--!strict
-- Owns one run: timer, phases, mini-boss and final boss triggers, win/lose (PRD §2.1). Named RunManager to avoid clashing with Roblox's RunService.
--
-- Public functions below are part of the agreed interface between the two tracks (issue #4).
-- Timer, timeline and boss triggers: Track A fills them in (#6, #11).
--
-- RunManager must not require EnemyService, WeaponService or UpgradeService: they all
-- require RunManager (to check the pause), so requiring them back would be a loop.
--
-- Player attributes set here (read by the HUD):
--   "Hp", "MaxHp"  the chef's HP (#9)
--   "RunSeconds"   run timer in whole seconds (#6)
--   "RunState"     "Playing", "Lost" (#9) or "Won" (#6; the boss replaces this in #11)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Chapters = require(ReplicatedStorage.Config.Chapters)
local RunRules = require(ReplicatedStorage.Config.RunRules)
local StatsService = require(script.Parent.StatsService)

local RunManager = {}

-- Called when the timeline moves to a new phase: which enemy types may spawn now,
-- and how many spawn groups per second. An empty list means "stop spawning".
export type PhaseCallback = (enemyTypes: { string }, spawnsPerSecond: number) -> ()

-- Phase 1 has one chapter (PRD §9). The lobby picks the chapter from Phase 2 on.
local CHAPTER = "DinerKitchen"

--------------------------------------------------------------------------------
-- Pause
--------------------------------------------------------------------------------

local paused = false
local runOver = false
local result: "Won" | "Lost" | nil = nil

-- Pause or resume the run. UpgradeService pauses while "Order Up!" cards are on screen.
-- While paused: the timer, enemies (#6, #8) and weapons must all stand still.
-- A finished run stays paused: resuming is ignored once the run is over.
function RunManager.setPaused(isPaused: boolean)
	if runOver and not isPaused then
		return
	end
	paused = isPaused
end

-- True while the run is paused. Anything that moves or counts down each frame checks this.
function RunManager.isPaused(): boolean
	return paused
end

-- True once the run has ended, won or lost.
function RunManager.isRunOver(): boolean
	return runOver
end

--------------------------------------------------------------------------------
-- Run timer and timeline (#6)
--------------------------------------------------------------------------------

local runSeconds = 0 -- counts up while the run is playing; stands still while paused
local shownSeconds = -1 -- last whole second written to the HUD attribute
-- Which timeline phase is active: 0 = run not started yet, #timeline + 1 = past the end.
local phaseIndex = 0
local currentEnemyTypes: { string } = {}
local currentSpawnsPerSecond = 0
local phaseCallbacks: { PhaseCallback } = {}

local function getTimeline(): { Chapters.Phase }
	return Chapters[CHAPTER].Timeline or {}
end

-- Which phase `seconds` falls in (#timeline + 1 once the timeline has ended).
local function findPhase(seconds: number): number
	local timeline = getTimeline()
	for index, phase in timeline do
		if seconds >= phase.From and seconds < phase.To then
			return index
		end
	end
	return #timeline + 1
end

-- Switch to a phase and tell every listener what may spawn now.
-- Only enemies in RunRules.EnemyPool spawn (Phase 1 has 3 of the 5 in the timeline).
local function setPhase(index: number)
	phaseIndex = index
	local phase = getTimeline()[index]
	currentEnemyTypes = {}
	currentSpawnsPerSecond = 0
	if phase then
		for _, enemyType in phase.Enemies do
			if table.find(RunRules.EnemyPool, enemyType) then
				table.insert(currentEnemyTypes, enemyType)
			end
		end
		currentSpawnsPerSecond = phase.SpawnsPerSecond
	end
	for _, callback in phaseCallbacks do
		task.spawn(callback, table.clone(currentEnemyTypes), currentSpawnsPerSecond)
	end
end

-- Run `callback` every time the timeline moves to a new phase (EnemyService uses this).
-- If a phase is already active, the callback also runs straight away with it.
function RunManager.onPhaseChanged(callback: PhaseCallback)
	table.insert(phaseCallbacks, callback)
	if phaseIndex > 0 then
		task.spawn(callback, table.clone(currentEnemyTypes), currentSpawnsPerSecond)
	end
end

-- Seconds since the run started (paused time doesn't count).
function RunManager.getRunSeconds(): number
	return runSeconds
end

-- Jump the run clock to `seconds` (testing and tuning only, e.g. to try the 9:00 wave
-- straight away). The phase for that time is announced on the next frame.
function RunManager.setRunSeconds(seconds: number)
	runSeconds = math.max(seconds, 0)
end

--------------------------------------------------------------------------------
-- Chef HP (#9)
--------------------------------------------------------------------------------

local hp = RunRules.ChefMaxHp
local lastMaxHp = RunRules.ChefMaxHp

-- Max HP right now: base plus Bread's bonus (PRD §3.3).
local function getMaxHp(): number
	return RunRules.ChefMaxHp * (1 + StatsService.getStat("MaxHp"))
end

-- If max HP went up (a Bread card), the chef gains that much HP too, like most survivors games.
local function refreshMaxHp()
	local maxHp = getMaxHp()
	if maxHp > lastMaxHp then
		hp += maxHp - lastMaxHp
	end
	lastMaxHp = maxHp
	hp = math.min(hp, maxHp)
end

-- Copy HP and run state onto the run's player for the HUD.
local function syncAttributes()
	local player = Players:GetPlayers()[1]
	if player then
		player:SetAttribute("Hp", math.ceil(hp))
		player:SetAttribute("MaxHp", math.ceil(lastMaxHp))
		player:SetAttribute("RunSeconds", math.floor(runSeconds))
		player:SetAttribute("RunState", result or "Playing")
	end
end

-- End the run with a result: freeze everything and tell the client.
local function endRun(runResult: "Won" | "Lost")
	if runOver then
		return
	end
	runOver = true
	result = runResult
	paused = true
	syncAttributes()
end

-- The run is lost. (Revives come in Phase 3, PRD §2.7.)
local function loseRun()
	endRun("Lost")
end

-- The run is won: the chapter is cleared. The final boss calls this when defeated (#11).
-- Until the boss exists, surviving to RunRules.RunLengthSeconds wins.
function RunManager.winRun()
	endRun("Won")
end

-- Hurt the player (enemy contact, boss pulses). Armor (StatsService.getStat("Armor")) is
-- applied here, so pass raw damage. Every hit does at least 1.
-- Does nothing once the player is dead. HP 0 ends the run as lost.
function RunManager.damagePlayer(amount: number)
	if runOver or amount <= 0 then
		return
	end
	refreshMaxHp()
	local afterArmor = math.max(amount - StatsService.getStat("Armor"), 1)
	hp = math.max(hp - afterArmor, 0)
	if hp <= 0 then
		loseRun()
	else
		syncAttributes()
	end
end

-- Heal the player by a fraction of max HP (0.3 = 30%), capped at max HP. Used by the Pie card.
function RunManager.healPlayer(fraction: number)
	if runOver or fraction <= 0 then
		return
	end
	refreshMaxHp()
	hp = math.min(hp + lastMaxHp * fraction, lastMaxHp)
	syncAttributes()
end

-- The chef's current HP and max HP.
function RunManager.getHp(): (number, number)
	refreshMaxHp()
	return hp, lastMaxHp
end

-- Start a fresh run: full HP, timer at 0:00, not paused, not over.
-- The first phase is announced again on the next frame.
function RunManager.reset()
	runOver = false
	result = nil
	paused = false
	lastMaxHp = getMaxHp()
	hp = lastMaxHp
	runSeconds = 0
	shownSeconds = -1
	phaseIndex = 0
	syncAttributes()
end

--------------------------------------------------------------------------------
-- Every frame
--------------------------------------------------------------------------------

-- Count the run timer up, move the timeline along, and end the shift at 10:00.
local function update(deltaTime: number)
	if paused or runOver then
		return -- "Order Up!" on screen, or the run is over: the clock stands still
	end
	local player = Players:GetPlayers()[1]
	if not (player and player.Character) then
		return -- the clock starts once the chef is in the kitchen
	end

	runSeconds += deltaTime

	-- The HUD only needs whole seconds, so only write the attribute when the number changes.
	local whole = math.floor(runSeconds)
	if whole ~= shownSeconds then
		shownSeconds = whole
		player:SetAttribute("RunSeconds", whole)
	end

	local index = findPhase(runSeconds)
	if index ~= phaseIndex then
		setPhase(index)
	end

	if runSeconds >= RunRules.RunLengthSeconds then
		-- 10:00: this is where the final boss arrives (#11). Until then, surviving the shift wins.
		RunManager.winRun()
	end
end

--------------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------------

function RunManager:init() end

function RunManager:start()
	syncAttributes()
	Players.PlayerAdded:Connect(syncAttributes)
	RunService.Heartbeat:Connect(update)
end

return RunManager
