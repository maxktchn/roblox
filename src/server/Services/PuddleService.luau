--!strict
-- Slowing puddles left by enemies when they die (#117, PRD §3.4): the Rotten Tomato bursts
-- into one. An enemy's DeathPuddle settings are in Enemies.luau.
--
--   * When an enemy with a DeathPuddle dies (to anything), a flat puddle appears where it died.
--   * A puddle lasts DeathPuddle.Seconds and fades out over its last second.
--   * The chef standing in any puddle walks DeathPuddle.Slow slower (StatsService.setSlow).
--     Puddles don't stack: one or five, it's the strongest single slow. Leaving gives full
--     speed back straight away. No damage, and enemies aren't affected.
--   * At most RunRules.MaxPuddles on the floor; a new one removes the oldest.
--
-- Hits are flat distance checks (PRD §8.3), like everything else. Frozen while paused.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Enemies = require(ReplicatedStorage.Config.Enemies)
local EnemyService = require(script.Parent.EnemyService)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)
local StatsService = require(script.Parent.StatsService)

local PuddleService = {}

local CHEF_RADIUS = RunRules.ChefRadius
local FADE_SECONDS = 1 -- puddles fade out over their last second
local PUDDLE_TRANSPARENCY = 0.15
local PUDDLE_HEIGHT = 0.2

type Puddle = {
	position: Vector3, -- flat
	timeLeft: number,
	settings: Enemies.DeathPuddle,
	part: Part,
}

local puddles: { Puddle } = {} -- oldest first
local folder: Folder
local slowedSeconds = 0 -- this run, for the run report

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

local function removePuddle(index: number)
	puddles[index].part:Destroy()
	table.remove(puddles, index)
end

-- Put a puddle down at `position` (only X and Z are used).
function PuddleService.drop(position: Vector3, settings: Enemies.DeathPuddle)
	while #puddles >= RunRules.MaxPuddles do
		removePuddle(1) -- the oldest goes, so a big wave can't cover the arena
	end
	local part = Instance.new("Part")
	part.Name = "SlowPuddle"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = settings.Color
	part.Transparency = PUDDLE_TRANSPARENCY
	-- A cylinder's length runs along X, so tip it on its side to lie flat on the floor.
	-- A touch lower than the cheese trail, so the two don't flicker where they overlap.
	part.Size = Vector3.new(PUDDLE_HEIGHT, settings.Width, settings.Width)
	part.CFrame = CFrame.new(position.X, getFloorY() + PUDDLE_HEIGHT / 2 + 0.03, position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	part.Parent = folder
	table.insert(puddles, { position = flat(position), timeLeft = settings.Seconds, settings = settings, part = part })
end

-- How many puddles are down right now (tests).
function PuddleService.getPuddleCount(): number
	return #puddles
end

-- Seconds the chef has spent slowed this run (run report).
function PuddleService.getSlowedSeconds(): number
	return slowedSeconds
end

-- Take every puddle away and give the chef full speed back (a new run is starting).
function PuddleService.reset()
	table.clear(puddles)
	folder:ClearAllChildren()
	slowedSeconds = 0
	StatsService.setSlow(0)
end

local function update(deltaTime: number)
	if RunManager.isPaused() or RunManager.isRunOver() then
		return
	end
	local chefPosition = getChefPosition()
	local chef = chefPosition and flat(chefPosition)
	local slow = 0
	for i = #puddles, 1, -1 do
		local puddle = puddles[i]
		puddle.timeLeft -= deltaTime
		if puddle.timeLeft <= 0 then
			removePuddle(i)
			continue
		end
		if puddle.timeLeft < FADE_SECONDS then
			local faded = 1 - puddle.timeLeft / FADE_SECONDS
			puddle.part.Transparency = PUDDLE_TRANSPARENCY + (1 - PUDDLE_TRANSPARENCY) * faded
		end
		if chef and (chef - puddle.position).Magnitude <= puddle.settings.Width / 2 + CHEF_RADIUS then
			slow = math.max(slow, puddle.settings.Slow)
		end
	end
	if slow > 0 then
		slowedSeconds += deltaTime
	end
	StatsService.setSlow(slow)
end

function PuddleService:init()
	folder = Instance.new("Folder")
	folder.Name = "SlowPuddles"
	folder.Parent = workspace
end

function PuddleService:start()
	EnemyService.onEnemyKilled(function(_enemyId, enemyType, position)
		local config = EnemyService.getConfigForType(enemyType)
		local settings = config and config.DeathPuddle
		if settings then
			PuddleService.drop(position, settings)
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return PuddleService
