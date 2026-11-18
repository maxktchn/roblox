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
--   "JustUnlockedStarter" = "<starter name>" the same for a starter (#151)
--
-- Chapters and starters (P2-6e, #151): when a run ends, a won run's chapter is saved as
-- cleared (data.Unlocks.Cleared), and every MVP starter whose UnlockRule (Starters.luau) is now
-- met is given once: a Common Lv 1 copy goes into the gear inventory, marked New, and its id
-- goes into data.Unlocks.Starters so it's never given again. This happens before the run's
-- RunState changes (RunManager.onRunEnded), so the run-end save includes it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossPowers = require(ReplicatedStorage.Config.BossPowers)
local Bosses = require(ReplicatedStorage.Config.Bosses)
local DataService = require(script.Parent.DataService)
local EnemyService = require(script.Parent.EnemyService)
local GearService = require(script.Parent.GearService)
local RunManager = require(script.Parent.RunManager)
local Starters = require(ReplicatedStorage.Config.Starters)

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

-- The player left: forget the unlocks in memory, so a next player in this server can't have
-- them merged into their save. (Their own unlocks are already in their save.)
function UnlockService.forgetPlayer()
	table.clear(unlocked)
end

-- A new run is starting: the win banner shouldn't announce the last run's unlock again.
function UnlockService.clearJustUnlocked()
	local player = getRunPlayer()
	if player then
		player:SetAttribute("JustUnlocked", nil)
		player:SetAttribute("JustUnlockedStarter", nil)
	end
end

-- The save's Unlocks section, with both lists there (a new save starts with an empty table).
local function getUnlocks(data: DataService.Data): { Cleared: { [string]: boolean }, Starters: { [string]: boolean } }
	local unlocks = data.Unlocks
	unlocks.Cleared = unlocks.Cleared or {}
	unlocks.Starters = unlocks.Starters or {}
	return unlocks :: any
end

-- Chapters this player has won at least once (empty before the save loads).
function UnlockService.getClearedChapters(): { [string]: boolean }
	local player = getRunPlayer()
	local data = player and DataService.get(player)
	return if data then table.clone(getUnlocks(data).Cleared) else {}
end

-- Is this starter's UnlockRule met by the save (and this run's kills, not yet counted in it)?
local function ruleMet(rule: Starters.UnlockRule, unlocks: any, kills: number): boolean
	if rule.Kind == "ClearChapter" then
		return rule.Chapter ~= nil and unlocks.Cleared[rule.Chapter] == true
	end
	return rule.Count ~= nil and kills >= rule.Count
end

-- A run ended: save a cleared chapter and give any starter just earned.
local function onRunEnded(result: "Won" | "Lost")
	local player = getRunPlayer()
	local data = player and DataService.get(player)
	if not (player and data) then
		return -- the save hasn't loaded: nothing can be recorded
	end
	local unlocks = getUnlocks(data)
	if result == "Won" then
		unlocks.Cleared[RunManager.getChapter()] = true
	end
	local runKills = player:GetAttribute("Kills")
	local kills = data.Lifetime.Kills + (if type(runKills) == "number" then runKills else 0)
	local ids = {}
	for id in Starters do
		table.insert(ids, id)
	end
	table.sort(ids) -- the same order every time
	local names = {}
	for _, id in ids do
		local starter = Starters[id]
		local rule = starter.UnlockRule
		if starter.Mvp and rule and not unlocks.Starters[id] and ruleMet(rule, unlocks, kills) then
			local itemId = GearService.give(player, id, "Common", 1)
			if itemId then
				data.Gear.Items[itemId].New = true
				unlocks.Starters[id] = true
				table.insert(names, starter.Name)
			end
		end
	end
	if #names > 0 then
		player:SetAttribute("JustUnlockedStarter", table.concat(names, ", "))
		GearService.sendState(player)
	end
end

-- DEV: forget cleared chapters and given starters, so clearing Chapter 1 gives the Rolling Pin
-- again. Items already given are kept.
function UnlockService.resetUnlocks(player: Player)
	local data = DataService.get(player)
	if data then
		data.Unlocks = { Cleared = {}, Starters = {} }
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
	RunManager.onRunEnded(onRunEnded)
	Players.PlayerAdded:Connect(syncAttributes)
	Players.PlayerRemoving:Connect(UnlockService.forgetPlayer)
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
