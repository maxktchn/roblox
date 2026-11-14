--!strict
-- Tips/XP, "Order Up!" card draws, rerolls, recipe cards, loadout limits (PRD §2.3 to §2.5). Validates every ChooseCard against the cards it offered.
--
-- Public functions below are part of the agreed interface between the two tracks (issue #4).
-- They are stubs for now: Track B fills them in (#16).
-- Stat bonuses (armor, pickup range...) live in StatsService.getStat, not here.

local UpgradeService = {}

-- Add tips (XP) when the player picks one up. Fills the tip bar and triggers "Order Up!".
function UpgradeService.addTips(_amount: number)
	-- TODO(#16)
end

function UpgradeService:init() end

function UpgradeService:start() end

return UpgradeService
