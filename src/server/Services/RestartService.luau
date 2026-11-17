--!strict
-- "Play again" (#50): start a fresh run in the same server, without rejoining.
--
-- The run-over banner's button sends RequestRestart. It is only accepted from the run's
-- player and only while the run is over. RestartService.restart() resets every system in
-- order, then respawns the chef at the map's SpawnLocation.
--
-- This lives in its own service because it has to call almost every other one, and
-- RunManager can't require them (they require RunManager).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossService = require(script.Parent.BossService)
local EliteService = require(script.Parent.EliteService)
local EnemyService = require(script.Parent.EnemyService)
local JuiceService = require(script.Parent.JuiceService)
local MiniBossService = require(script.Parent.MiniBossService)
local PickupService = require(script.Parent.PickupService)
local PuddleService = require(script.Parent.PuddleService)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunManager = require(script.Parent.RunManager)
local RunReportService = require(script.Parent.RunReportService)
local StatsService = require(script.Parent.StatsService)
local UnlockService = require(script.Parent.UnlockService)
local UpgradeService = require(script.Parent.UpgradeService)
local WeaponService = require(script.Parent.WeaponService)

local RestartService = {}

-- Start the run again from 0:00. Order matters:
--   enemies and the boss fight first (no kills, tips or wins fire from removing them),
--   then the player's progress, and the run itself last so the clock starts clean.
function RestartService.restart()
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
	RunManager.reset() -- full HP, 0:00, timeline from the start, RunState "Playing"
	RunReportService.reset() -- a new report for the new run
	UnlockService.clearJustUnlocked() -- unlocks stay; only the banner's announcement goes

	-- A fresh chef at the SpawnLocation (also undoes any freeze from the card screen).
	local player = Players:GetPlayers()[1]
	if player then
		player:LoadCharacter()
	end
end

function RestartService:start()
	Remotes.get("RequestRestart").OnServerEvent:Connect(function(player: Player)
		-- Only the run's player, and only once the run has ended. A double tap is ignored:
		-- the first one already made the run "not over".
		if player ~= Players:GetPlayers()[1] or not RunManager.isRunOver() then
			return
		end
		RestartService.restart()
	end)
end

return RestartService
