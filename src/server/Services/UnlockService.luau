--!strict
-- Boss power unlocks (PRD §3.8, issue #65). Beating a chapter's final boss unlocks the boss
-- power named by its `Power` in Bosses.luau. Only a defeated boss unlocks it: the boss dying
-- fires EnemyService.onEnemyKilled, which a lost fight or a cleared arena never does.
--
-- Phase 1: unlocks live in memory, so they last until the server closes and survive
-- "Play again". Phase 2 saving: DataService loads the saved list into this service when the
-- player joins and saves it when it changes. This is the only place that knows unlocks, so
-- nothing else needs to change.
--
-- Player attributes set here:
--   "Unlocked_<id>" = true          for every unlocked power (UI can show what's unlocked)
--   "JustUnlocked"  = "<power name>" set when this run unlocked something new, so the win
--                                    banner can announce it; cleared when a new run starts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossPowers = require(ReplicatedStorage.Config.BossPowers)
local Bosses = require(ReplicatedStorage.Config.Bosses)
local EnemyService = require(script.Parent.EnemyService)

local UnlockService = {}

local unlocked: { [string]: boolean } = {}

local function getRunPlayer(): Player?
	return Players:GetPlayers()[1]
end

-- Copy every unlock onto the player as attributes (e.g. after they join).
local function syncAttributes()
	local player = getRunPlayer()
	if player then
		for id in unlocked do
			player:SetAttribute(`Unlocked_{id}`, true)
		end
	end
end

-- Unlock a boss power. Returns true only if it wasn't unlocked before.
function UnlockService.unlock(id: string): boolean
	local power = BossPowers[id]
	if not power or unlocked[id] then
		return false
	end
	unlocked[id] = true
	local player = getRunPlayer()
	if player then
		player:SetAttribute(`Unlocked_{id}`, true)
		player:SetAttribute("JustUnlocked", power.Name)
	end
	return true
end

-- Lock a boss power again. Dev only: the playtest bot (PlaytestBotService) uses it so a win
-- in one bot run doesn't hand the next run a power. Players never lose an unlock.
function UnlockService.lock(id: string)
	unlocked[id] = nil
	local player = getRunPlayer()
	if player then
		player:SetAttribute(`Unlocked_{id}`, nil)
	end
end

function UnlockService.isUnlocked(id: string): boolean
	return unlocked[id] == true
end

-- Every unlocked power id, sorted (for saving later, and for tests).
function UnlockService.getUnlocked(): { string }
	local ids = {}
	for id in unlocked do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- A new run is starting: the win banner shouldn't announce the last run's unlock again.
function UnlockService.clearJustUnlocked()
	local player = getRunPlayer()
	if player then
		player:SetAttribute("JustUnlocked", nil)
	end
end

function UnlockService:start()
	-- A boss with a Power was defeated: take its power.
	EnemyService.onEnemyKilled(function(_enemyId, enemyType)
		local boss = Bosses[enemyType]
		if boss and boss.Power then
			UnlockService.unlock(boss.Power)
		end
	end)
	Players.PlayerAdded:Connect(syncAttributes)
	syncAttributes()
end

return UnlockService
