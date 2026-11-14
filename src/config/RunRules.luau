--!strict
-- Rules for a single run. Starting values from PRD §2 and §8.3; tune here, then update docs/PRD.md.

return {
	RunLengthSeconds = 600, -- final boss at 10:00
	MiniBossAtSeconds = 300, -- mini-boss at 5:00

	-- Camera (PRD §2.2): fixed 3/4 overhead view
	CameraPitchDegrees = 55, -- angle looking down; 90 = straight down
	CameraDistance = 45, -- studs from the chef
	CameraFieldOfView = 50, -- degrees; lower = less stretching at the screen edges

	-- Phase 1 has no lobby, so every run starts with this starter (PRD §9). Checked by ConfigCheck.
	Starter = "ChefsKnife",

	-- Combat (PRD §3.3): Salt adds crit chance; a crit multiplies one hit's damage.
	CritDamageMultiplier = 2,
	BurnTickSeconds = 0.5, -- burns (Pepper Shaker) deal their damage in ticks this far apart
	OrbitHitRadius = 2.5, -- how close an enemy must be to an orbiting fork to be hit
	ProjectileHitRadius = 2, -- how close an enemy must be to a flying shot to be hit

	-- Loadout (PRD §2.4)
	StarterMaxLevel = 5,
	SharedSlots = 6, -- gadgets + ingredients combined
	SharedItemMaxLevel = 5,

	-- "Order Up!" (PRD §2.3)
	-- Tips needed to fill the bar: FirstLevelTips for level 1 -> 2, then ExtraTipsPerLevel more each level.
	-- So 5, 8, 11, 14... Leftover tips carry over to the next bar.
	FirstLevelTips = 5,
	ExtraTipsPerLevel = 3,
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

	-- Enemy spawning (PRD §2.1, §8.3)
	EnemySpawnsPerSecond = 2, -- RunManager changes this over the timeline (#6)
	-- Enemies appear on a ring this far from the chef, just outside the camera view.
	-- With the camera above (pitch 55, distance 45, FOV 50) the farthest visible ground,
	-- a corner of a wide phone screen, is about 85 studs away. Retune if the camera changes.
	EnemySpawnRadius = 90,
}
