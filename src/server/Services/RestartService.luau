--!strict
-- Starting runs and going back to the lobby, in the same server, without rejoining (#50, P2-8 #143).
--
-- The lobby's Play button sends RequestRestart with the chapter picked on the Chapters tab (#152):
-- accepted only from the run's player, only in the lobby, only for a chapter they can play. RestartService.restart() resets every system in order, then respawns the chef at
-- the map's SpawnLocation. The run-over banner's Continue button sends RequestLobby: accepted
-- only once a run has ended; toLobby() clears the run and goes back to the lobby.
--
-- This lives in its own service because it has to call almost every other one, and
-- RunManager can't require them (they require RunManager).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossService = require(script.Parent.BossService)
local ChapterMath = require(ReplicatedStorage.Shared.ChapterMath)
local EliteService = require(script.Parent.EliteService)
local EnemyService = require(script.Parent.EnemyService)
local GearService = require(script.Parent.GearService)
local JuiceService = require(script.Parent.JuiceService)
local MiniBossService = require(script.Parent.MiniBossService)
local PickupService = require(script.Parent.PickupService)
local PuddleService = require(script.Parent.PuddleService)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RewardService = require(script.Parent.RewardService)
local RunManager = require(script.Parent.RunManager)
local RunReportService = require(script.Parent.RunReportService)
local StatsService = require(script.Parent.StatsService)
local TalentService = require(script.Parent.TalentService)
local UnlockService = require(script.Parent.UnlockService)
local UpgradeService = require(script.Parent.UpgradeService)
local WeaponService = require(script.Parent.WeaponService)

local RestartService = {}

-- Clear everything a run leaves behind. Order matters: enemies and the boss fight first
-- (no kills, tips or wins fire from removing them), then the player's progress.
local function clearRun()
	EnemyService.clearAll()
	BossService.reset()
	MiniBossService.reset()
	EliteService.reset()
	PickupService.reset()
	PuddleService.reset() -- also lets the chef walk at full speed again
	JuiceService.reset()
	WeaponService.reset() -- back to the starter at Lv 1, kills 0
	StatsService.reset() -- no ingredients
	UpgradeService.reset() -- Lv 1, rerolls back, closes any open cards
	UnlockService.clearJustUnlocked() -- unlocks stay; only the banner's announcement goes
	TalentService.clearJustLeveled() -- the same for the account level line
	RewardService.clearRewards() -- and the run reward rows (#106)
end

-- A fresh chef at the SpawnLocation (also undoes any freeze from the card screen).
local function respawnChef()
	local player = Players:GetPlayers()[1]
	if player then
		player:LoadCharacter()
	end
end

-- Start a run from 0:00: Play in the lobby, the playtest bot, and DEV "Restart" (from any state).
-- The run itself is reset last so the clock starts clean.
function RestartService.restart()
	clearRun()
	RunManager.reset() -- full HP, 0:00, timeline from the start, RunState "Playing"
	RunReportService.reset() -- a new report for the new run
	respawnChef()

	-- This run's gear, from what's equipped now (P2-4). After the new chef exists: an Epic Hat's
	-- free picks open the cards, and the card screen has to freeze the new chef, not the old one.
	-- The gear's max HP shows on RunManager's next frame (as full HP).
	GearService.startRun()
end

-- Back to the lobby after a run (Continue, P2-8 #143): clear what the run left and stand the chef
-- in the kitchen. The last run report stays for devs.
function RestartService.toLobby()
	clearRun()
	RunManager.enterLobby() -- RunState "Lobby": no clock, no spawns
	respawnChef()
end

-- The Play button (RequestRestart): only the run's player, only from the lobby. A double tap is
-- ignored: the first one already left the lobby. `chapterId` is the chapter to play (nil = the
-- current one); one that's locked, coming soon or unknown is refused and nothing starts.
function RestartService.requestPlay(player: Player, chapterId: unknown?)
	if player ~= Players:GetPlayers()[1] or not RunManager.isInLobby() then
		return
	end
	if chapterId ~= nil then
		if type(chapterId) ~= "string" or not ChapterMath.isPlayable(chapterId, UnlockService.getClearedChapters()) then
			return
		end
		RunManager.setChapter(chapterId)
	end
	RestartService.restart()
end

-- The Continue button (RequestLobby): only the run's player, only once a run has ended.
function RestartService.requestContinue(player: Player)
	if player == Players:GetPlayers()[1] and RunManager.isRunOver() and not RunManager.isInLobby() then
		RestartService.toLobby()
	end
end

function RestartService:start()
	Remotes.get("RequestRestart").OnServerEvent:Connect(RestartService.requestPlay)
	Remotes.get("RequestLobby").OnServerEvent:Connect(RestartService.requestContinue)
end

return RestartService
