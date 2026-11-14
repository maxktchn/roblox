--!strict
-- Contact damage: enemies touching the chef hurt them (PRD §3.4, issue #9).
--
-- Touching is a distance check, never a physics .Touched (PRD §8.3): an enemy touches the
-- chef when it is within the chef's radius + half its own width + RunRules.ContactReach.
-- (EnemyService stops chasing enemies at exactly the chef's radius + half their width.)
--
-- After a hit the chef can't be hurt again for RunRules.ChefHurtCooldown seconds, and only
-- the strongest touching enemy's Damage counts, so a crowd wears HP down at a steady pace.
-- Armor and death are handled by RunManager.damagePlayer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EnemyService = require(script.Parent.EnemyService)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)

local ContactService = {}

local CHEF_RADIUS = 1.5 -- same as EnemyService's: roughly how wide the chef is

local hurtCooldown = 0 -- seconds until the chef can be hurt again
local searchRadius = CHEF_RADIUS -- widest possible touch distance, worked out in init

local function getChefPosition(): Vector3?
	local player = Players:GetPlayers()[1]
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function update(deltaTime: number)
	if RunManager.isPaused() or RunManager.isRunOver() then
		return -- frozen with everything else
	end
	hurtCooldown -= deltaTime
	if hurtCooldown > 0 then
		return
	end
	local chefPosition = getChefPosition()
	if not chefPosition then
		return
	end

	-- Find the strongest enemy touching the chef.
	local strongest = 0
	local strongestType: string? = nil -- which enemy it was, for the run report
	local cooldown = RunRules.ChefHurtCooldown
	for _, enemyId in EnemyService.getEnemiesInRadius(chefPosition, searchRadius) do
		local enemyType = EnemyService.getEnemyType(enemyId)
		local position = EnemyService.getEnemyPosition(enemyId)
		local config = enemyType and EnemyService.getConfigForType(enemyType) -- bosses too
		if config and position then
			local touchDistance = CHEF_RADIUS + config.Size.X / 2 + RunRules.ContactReach
			local distance = Vector3.new(position.X - chefPosition.X, 0, position.Z - chefPosition.Z).Magnitude
			-- Damage grows with run time (PRD §3.4), so read the enemy's own value, not the config's.
			local damage = EnemyService.getEnemyDamage(enemyId) or config.Damage
			if distance <= touchDistance and damage > strongest then
				strongest = damage
				strongestType = enemyType
				-- Hard hitters (the boss) can set their own, longer wait between hits.
				cooldown = config.HurtCooldown or RunRules.ChefHurtCooldown
			end
		end
	end

	if strongest > 0 then
		RunManager.damagePlayer(strongest, strongestType)
		hurtCooldown = cooldown
	end
end

function ContactService:init()
	-- The widest enemy (or boss) decides how far around the chef we need to look.
	searchRadius = CHEF_RADIUS + EnemyService.getMaxEnemyWidth() / 2 + RunRules.ContactReach
end

function ContactService:start()
	RunService.Heartbeat:Connect(update)
end

return ContactService
