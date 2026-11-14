--!strict
-- Owns one run: timer, phases, mini-boss and final boss triggers, win/lose (PRD §2.1). Named RunManager to avoid clashing with Roblox's RunService.
--
-- Public functions below are part of the agreed interface between the two tracks (issue #4).
-- They are stubs for now: Track A fills them in (#6, #9).

local RunManager = {}

-- Hurt the player (enemy contact, boss pulses). Armor (StatsService.getStat("Armor")) is
-- applied here, so pass raw damage.
-- Does nothing once the player is dead. HP 0 ends the run as lost.
function RunManager.damagePlayer(_amount: number)
	-- TODO(#9)
end

-- Heal the player by a fraction of max HP (0.3 = 30%), capped at max HP. Used by the Pie card.
function RunManager.healPlayer(_fraction: number)
	-- TODO(#9)
end

function RunManager:init() end

function RunManager:start() end

return RunManager
