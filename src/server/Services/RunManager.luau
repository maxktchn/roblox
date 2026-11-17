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
--   "RunState"     "Playing", "Lost" (#9) or "Won" (final boss defeated, #11)
--   "Rush", "RushStage", "RushSound"  a swarm event (the dinner rush, #121): its name, "Warning"
--                  or "On", and its sound id; all nil when there's none

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
-- Final boss (#11): who to tell at the end of the timeline, and whether we already did.
local finalBossCallbacks: { () -> () } = {}
local finalBossStarted = false
-- Mini-boss (#84): who to tell when the clock reaches RunRules.MiniBossAtSeconds, and whether
-- it already happened this run.
local miniBossCallbacks: { () -> () } = {}
local miniBossStarted = false
-- While held, the clock stands still and nothing new spawns (the mini-boss fight).
local clockHeld = false
-- The dinner rush (#121): how much faster spawns run right now (1 = normal), and which rush
-- is warning or on (nil = none).
local rushScale = 1
local rushShown: Chapters.Rush? = nil
local rushStage: "Warning" | "On" | nil = nil

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
		currentSpawnsPerSecond = phase.SpawnsPerSecond * rushScale
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

-- Copy the dinner rush onto the player for the HUD.
local function syncRush()
	local player = Players:GetPlayers()[1]
	if player then
		local rush = rushShown
		player:SetAttribute("Rush", rush and rush.Name)
		player:SetAttribute("RushStage", rushStage)
		player:SetAttribute("RushSound", rush and rush.SoundId)
	end
end

-- Work out whether a rush is warning or on at the current clock time, and when its spawn rate
-- changes, tell the phase listeners again (they get the rate times SpawnScale).
local function updateRush()
	local scale = 1
	local shown: Chapters.Rush? = nil
	local stage: "Warning" | "On" | nil = nil
	local rushes: { Chapters.Rush } = Chapters[CHAPTER].Rushes or {}
	for _, rush in rushes do
		if runSeconds >= rush.At and runSeconds < rush.At + rush.Seconds then
			scale, shown, stage = rush.SpawnScale, rush, "On"
		elseif runSeconds >= rush.At - rush.Warning and runSeconds < rush.At then
			shown, stage = rush, "Warning"
		end
	end
	if shown ~= rushShown or stage ~= rushStage then
		rushShown, rushStage = shown, stage
		syncRush()
	end
	if scale ~= rushScale then
		rushScale = scale
		if phaseIndex > 0 and not clockHeld then
			setPhase(phaseIndex)
		end
	end
end

-- True while a swarm event (the dinner rush) is on.
function RunManager.isRushOn(): boolean
	return rushStage == "On"
end

-- Which enemy types the current phase spawns (only those in RunRules.EnemyPool). EliteService
-- picks its elites from these.
function RunManager.getSpawnTypes(): { string }
	return table.clone(currentEnemyTypes)
end

-- Which chapter this run is in (a key of Chapters.luau).
function RunManager.getChapter(): string
	return CHAPTER
end

-- Run `callback` once, when the timeline ends at RunRules.RunLengthSeconds: time for the
-- final boss (BossService, #11). The clock keeps running during the boss fight.
function RunManager.onFinalBoss(callback: () -> ())
	table.insert(finalBossCallbacks, callback)
end

-- Run `callback` once per run, on the frame the clock counts up past RunRules.MiniBossAtSeconds
-- (3:00): time for the mini-boss (MiniBossService, #84). The clock is set to exactly 3:00 first.
-- Jumping the clock past 3:00 with setRunSeconds doesn't count (a dev skip).
function RunManager.onMiniBoss(callback: () -> ())
	table.insert(miniBossCallbacks, callback)
end

-- Hold or release the clock (the mini-boss fight, #84). While held, the clock stands still,
-- the timeline doesn't move on, and every phase listener is told "spawn nothing". Releasing
-- announces the current phase again, so spawns pick up where they left off.
function RunManager.setClockHeld(held: boolean)
	if held == clockHeld then
		return
	end
	clockHeld = held
	if held then
		for _, callback in phaseCallbacks do
			task.spawn(callback, {}, 0)
		end
	elseif phaseIndex > 0 then
		setPhase(findPhase(runSeconds))
	end
end

-- True while the clock is held (the mini-boss fight).
function RunManager.isClockHeld(): boolean
	return clockHeld
end

-- Seconds since the run started (paused time doesn't count).
function RunManager.getRunSeconds(): number
	return runSeconds
end

-- Jump the run clock to `seconds` (testing and tuning only, e.g. to try the final wave
-- straight away). The phase for that time is announced on the next frame.
-- A jump releases a held clock, and a jump back before 3:00 lets the mini-boss come again.
function RunManager.setRunSeconds(seconds: number)
	runSeconds = math.max(seconds, 0)
	if runSeconds < RunRules.MiniBossAtSeconds then
		miniBossStarted = false
	end
	if clockHeld then
		clockHeld = false
		phaseIndex = 0 -- announce the phase again on the next frame
	end
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
	rushShown, rushStage = nil, nil -- the banner goes with the run
	syncRush()
	syncAttributes()
end

-- The run is lost. (Revives come in Phase 3, PRD §2.7.)
local function loseRun()
	endRun("Lost")
end

-- The run is won: the chapter is cleared. BossService calls this when the final boss dies (#11).
function RunManager.winRun()
	endRun("Won")
end

-- Called after every hit on the chef: the HP actually lost, and what hit them (or nil).
export type DamagedCallback = (hpLost: number, source: string?) -> ()
local damagedCallbacks: { DamagedCallback } = {}

-- Run `callback` after every hit on the chef (RunReportService counts damage per source).
function RunManager.onPlayerDamaged(callback: DamagedCallback)
	table.insert(damagedCallbacks, callback)
end

-- Hurt the player (enemy contact, boss pulses). Armor (StatsService.getStat("Armor")) is
-- applied here, so pass raw damage. Every hit does at least 1.
-- `source` says what hit them (an enemy id like "FruitFlies", or "BossPulse"), for the run report.
-- Does nothing once the player is dead. HP 0 ends the run as lost.
function RunManager.damagePlayer(amount: number, source: string?)
	if runOver or amount <= 0 then
		return
	end
	refreshMaxHp()
	local afterArmor = math.max(amount - StatsService.getStat("Armor"), 1)
	local hpLost = math.min(afterArmor, hp)
	hp = math.max(hp - afterArmor, 0)
	for _, callback in damagedCallbacks do
		task.spawn(callback, hpLost, source)
	end
	if hp <= 0 then
		loseRun()
	else
		syncAttributes()
	end
end

-- Heal the player by a fraction of max HP (0.2 = 20%), capped at max HP. Used by pies (PickupService).
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
	finalBossStarted = false
	miniBossStarted = false
	clockHeld = false
	rushScale = 1
	rushShown, rushStage = nil, nil
	syncRush()
	syncAttributes()
end

--------------------------------------------------------------------------------
-- Every frame
--------------------------------------------------------------------------------

-- Count the run timer up, move the timeline along, and end the shift at RunLengthSeconds (6:00).
local function update(deltaTime: number)
	if paused or runOver then
		return -- "Order Up!" on screen, or the run is over: the clock stands still
	end
	local player = Players:GetPlayers()[1]
	if not (player and player.Character) then
		return -- the clock starts once the chef is in the kitchen
	end

	if clockHeld then
		return -- the mini-boss fight: the clock waits at 3:00
	end

	local before = runSeconds
	runSeconds += deltaTime

	-- Mini-boss (#84): only when the clock counts up past 3:00, not when a dev jumps over it.
	local miniBossAt = RunRules.MiniBossAtSeconds
	local miniBossNow = before < miniBossAt and runSeconds >= miniBossAt and not miniBossStarted
	if miniBossNow then
		miniBossStarted = true
		runSeconds = miniBossAt
	end

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
	updateRush()

	if miniBossNow then
		for _, callback in miniBossCallbacks do
			task.spawn(callback)
		end
	end

	if runSeconds >= RunRules.RunLengthSeconds and not finalBossStarted then
		-- End of the run: normal spawns have stopped (the timeline is over); the final boss arrives.
		finalBossStarted = true
		if #finalBossCallbacks == 0 then
			RunManager.winRun() -- no boss fight in this game: surviving the shift wins
		end
		for _, callback in finalBossCallbacks do
			task.spawn(callback)
		end
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
