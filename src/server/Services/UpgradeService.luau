--!strict
-- Tips/XP, "Order Up!" card draws, rerolls, recipe cards, loadout limits (PRD §2.3 to §2.5). Validates every ChooseCard against the cards it offered.
--
-- Public functions below are part of the agreed interface between the two tracks (issue #4).
-- They are stubs for now: Track B fills them in (#15, #16).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ingredients = require(ReplicatedStorage.Config.Ingredients)

local UpgradeService = {}

-- Add tips (XP) when the player picks one up. Fills the tip bar and triggers "Order Up!".
function UpgradeService.addTips(_amount: number)
	-- TODO(#16)
end

-- The player's total bonus for one ingredient stat, from every ingredient they own.
-- Example: Beef Jerky Lv 2 -> getStat("Armor") == 2. Returns 0 when they own none.
-- Track A reads "Armor" (contact damage, #9) and "PickupRange" (tips, #10).
function UpgradeService.getStat(_stat: Ingredients.Stat): number
	return 0 -- TODO(#15)
end

function UpgradeService:init() end

function UpgradeService:start() end

return UpgradeService
