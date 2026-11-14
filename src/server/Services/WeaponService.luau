--!strict
-- Fires the player's starter, gadgets and recipe weapons on cooldowns; applies ingredient stats. Server decides all damage (PRD §8.4).
--
-- Each frame, every owned weapon counts down its cooldown. At 0 it attacks:
-- the server finds the enemies it hits, damages them, then tells the client to
-- draw the effect (WeaponFx). The client never decides what was hit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EnemyService = require(script.Parent.EnemyService)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunRules = require(ReplicatedStorage.Config.RunRules)
local Starters = require(ReplicatedStorage.Config.Starters)
local StatsService = require(script.Parent.StatsService)

local WeaponService = {}

-- Weapon id -> current level (1 to 5). The run starts with the starter at Lv 1.
local levels: { [string]: number } = {}
-- Weapon id -> seconds until it can attack again.
local cooldowns: { [string]: number } = {}

local weaponFx: RemoteEvent

-- The chef's root part, or nil while there is no living chef.
-- Each run server has exactly one player (PRD §8.1).
local function getChef(): BasePart?
	local player = Players:GetPlayers()[1]
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Final damage for one hit: base damage + Hot Sauce bonus, and a crit roll (Salt).
-- Rolled separately for every enemy hit, so a big swing can mix crits and normal hits.
local function rollDamage(baseDamage: number): number
	local damage = baseDamage * (1 + StatsService.getStat("Damage"))
	if math.random() < StatsService.getStat("CritChance") then
		damage *= RunRules.CritDamageMultiplier
	end
	return damage
end

-- Chef's Knife: hit every enemy inside a slice of circle in front of the chef.
local function slash(weaponId: string, stats: Starters.WeaponLevel, root: BasePart)
	local origin = root.Position
	-- Facing direction, flattened so looking slightly up/down doesn't matter.
	local look = root.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z).Unit
	-- An enemy is inside the arc if the angle to it is at most half the arc width.
	-- Comparing dot products avoids computing angles: dot >= cos(half arc).
	local minDot = math.cos(math.rad(stats.ArcDegrees / 2))

	for _, enemyId in EnemyService.getEnemiesInRadius(origin, stats.Range) do
		local position = EnemyService.getEnemyPosition(enemyId)
		if position then
			local offset = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
			-- An enemy standing right on the chef counts as hit (no direction to check).
			if offset.Magnitude < 0.01 or facing:Dot(offset.Unit) >= minDot then
				EnemyService.damage(enemyId, rollDamage(stats.Damage))
			end
		end
	end

	local player = Players:GetPlayers()[1]
	if player then
		weaponFx:FireClient(player, weaponId, facing, stats.Range, stats.ArcDegrees)
	end
end

local function update(deltaTime: number)
	local root = getChef()
	if not root then
		return -- no living chef: weapons wait
	end
	for weaponId, level in levels do
		cooldowns[weaponId] = (cooldowns[weaponId] or 0) - deltaTime
		if cooldowns[weaponId] <= 0 then
			local starter = Starters[weaponId]
			local stats = starter and starter.Levels and starter.Levels[level]
			if stats then
				slash(weaponId, stats, root)
				cooldowns[weaponId] = stats.Cooldown
			end
		end
	end
end

-- Set a weapon's level (UpgradeService calls this when a card is taken, #16).
function WeaponService.setWeaponLevel(weaponId: string, level: number)
	levels[weaponId] = level
end

-- Current level of a weapon, or nil if the player doesn't own it.
function WeaponService.getWeaponLevel(weaponId: string): number?
	return levels[weaponId]
end

function WeaponService:init()
	levels[RunRules.Starter] = 1
end

function WeaponService:start()
	weaponFx = Remotes.get("WeaponFx")
	RunService.Heartbeat:Connect(update)
end

return WeaponService
