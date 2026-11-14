--!strict
-- Rules for a single run. Starting values from PRD §2 and §8.3; tune here, then update docs/PRD.md.

return {
	RunLengthSeconds = 600, -- final boss at 10:00
	MiniBossAtSeconds = 300, -- mini-boss at 5:00

	-- Loadout (PRD §2.4)
	StarterMaxLevel = 5,
	SharedSlots = 6, -- gadgets + ingredients combined
	SharedItemMaxLevel = 5,

	-- "Order Up!" (PRD §2.3)
	CardsPerLevelUp = 3,
	RerollsPerRun = 2,

	-- Which gadgets and ingredients can show up as cards. Phase 1 picks (PRD §9);
	-- add ids here to put more items in the game. Checked by ConfigCheck.
	UpgradePool = {
		Gadgets = { "PepperShaker", "Blender", "SpinningForks", "Toaster" },
		Ingredients = { "Salt", "HotSauce", "BeefJerky", "FridgeMagnet" },
	},

	-- Pickups (PRD §2.6)
	PieHealFraction = 0.3,
	LunchboxUpgradesMin = 1,
	LunchboxUpgradesMax = 3,

	-- Revive (PRD §2.7)
	RevivesPerRun = 1,
	ReviveGemCost = 30,

	-- Performance (PRD §8.3)
	MaxAliveEnemies = 150,
}
