--!strict
-- Elites (#120, PRD §3.4): bigger, glowing, tougher versions of normal enemies that arrive on
-- the chapter's schedule (Chapters.luau Elites) and always drop a Lunchbox (PickupService).
--
--   * At each scheduled run-clock time, one elite spawns where normal enemies spawn. It's a
--     random enemy from the current phase that CanBeElite (Enemies.luau), so never Fruit Flies.
--   * Its numbers come from RunRules (Elite... values) via EnemyService.spawnElite.
--   * Only the clock counting up counts: time held for The Big Cheese doesn't move the
--     schedule on, and a dev jump of the clock skips the elites it jumps over.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Chapters = require(ReplicatedStorage.Config.Chapters)
local EnemyService = require(script.Parent.EnemyService)
local RunManager = require(script.Parent.RunManager)

local EliteService = {}

-- A clock change bigger than this in one frame is a dev jump, not time passing.
local JUMP_SECONDS = 1

local nextIndex = 1 -- the next scheduled elite
local lastSeconds = 0 -- the run clock last frame
local spawnedCount = 0 -- this run, for the run report
local killTimes: { number } = {} -- run-clock time each elite died, for the run report
local random = Random.new()

local function getChefPosition(): Vector3?
	local player = Players:GetPlayers()[1]
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function getSchedule(): { number }
	return Chapters[RunManager.getChapter()].Elites or {}
end

-- Spawn one elite from the current phase's enemies. Returns its id, or nil if none can be elite.
function EliteService.spawnNow(): number?
	local chefPosition = getChefPosition()
	if not chefPosition then
		return nil
	end
	local choices = {}
	for _, enemyType in RunManager.getSpawnTypes() do
		local config = EnemyService.getConfigForType(enemyType)
		if config and config.CanBeElite then
			table.insert(choices, enemyType)
		end
	end
	if #choices == 0 then
		return nil
	end
	local enemyType = choices[random:NextInteger(1, #choices)]
	local id = EnemyService.spawnElite(enemyType, EnemyService.getSpawnPoint(chefPosition))
	if id then
		spawnedCount += 1
	end
	return id
end

-- How many elites came this run, and the run-clock time each killed one died.
function EliteService.getStats(): (number, { number })
	return spawnedCount, table.clone(killTimes)
end

-- Start the schedule again (a new run).
function EliteService.reset()
	nextIndex = 1
	lastSeconds = 0
	spawnedCount = 0
	table.clear(killTimes)
end

local function update()
	if RunManager.isPaused() or RunManager.isRunOver() or RunManager.isClockHeld() then
		return
	end
	local seconds = RunManager.getRunSeconds()
	local schedule = getSchedule()
	if math.abs(seconds - lastSeconds) > JUMP_SECONDS then
		-- The clock was jumped (a dev tool or a restart): skip to the next elite after it.
		nextIndex = #schedule + 1
		for index, at in schedule do
			if at > seconds then
				nextIndex = index
				break
			end
		end
	else
		while schedule[nextIndex] and seconds >= schedule[nextIndex] do
			nextIndex += 1
			EliteService.spawnNow()
		end
	end
	lastSeconds = seconds
end

function EliteService:start()
	EnemyService.onEnemyKilled(function(_enemyId, enemyType)
		local config = EnemyService.getConfigForType(enemyType)
		if config and config.IsElite then
			table.insert(killTimes, RunManager.getRunSeconds())
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return EliteService
