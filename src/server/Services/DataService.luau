--!strict
-- Loads and saves each player's data (PRD §8.2, P2-1 #102, design:
-- docs/superpowers/specs/2026-11-17-saving-design.md).
--
-- This is the ONLY file that touches the save. It uses ProfileStore (third-party, in vendor/),
-- which locks a player's save to one server at a time, saves every few minutes, and saves when
-- the player leaves or the server shuts down.
--
-- Other services never touch ProfileStore. They:
--   * DataService.onLoaded(fn)  get told when a player's save is ready, and copy their section
--   * DataService.get(player)   read and change ONLY their own section of the save table
--
-- Rules (decided in #102):
--   * Nothing a run earns goes into the save before the run ends. Quitting mid-run loses it.
--   * If the save can't load within Saving.LoadTimeoutSeconds, the player plays anyway with a
--     fresh copy of the template, SaveStatus "Off", and that session is never saved, so their
--     real save stays safe.
--   * Before launch, changing Saving.SaveSlot wipes everyone. Studio uses its own store.
--
-- When a run ends (RunState becomes "Won" or "Lost") the Lifetime stats count it and a save is
-- requested. Run rewards (#106) will add their payout at the same moment.
--
-- Player attributes:
--   "SaveStatus"  set here: "Loading", then "On" (saving) or "Off" (playing without saving)
--   "LifetimeRuns", "LifetimeWins", "BestWinSeconds"  set here from the save's Lifetime stats, on
--                 load and after every finished run (the lobby's Home screen shows them, P2-8)
--   read here:    "RunState" and "RunSeconds" (RunManager), "Kills" (WeaponService)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

-- Third-party and not --!strict, so it's typed loosely here.
local GearMath = require(ReplicatedStorage.Shared.GearMath)
local ProfileStore = require(ServerScriptService.ProfileStore) :: any
local Saving = require(ReplicatedStorage.Config.Saving)

local DataService = {}

-- The save file, version 1. ProfileStore can't store nil, so "none yet" is 0 or {}.
-- Later Phase 2 topics fill in their own reserved section (Currencies, Gear, Talents, Unlocks).
export type Data = {
	Version: number,
	BossPowers: { [string]: boolean }, -- [powerId] = true (UnlockService)
	Lifetime: {
		Kills: number, -- enemies killed in finished runs
		RunsPlayed: number, -- finished runs, won or lost
		RunsWon: number,
		BestWinSeconds: number, -- fastest win's run clock; 0 = no win yet
	},
	-- Gold and the 5 gear materials (P2-4). GearService changes them; others go through it.
	Currencies: { [string]: number },
	-- Owned gear and what's equipped (P2-4, GearService only). Item ids are strings because
	-- DataStores can't hold gappy number keys.
	Gear: {
		NextId: number,
		Items: { [string]: GearMath.ItemRecord },
		Equipped: { [string]: string }, -- [slot] = item id; a missing slot is empty
	},
	Talents: { [string]: any }, -- account level, XP and talent nodes (#108)
	Unlocks: { [string]: any }, -- chapters and starters (#107)
}

local TEMPLATE: Data = {
	Version = 1,
	BossPowers = {},
	Lifetime = { Kills = 0, RunsPlayed = 0, RunsWon = 0, BestWinSeconds = 0 },
	Currencies = { Gold = 0, Sharpener = 0, HatPattern = 0, ApronPattern = 0, MittPattern = 0, ShoePattern = 0 },
	Gear = { NextId = 1, Items = {}, Equipped = {} }, -- GearService gives the free knife on load
	Talents = {},
	Unlocks = {},
}

type Session = {
	profile: any?, -- the ProfileStore profile; nil when saving is off
	data: Data,
}

local sessions: { [Player]: Session } = {}
local loadedCallbacks: { (Player, Data) -> () } = {}
-- Counts loads per player, so an older load that finishes late (after a reload or a leave)
-- knows it's out of date and lets go of its profile.
local loadNumber: { [Player]: number } = {}
local store: any

-- A deep copy of the template (the save when saving is off).
local function copyTemplate(): Data
	local function copy(value: any): any
		if type(value) ~= "table" then
			return value
		end
		local result = {}
		for key, inner in value do
			result[key] = copy(inner)
		end
		return result
	end
	return copy(TEMPLATE)
end

local function setStatus(player: Player, status: string)
	player:SetAttribute("SaveStatus", status)
end

-- Copy the lifetime stats onto the player for the lobby's Home screen.
local function syncLifetime(player: Player, data: Data)
	player:SetAttribute("LifetimeRuns", data.Lifetime.RunsPlayed)
	player:SetAttribute("LifetimeWins", data.Lifetime.RunsWon)
	player:SetAttribute("BestWinSeconds", data.Lifetime.BestWinSeconds)
end

local function announceLoaded(player: Player, data: Data)
	syncLifetime(player, data)
	for _, callback in loadedCallbacks do
		callback(player, data)
	end
end

-- The load failed or another server took the save: play on, but never save this session.
local function playWithoutSaving(player: Player, data: Data?)
	sessions[player] = { profile = nil, data = data or copyTemplate() }
	setStatus(player, "Off")
end

-- Start the player's save session. Yields (up to Saving.LoadTimeoutSeconds).
local function load(player: Player)
	local myLoad = (loadNumber[player] or 0) + 1
	loadNumber[player] = myLoad
	setStatus(player, "Loading")

	local started = os.clock()
	local function isOutOfDate(): boolean
		return player.Parent ~= Players or loadNumber[player] ~= myLoad
	end
	-- pcall: if ProfileStore errors, the player plays without saving instead of being stuck
	-- on "Loading" with no banner.
	local ok, result = pcall(function()
		return store:StartSessionAsync(`Player_{player.UserId}`, {
			-- Stop trying when the player leaves, a newer load starts, or time is up.
			Cancel = function(): boolean
				return isOutOfDate() or os.clock() - started > Saving.LoadTimeoutSeconds
			end,
		})
	end)
	if not ok then
		warn(`[DataService] loading {player.Name}'s save failed: {result}`)
	end
	local profile = if ok then result else nil

	if isOutOfDate() then
		if profile then
			profile:EndSession()
		end
		return
	end
	if not profile then
		playWithoutSaving(player)
		announceLoaded(player, sessions[player].data)
		return
	end

	profile:AddUserId(player.UserId) -- GDPR: lets Roblox erase this save on request
	profile:Reconcile() -- fill in any fields added to the template since this save was made
	sessions[player] = { profile = profile, data = profile.Data }

	-- Another server took over this save (a fast rejoin elsewhere): stop saving here.
	profile.OnSessionEnd:Connect(function()
		local session = sessions[player]
		if session and session.profile == profile and player.Parent == Players then
			playWithoutSaving(player, session.data)
		end
	end)

	setStatus(player, "On")
	announceLoaded(player, profile.Data)
end

-- End the player's session (it saves on the way out, unless saving is off).
local function endSession(player: Player)
	local session = sessions[player]
	sessions[player] = nil
	if session and session.profile then
		session.profile:EndSession()
	end
end

-- A run just ended: count it in the Lifetime stats, then save. Runs that end before the save
-- has loaded aren't counted. When saving is off this only changes the copy in memory.
local function onRunEnded(player: Player, result: string)
	local data = DataService.get(player)
	if not data then
		return
	end
	local lifetime = data.Lifetime
	local kills = player:GetAttribute("Kills")
	lifetime.Kills += if type(kills) == "number" then kills else 0
	lifetime.RunsPlayed += 1
	if result == "Won" then
		lifetime.RunsWon += 1
		local seconds = player:GetAttribute("RunSeconds")
		if type(seconds) == "number" and (lifetime.BestWinSeconds == 0 or seconds < lifetime.BestWinSeconds) then
			lifetime.BestWinSeconds = seconds
		end
	end
	syncLifetime(player, data)
	DataService.saveNow(player)
end

-- Watch for the player's runs ending ("Playing" -> "Won"/"Lost"). Going back to "Playing"
-- (a new run) does nothing.
local function watchRuns(player: Player)
	player:GetAttributeChangedSignal("RunState"):Connect(function()
		local state = player:GetAttribute("RunState")
		if state == "Won" or state == "Lost" then
			onRunEnded(player, state)
		end
	end)
end

-- Called once each time a player's save is ready (or the fresh copy, when saving is off).
-- Players already loaded are passed to `callback` straight away.
function DataService.onLoaded(callback: (Player, Data) -> ())
	table.insert(loadedCallbacks, callback)
	for player, session in sessions do
		callback(player, session.data)
	end
end

-- The player's save table, or nil until it's loaded. Change only your own section.
function DataService.get(player: Player): Data?
	local session = sessions[player]
	return session and session.data
end

-- False when this session plays without saving (the load failed).
function DataService.isSaving(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.profile ~= nil
end

-- Ask ProfileStore to save soon (e.g. when a run ends). Does nothing when saving is off.
function DataService.saveNow(player: Player)
	local session = sessions[player]
	if session and session.profile then
		session.profile:Save()
	end
end

-- TESTS AND DEV ONLY: end the session (saving it) and load again, as if the player rejoined.
-- With simulateFailure, skip loading and go straight to playing without saving. Yields.
function DataService.reload(player: Player, simulateFailure: boolean?)
	local session = sessions[player]
	endSession(player)
	if session and session.profile then
		-- Wait until ProfileStore has let go, so the new session can start on this server.
		local deadline = os.clock() + 10
		while session.profile:IsActive() and os.clock() < deadline do
			task.wait()
		end
	end
	if simulateFailure then
		loadNumber[player] = (loadNumber[player] or 0) + 1 -- any load still running is out of date
		playWithoutSaving(player)
		announceLoaded(player, sessions[player].data)
	else
		load(player)
	end
end

function DataService:init()
	-- In Studio, tests use their own store so they never touch real players' saves.
	local storeName = Saving.SaveSlot .. (if RunService:IsStudio() then "_Studio" else "")
	store = ProfileStore.New(storeName, TEMPLATE)
end

function DataService:start()
	Players.PlayerAdded:Connect(function(player)
		watchRuns(player)
		load(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		endSession(player)
		loadNumber[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		watchRuns(player)
		task.spawn(load, player)
	end
end

return DataService
