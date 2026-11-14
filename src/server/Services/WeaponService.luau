--!strict
-- Fires the player's starter, gadgets and recipe weapons on cooldowns; applies ingredient stats. Server decides all damage (PRD §8.4).
--
-- Every weapon has a Shape in config (see Shared/WeaponTypes): Arc, Aura, Orbit or Projectile.
-- There is one attack function per shape below, so new weapons are config-only (PRD §8.5).
--
-- Each frame, every owned weapon counts down its cooldown. At 0 it attacks: the server
-- finds the enemies it hits and damages them, then tells the client to draw the effect
-- (WeaponFx). The client never decides what was hit.
--
-- Owned weapon levels are also copied onto the player as attributes ("Weapon_<id>" = level),
-- so the client can draw always-on effects (orbiting forks) and the HUD can show icons (#21).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EnemyService = require(script.Parent.EnemyService)
local Gadgets = require(ReplicatedStorage.Config.Gadgets)
local Recipes = require(ReplicatedStorage.Config.Recipes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)
local Starters = require(ReplicatedStorage.Config.Starters)
local StatsService = require(script.Parent.StatsService)
local WeaponTypes = require(ReplicatedStorage.Shared.WeaponTypes)

type WeaponLevel = WeaponTypes.WeaponLevel

local WeaponService = {}

-- Weapon id -> current level (1 to 5). The run starts with the starter at Lv 1.
local levels: { [string]: number } = {}
-- Weapon id -> seconds until it can attack again.
local cooldowns: { [string]: number } = {}

-- Burning enemies (Pepper Shaker). Enemy id -> burn state.
type Burn = { dps: number, timeLeft: number, tickTimer: number }
local burns: { [number]: Burn } = {}

-- Orbit weapons: weapon id -> (enemy id -> time it can be hit again).
local orbitHitTimes: { [string]: { [number]: number } } = {}

-- Shots in flight (Toaster). The client draws its own copy of each one.
type Shot = {
	id: number,
	weaponId: string,
	position: Vector3,
	direction: Vector3,
	speed: number,
	traveled: number,
	maxDistance: number,
	damage: number,
}
local shots: { Shot } = {}
local lastShotId = 0

local kills = 0 -- enemies defeated this run (shown on the HUD)

local weaponFx: RemoteEvent

-- The run's one player (PRD §8.1), or nil before they join.
local function getRunPlayer(): Player?
	return Players:GetPlayers()[1]
end

-- The chef's root part, or nil while there is no living chef.
local function getChef(): BasePart?
	local player = getRunPlayer()
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- A weapon's config entry, from Starters, Gadgets or Recipes.
local function getWeaponConfig(weaponId: string): (WeaponTypes.Shape?, { WeaponLevel }?)
	local config: any = Starters[weaponId] or Gadgets[weaponId] or Recipes[weaponId]
	if not config then
		return nil, nil
	end
	return config.Shape, config.Levels
end

-- Tell the client to draw an effect. Visual only.
local function sendFx(weaponId: string, ...: any)
	local player = getRunPlayer()
	if player then
		weaponFx:FireClient(player, weaponId, ...)
	end
end

-- Final damage for one hit: base damage + Hot Sauce bonus, and a crit roll (Salt, plus
-- the weapon's own CritBonus if it has one, e.g. Sushi Master Blade).
-- Rolled separately for every enemy hit, so a big swing can mix crits and normal hits.
local function rollDamage(baseDamage: number, critBonus: number?): number
	local damage = baseDamage * (1 + StatsService.getStat("Damage"))
	if math.random() < StatsService.getStat("CritChance") + (critBonus or 0) then
		damage *= RunRules.CritDamageMultiplier
	end
	return damage
end

-- Hit one enemy with a weapon: damage now, plus a burn if the weapon has one.
local function hit(enemyId: number, stats: WeaponLevel)
	EnemyService.damage(enemyId, rollDamage(stats.Damage, stats.CritBonus))
	if stats.BurnDps and stats.BurnSeconds and EnemyService.getEnemyPosition(enemyId) then
		local burn = burns[enemyId]
		if burn then
			-- Already burning: keep the stronger burn and restart the timer.
			burn.dps = math.max(burn.dps, stats.BurnDps)
			burn.timeLeft = stats.BurnSeconds
		else
			burns[enemyId] = { dps = stats.BurnDps, timeLeft = stats.BurnSeconds, tickTimer = RunRules.BurnTickSeconds }
		end
	end
end

-- Flat distance (X and Z only) between two points, matching EnemyService.
local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- ARC: hit every enemy inside a slice of circle in front of the chef.
local function attackArc(weaponId: string, stats: WeaponLevel, root: BasePart)
	local origin = root.Position
	-- Facing direction, flattened so looking slightly up/down doesn't matter.
	local look = root.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z).Unit
	local arcDegrees = stats.ArcDegrees or 90
	-- An enemy is inside the arc if the angle to it is at most half the arc width.
	-- Comparing dot products avoids computing angles: dot >= cos(half arc).
	local minDot = math.cos(math.rad(arcDegrees / 2))

	for _, enemyId in EnemyService.getEnemiesInRadius(origin, stats.Range) do
		local position = EnemyService.getEnemyPosition(enemyId)
		if position then
			local offset = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
			-- An enemy standing right on the chef counts as hit (no direction to check).
			if offset.Magnitude < 0.01 or facing:Dot(offset.Unit) >= minDot then
				hit(enemyId, stats)
			end
		end
	end
	sendFx(weaponId, facing, stats.Range, arcDegrees)
end

-- AURA: hit every enemy in a circle around the chef.
local function attackAura(weaponId: string, stats: WeaponLevel, root: BasePart)
	for _, enemyId in EnemyService.getEnemiesInRadius(root.Position, stats.Range) do
		hit(enemyId, stats)
	end
	sendFx(weaponId, stats.Range)
end

-- PROJECTILE: fire one shot at each of the nearest `Count` enemies in range.
local function attackProjectile(weaponId: string, stats: WeaponLevel, root: BasePart)
	local origin = root.Position
	-- Sort the enemies in range by distance and take the closest few.
	local targets = {}
	for _, enemyId in EnemyService.getEnemiesInRadius(origin, stats.Range) do
		local position = EnemyService.getEnemyPosition(enemyId)
		if position then
			table.insert(targets, { position = position, distance = flatDistance(position, origin) })
		end
	end
	table.sort(targets, function(a, b)
		return a.distance < b.distance
	end)

	for i = 1, math.min(stats.Count or 1, #targets) do
		local toTarget = targets[i].position - origin
		if toTarget.Magnitude > 0.01 then
			lastShotId += 1
			local shot: Shot = {
				id = lastShotId,
				weaponId = weaponId,
				position = origin,
				direction = toTarget.Unit,
				speed = stats.Speed or 40,
				traveled = 0,
				maxDistance = stats.Range,
				damage = stats.Damage,
			}
			table.insert(shots, shot)
			sendFx(weaponId, "Launch", shot.id, origin, shot.direction, shot.speed, shot.maxDistance)
		end
	end
end

-- Move every shot; a shot hits the first enemy it comes close to, or ends at max distance.
local function updateShots(deltaTime: number)
	-- Walk backwards so removing a shot doesn't skip the next one.
	for i = #shots, 1, -1 do
		local shot = shots[i]
		local step = shot.speed * deltaTime
		shot.position += shot.direction * step
		shot.traveled += step

		local targets = EnemyService.getEnemiesInRadius(shot.position, RunRules.ProjectileHitRadius)
		local target = targets[1]
		if target then
			EnemyService.damage(target, rollDamage(shot.damage))
		end
		if target or shot.traveled >= shot.maxDistance then
			table.remove(shots, i)
			sendFx(shot.weaponId, "End", shot.id)
		end
	end
end

-- ORBIT: `Count` objects circle the chef. Their angle comes from the shared server clock,
-- so the client can draw them in the same spots without any messages (see WeaponFxController).
local function updateOrbit(weaponId: string, stats: WeaponLevel, root: BasePart)
	local count = stats.Count or 1
	local now = workspace:GetServerTimeNow()
	local hitTimes = orbitHitTimes[weaponId]
	if not hitTimes then
		hitTimes = {}
		orbitHitTimes[weaponId] = hitTimes
	end

	-- Only enemies near the circle can be touched, so check those.
	local nearby = EnemyService.getEnemiesInRadius(root.Position, stats.Range + RunRules.OrbitHitRadius)
	for i = 0, count - 1 do
		local angle = math.rad(now * (stats.Speed or 180) + i * 360 / count)
		local forkPosition = root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * stats.Range
		for _, enemyId in nearby do
			local position = EnemyService.getEnemyPosition(enemyId)
			local readyAt = hitTimes[enemyId] or 0
			if position and now >= readyAt and flatDistance(position, forkPosition) <= RunRules.OrbitHitRadius then
				hit(enemyId, stats)
				hitTimes[enemyId] = now + stats.Cooldown -- one fork hit per enemy per Cooldown
			end
		end
	end

	-- Forget enemies that can be hit again (also drops dead ones), so the table stays small.
	for enemyId, readyAt in hitTimes do
		if now >= readyAt then
			hitTimes[enemyId] = nil
		end
	end
end

-- Burn damage ticks.
local function updateBurns(deltaTime: number)
	for enemyId, burn in burns do
		if not EnemyService.getEnemyPosition(enemyId) then
			burns[enemyId] = nil -- enemy died
			continue
		end
		burn.timeLeft -= deltaTime
		burn.tickTimer -= deltaTime
		if burn.tickTimer <= 0 then
			burn.tickTimer += RunRules.BurnTickSeconds
			-- Burns get Hot Sauce but can't crit.
			local damage = burn.dps * RunRules.BurnTickSeconds * (1 + StatsService.getStat("Damage"))
			EnemyService.damage(enemyId, damage)
		end
		if burn.timeLeft <= 0 then
			burns[enemyId] = nil
		end
	end
end

-- Shapes that attack on a cooldown. (Orbit is always on, so it's handled separately.)
local ATTACKS: { [string]: (string, WeaponLevel, BasePart) -> () } = {
	Arc = attackArc,
	Aura = attackAura,
	Projectile = attackProjectile,
}

local function update(deltaTime: number)
	if RunManager.isPaused() then
		return -- "Order Up!" is on screen: cooldowns, shots and burns all freeze
	end
	updateShots(deltaTime)
	updateBurns(deltaTime)

	local root = getChef()
	if not root then
		return -- no living chef: weapons wait
	end
	for weaponId, level in levels do
		local shape, weaponLevels = getWeaponConfig(weaponId)
		local stats = weaponLevels and weaponLevels[level]
		if not (shape and stats) then
			continue -- not playable yet (no numbers in config)
		end
		if shape == "Orbit" then
			updateOrbit(weaponId, stats, root) -- always on, no cooldown to wait for
			continue
		end
		cooldowns[weaponId] = (cooldowns[weaponId] or 0) - deltaTime
		if cooldowns[weaponId] <= 0 then
			ATTACKS[shape](weaponId, stats, root)
			cooldowns[weaponId] = stats.Cooldown
		end
	end
end

-- Copy owned weapon levels onto the player as "Weapon_<id>" attributes (nil = not owned).
local function syncAttributes()
	local player = getRunPlayer()
	if not player then
		return
	end
	for id in Starters do
		player:SetAttribute(`Weapon_{id}`, levels[id])
	end
	for id in Gadgets do
		player:SetAttribute(`Weapon_{id}`, levels[id])
	end
	for id in Recipes do
		player:SetAttribute(`Weapon_{id}`, levels[id])
	end
end

-- Set a weapon's level (UpgradeService calls this when a card is taken).
function WeaponService.setWeaponLevel(weaponId: string, level: number)
	levels[weaponId] = level
	syncAttributes()
end

-- Swap one weapon for another in the same slot (a recipe replacing its weapon, PRD §2.5).
-- The new weapon starts at Lv 1 and attacks straight away.
function WeaponService.replaceWeapon(oldId: string, newId: string)
	levels[oldId] = nil
	cooldowns[oldId] = nil
	orbitHitTimes[oldId] = nil
	levels[newId] = 1
	syncAttributes()
end

-- Every owned weapon id -> level. A copy, so changing it changes nothing here.
function WeaponService.getOwnedWeapons(): { [string]: number }
	return table.clone(levels)
end

-- Forget all weapons and give back the starter at Lv 1 (start of a new run).
function WeaponService.reset()
	table.clear(levels)
	table.clear(cooldowns)
	table.clear(burns)
	table.clear(orbitHitTimes)
	for _, shot in shots do
		sendFx(shot.weaponId, "End", shot.id)
	end
	table.clear(shots)
	levels[RunRules.Starter] = 1
	kills = 0
	local player = getRunPlayer()
	if player then
		player:SetAttribute("Kills", 0)
	end
	syncAttributes()
end

-- Current level of a weapon, or nil if the player doesn't own it.
function WeaponService.getWeaponLevel(weaponId: string): number?
	return levels[weaponId]
end

function WeaponService:init()
	table.clear(levels)
	levels[RunRules.Starter] = 1
end

function WeaponService:start()
	weaponFx = Remotes.get("WeaponFx")
	syncAttributes()
	Players.PlayerAdded:Connect(syncAttributes)
	RunService.Heartbeat:Connect(update)

	-- Kill count for the HUD, as the player's "Kills" attribute. Counted here because this
	-- service already listens to EnemyService (RunManager can't: EnemyService requires it).
	EnemyService.onEnemyKilled(function()
		kills += 1
		local player = getRunPlayer()
		if player then
			player:SetAttribute("Kills", kills)
		end
	end)
end

return WeaponService
