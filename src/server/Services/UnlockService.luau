--!strict
-- Boss power unlocks (PRD §3.8, issue #65). Beating a chapter's final boss unlocks the boss
-- power named by its `Power` in Bosses.luau. Only a defeated boss unlocks it: the boss dying
-- fires EnemyService.onEnemyKilled, which a lost fight or a cleared arena never does.
--
-- Saved (P2-1, #112): the in-memory set below is what the game uses. When the player's save
-- loads (DataService.onLoaded), saved unlocks join it, and any unlocked before the load finished
-- are written into the save. unlock() and lock() also update the save's BossPowers section.
-- The run-end save writes it: a power unlocks when the boss dies, which is when the run ends.
--
-- Player attributes set here:
--   "Unlocked_<id>" = true          for every unlocked power (UI can show what's unlocked)
--   "JustUnlocked"  = "<power name>" set when this run unlocked something new, so the win
--                                    banner can announce it; cleared when a new run starts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossPowers = require(ReplicatedStorage.Config.BossPowers)
local Bosses = require(ReplicatedStorage.Config.Bosses)
local DataService = require(script.Parent.DataService)
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
	local data = player and DataService.get(player)
	if data then
		data.BossPowers[id] = true
	end
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
	local data = player and DataService.get(player)
	if data then
		data.BossPowers[id] = nil
	end
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

	-- The save loaded: saved unlocks join the in-memory set (ids no longer in BossPowers are
	-- left in the save but not unlocked), and unlocks gained before the load are saved too.
	DataService.onLoaded(function(_player, data)
		for id in data.BossPowers do
			if BossPowers[id] then
				unlocked[id] = true
			end
		end
		for id in unlocked do
			data.BossPowers[id] = true
		end
		syncAttributes()
	end)
end

return UnlockService
