--!strict
-- Damaging trails left by a walking boss (#99, PRD §3.5): The Big Cheese's melted cheese.
-- MiniBossService calls follow() when the boss spawns; a boss's Trail settings are in Bosses.luau.
--
--   * Every Trail.Spacing studs the boss walks, a flat puddle drops at its back edge.
--   * A puddle lasts Trail.Seconds and fades out over its last second.
--   * The chef standing in any puddle takes Trail.Damage, at most once every
--     Trail.HitCooldown seconds (standing in it doesn't stack hits).
--   * When the boss dies (or splits) it stops dropping puddles; the ones already down fade
--     normally. Only the chef is hurt.
--
-- Hits are flat distance checks (PRD §8.3), like everything else. Frozen while paused.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bosses = require(ReplicatedStorage.Config.Bosses)
local EnemyService = require(script.Parent.EnemyService)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)

local TrailService = {}

local CHEF_RADIUS = RunRules.ChefRadius
local FADE_SECONDS = 1 -- puddles fade out over their last second
local PUDDLE_TRANSPARENCY = 0.1
local PUDDLE_HEIGHT = 0.2

type Follower = {
	enemyId: number,
	trail: Bosses.BossTrail,
	lastDrop: Vector3?, -- where the last puddle dropped (flat), nil before the first
}
type Puddle = {
	position: Vector3, -- flat
	timeLeft: number,
	trail: Bosses.BossTrail,
	part: Part,
}

local followers: { Follower } = {}
local puddles: { Puddle } = {}
local hitCooldown = 0 -- seconds until any trail can hurt the chef again
local folder: Folder

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function getChefPosition(): Vector3?
	local player = Players:GetPlayers()[1]
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function getFloorY(): number
	local map = workspace:FindFirstChild("Map")
	local center = map and map:GetAttribute("ArenaCenter")
	return if typeof(center) == "Vector3" then center.Y else 0
end

local function dropPuddle(position: Vector3, trail: Bosses.BossTrail)
	local part = Instance.new("Part")
	part.Name = "TrailPuddle"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = trail.Color
	part.Transparency = PUDDLE_TRANSPARENCY
	-- A cylinder's length runs along X, so tip it on its side to lie flat on the floor.
	part.Size = Vector3.new(PUDDLE_HEIGHT, trail.Width, trail.Width)
	part.CFrame = CFrame.new(position.X, getFloorY() + PUDDLE_HEIGHT / 2 + 0.05, position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	part.Parent = folder
	table.insert(puddles, { position = position, timeLeft = trail.Seconds, trail = trail, part = part })
end

-- Start leaving `trail` behind enemy `enemyId` (until it dies or reset() is called).
function TrailService.follow(enemyId: number, trail: Bosses.BossTrail)
	table.insert(followers, { enemyId = enemyId, trail = trail, lastDrop = nil })
end

-- How many puddles are down right now (tests).
function TrailService.getPuddleCount(): number
	return #puddles
end

-- Take every trail and puddle away (a new run is starting).
function TrailService.reset()
	table.clear(followers)
	table.clear(puddles)
	hitCooldown = 0
	folder:ClearAllChildren()
end

local function update(deltaTime: number)
	if RunManager.isPaused() or RunManager.isRunOver() then
		return
	end

	-- Drop puddles behind each walking boss.
	for i = #followers, 1, -1 do
		local follower = followers[i]
		local position = EnemyService.getEnemyPosition(follower.enemyId)
		local enemyType = EnemyService.getEnemyType(follower.enemyId)
		local config = enemyType and EnemyService.getConfigForType(enemyType)
		local part = EnemyService.getEnemyPart(follower.enemyId)
		if not (position and config and part) then
			table.remove(followers, i) -- it died (or split): no more puddles
			continue
		end
		local here = flat(position)
		local lastDrop = follower.lastDrop
		if not lastDrop or (here - lastDrop).Magnitude >= follower.trail.Spacing then
			follower.lastDrop = here
			-- At its back edge, so the puddle comes out from under it as it walks on.
			local look = flat(part.CFrame.LookVector)
			local back = if look.Magnitude > 0.01 then -look.Unit else Vector3.zero
			dropPuddle(here + back * EnemyService.getHalfDepth(config), follower.trail)
		end
	end

	-- Age the puddles, and hurt the chef standing in one.
	hitCooldown -= deltaTime
	local chefPosition = getChefPosition()
	local chef = chefPosition and flat(chefPosition)
	local hitBy: Bosses.BossTrail? = nil
	for i = #puddles, 1, -1 do
		local puddle = puddles[i]
		puddle.timeLeft -= deltaTime
		if puddle.timeLeft <= 0 then
			puddle.part:Destroy()
			table.remove(puddles, i)
			continue
		end
		if puddle.timeLeft < FADE_SECONDS then
			local faded = 1 - puddle.timeLeft / FADE_SECONDS
			puddle.part.Transparency = PUDDLE_TRANSPARENCY + (1 - PUDDLE_TRANSPARENCY) * faded
		end
		if chef and not hitBy and (chef - puddle.position).Magnitude <= puddle.trail.Width / 2 + CHEF_RADIUS then
			hitBy = puddle.trail
		end
	end
	if hitBy and hitCooldown <= 0 then
		hitCooldown = hitBy.HitCooldown
		RunManager.damagePlayer(hitBy.Damage, "CheeseTrail")
	end
end

function TrailService:init()
	folder = Instance.new("Folder")
	folder.Name = "BossTrails"
	folder.Parent = workspace
end

function TrailService:start()
	RunService.Heartbeat:Connect(update)
end

return TrailService
