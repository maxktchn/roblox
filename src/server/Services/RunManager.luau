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
--   "RunState"     "Playing" or "Lost" (#9); "Won" comes with the boss (#11)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunRules = require(ReplicatedStorage.Config.RunRules)
local StatsService = require(script.Parent.StatsService)

local RunManager = {}

--------------------------------------------------------------------------------
-- Pause
--------------------------------------------------------------------------------

local paused = false
local runOver = false

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

-- True once the run has ended (for now only by the chef's HP reaching 0).
function RunManager.isRunOver(): boolean
	return runOver
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
		player:SetAttribute("RunState", if runOver then "Lost" else "Playing")
	end
end

-- The run is lost: freeze everything and tell the client. (Revives come in Phase 3, PRD §2.7.)
local function loseRun()
	runOver = true
	paused = true
	syncAttributes()
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

-- Start a fresh run: full HP, not paused, not over.
function RunManager.reset()
	runOver = false
	paused = false
	lastMaxHp = getMaxHp()
	hp = lastMaxHp
	syncAttributes()
end

--------------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------------

function RunManager:init() end

function RunManager:start()
	syncAttributes()
	Players.PlayerAdded:Connect(syncAttributes)
end

return RunManager
