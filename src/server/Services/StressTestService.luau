--!strict
-- Developer stress test for the phone performance check (issue #12, PRD §8.3).
--
-- Type /stress in chat during a run (Studio, the experience's owner, or DevTools.DevUserIds):
--   * every Phase 1 weapon (starter + the 4 pool gadgets) goes to max level and keeps firing
--   * spawning runs flat out, so RunRules.MaxAliveEnemies enemies stay alive
--   * the run clock is held in the final phase: all Phase 1 enemies, no boss
--   * the chef is healed every frame, and no level-ups happen (no "Order Up!" pauses)
--   * the client shows an FPS readout (StressOverlayController) with server numbers from here
-- There is no "off": rejoin to play normally.
--
-- While it is on, workspace has the attribute "StressTest" = true (UpgradeService checks it).
-- Server numbers go on the player as attributes, every half second:
--   "StressAlive" enemies alive, "StressTips" tips on the ground, "StressServerFps" server frames/s

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local DevAccess = require(script.Parent.Parent.DevAccess)
local DevTools = require(ReplicatedStorage.Config.DevTools)
local EnemyService = require(script.Parent.EnemyService)
local PickupService = require(script.Parent.PickupService)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)
local WeaponService = require(script.Parent.WeaponService)

local StressTestService = {}

local active = false
local reportTimer = 0
local frameTimes = 0 -- sum of server frame times since the last report
local frameCount = 0

local function turnOn(player: Player)
	if active then
		return
	end
	active = true
	workspace:SetAttribute("StressTest", true)
	player:SetAttribute("StressTest", true)

	-- If an "Order Up!" happened to be open, the run would stay paused: resume it.
	RunManager.setPaused(false)

	WeaponService.setWeaponLevel(RunRules.Starter, RunRules.StarterMaxLevel)
	for _, gadgetId in RunRules.UpgradePool.Gadgets do
		WeaponService.setWeaponLevel(gadgetId, RunRules.SharedItemMaxLevel)
	end
	print(`[StressTest] on for {player.Name}`)
end

local function update(deltaTime: number)
	if not active then
		return
	end

	-- Hold the clock in the final phase and keep spawning flat out. Re-applied every frame
	-- so a phase change from RunManager can't turn the rate back down.
	RunManager.setRunSeconds(DevTools.StressRunSeconds)
	EnemyService.setSpawning(RunRules.EnemyPool, DevTools.StressSpawnsPerSecond)
	RunManager.healPlayer(1)
	if RunManager.isPaused() and not RunManager.isRunOver() then
		RunManager.setPaused(false)
	end

	frameTimes += deltaTime
	frameCount += 1
	reportTimer -= deltaTime
	if reportTimer <= 0 then
		reportTimer = 0.5
		local player = Players:GetPlayers()[1]
		if player then
			player:SetAttribute("StressAlive", EnemyService.getAliveCount())
			player:SetAttribute("StressTips", PickupService.getTipCount())
			player:SetAttribute("StressServerFps", math.floor(frameCount / frameTimes + 0.5))
		end
		frameTimes = 0
		frameCount = 0
	end
end

function StressTestService:start()
	-- A chat command made by the server fires here, on the server, with who typed it.
	local command = Instance.new("TextChatCommand")
	command.Name = "StressTestCommand"
	command.PrimaryAlias = "/stress"
	command.Triggered:Connect(function(source: TextSource)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player and DevAccess.isAllowed(player) then
			turnOn(player)
		end
	end)
	command.Parent = TextChatService

	RunService.Heartbeat:Connect(update)
end

-- For test scripts: turn the stress test on for the run's player.
function StressTestService.turnOn()
	local player = Players:GetPlayers()[1]
	if player then
		turnOn(player)
	end
end

return StressTestService
