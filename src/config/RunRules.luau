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
