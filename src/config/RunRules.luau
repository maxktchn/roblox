--!strict
-- Rules for a single run. Starting values from PRD §2 and §8.3; tune here, then update docs/PRD.md.

return {
	-- 6 minutes: short enough for Roblox attention spans (paused time doesn't count, so a run
	-- takes about 7 minutes of real time). The timeline in Chapters.luau must end here.
	RunLengthSeconds = 360, -- final boss at 6:00
	MiniBossAtSeconds = 180, -- mini-boss at 3:00

	-- Camera (PRD §2.2): fixed 3/4 overhead view
	CameraPitchDegrees = 55, -- angle looking down; 90 = straight down
	CameraDistance = 45, -- studs from the chef
	CameraFieldOfView = 50, -- degrees; lower = less stretching at the screen edges

	-- The chef (PRD §2.1, §2.7)
	ChefMaxHp = 100, -- before Bread's +% max HP
	-- After any hit the chef can't be hurt again for this long, so a swarm wears HP down
	-- instead of deleting it in one frame. Only the strongest touching enemy's hit counts.
	ChefHurtCooldown = 0.5,
	-- How far the chef's body reaches from its centre, for every distance check against the
	-- chef (contact, where chasers stop, boss pulses). The chef's body is about 2 studs wide and
	-- 1 deep, so 1 is a fair circle around it.
	ChefRadius = 1,
	-- An enemy hurts the chef when it is within touching distance plus this many studs.
	ContactReach = 0.75,

	-- Phase 1 has no lobby, so every run starts with this starter (PRD §9). Checked by ConfigCheck.
	Starter = "ChefsKnife",

	-- Aiming (PRD §2.2): the client sends its aim direction at most this many times a second;
	-- the server ignores anything faster.
	AimMessagesPerSecond = 20,

	-- How long an Arc swing (the knife's slash) stays live. The blade is drawn sweeping across
	-- for this long, and any enemy that enters the arc during it is hit (once per swing), so
	-- what you see slashed is what gets hit. Used by WeaponService and WeaponFxController.
	SlashSeconds = 0.15,

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
	-- So 5, 10, 15, 20... Leftover tips carry over. Tuned so a run reaches about Lv 20 by the boss,
	-- with only part of the build maxed (4, 6, 8... reached Lv 33 by 5:00 in playtests).
	FirstLevelTips = 5,
	ExtraTipsPerLevel = 5,
	CardsPerLevelUp = 3,
	RerollsPerRun = 2,

	-- Which gadgets and ingredients can show up as cards. Phase 1 picks (PRD §9);
	-- add ids here to put more items in the game. Checked by ConfigCheck.
	UpgradePool = {
		Gadgets = { "PepperShaker", "Blender", "SpinningForks", "Toaster" },
		Ingredients = { "Salt", "HotSauce", "BeefJerky", "FridgeMagnet" },
		-- Boss powers only show up once their boss has been defeated (PRD §3.8).
		BossPowers = { "MicrowavePulse" },
	},
	-- Chance (0 to 1) that an unlocked boss power the player doesn't own yet joins the cards a
	-- given "Order Up!" draws from. Makes its NEW card rarer than a gadget's (at 0.35 it shows
	-- up about a third as often); its upgrades appear normally.
	BossPowerNewCardChance = 0.35,

	-- Pickups (PRD §2.6)
	TipPickupRange = 8, -- studs; tips this close start flying to the chef. Fridge Magnet adds % on top.
	TipFlySpeed = 45, -- studs per second while a tip flies to the chef
	MaxTipsOnGround = 250, -- above this, new tips are added to the oldest tip instead (keeps phones fast)
	PieHealFraction = 0.3,
	LunchboxUpgradesMin = 1,
	LunchboxUpgradesMax = 3,

	-- Revive (PRD §2.7)
	RevivesPerRun = 1,
	ReviveGemCost = 30,

	-- Performance (PRD §8.3)
	MaxAliveEnemies = 150,

	-- Enemy scaling over the run (PRD §3.4). Enemies get tougher every minute of run time
	-- (paused time doesn't count), compounding: HP x(1 + growth) per minute. With 0.26 that is
	-- x2.0 at 3:00 and x4.0 at 6:00; damage with 0.085 is x1.6 at 6:00. Each enemy keeps the
	-- strength it spawned with. Speed never scales (Fruit Flies are already faster than the chef),
	-- and bosses don't scale (their numbers are tuned in Bosses.luau); their minions do.
	EnemyHpGrowthPerMinute = 0.26,
	EnemyDamageGrowthPerMinute = 0.085,

	-- Enemy spawning (PRD §2.1, §8.3). How many spawn per second is set per timeline phase in Chapters.luau.
	-- Which enemies can spawn at all. Phase 1 picks (PRD §9); the timeline skips anything not listed.
	-- Add ids here to put more enemies in the game. Checked by ConfigCheck.
	EnemyPool = { "MoldyBread", "FruitFlies", "Meatball" },
	-- Enemies appear on a ring this far from the chef, just outside the camera view.
	-- With the camera above (pitch 55, distance 45, FOV 50) the farthest visible ground,
	-- a corner of a wide phone screen, is about 85 studs away. Retune if the camera changes.
	EnemySpawnRadius = 90,
	EnemyGroupSpread = 4, -- studs; how far apart a group (e.g. Fruit Flies) spawns around its center

	-- Enemy movement (PRD §3.4)
	ChargeOvershootDistance = 25, -- studs a charger rolls past the chef before it turns and aims again
	-- How hard overlapping enemies push apart each frame: 0 = not at all, 1 = fully separated at once.
	-- Lower is smoother but lets the swarm squash together more.
	EnemySeparationStrength = 0.5,
}
