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
	-- The chef's walk speed before Butter and slows (StatsService.getWalkSpeed, #117).
	ChefWalkSpeed = 16,
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
	LobFlightSeconds = 0.6, -- a lobbed egg (Lob shape, #129) is in the air this long
	LobClusterSeconds = 0.3, -- Breakfast Bomb's mini-eggs are in the air this long
	LobHeight = 6, -- studs: how high an egg's arc goes (drawing only)
	-- Trail weapons (Squeeze Bottle, #131) and butter slicks (#132).
	TrailTickSeconds = 0.5, -- enemies on a splat take its damage this often
	TrailSlowSeconds = 0.3, -- a splat's slow lasts this long after the enemy steps off
	TrailMoveSpeed = 2, -- studs per second: slower than this counts as standing still
	MaxTrailSplats = 40, -- per trail weapon; a new splat removes the oldest
	MaxSlicks = 20, -- Buttered Barrage's butter slicks (#132); a new one removes the oldest

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
		Gadgets = {
			"PepperShaker",
			"SpinningForks",
			"Toaster",
			"EggGrenade",
			"PizzaCutter",
			"SqueezeBottle",
			"IceCubeTray",
		},
		Ingredients = { "Salt", "HotSauce", "BeefJerky", "FridgeMagnet", "Coffee", "Bread", "Butter" },
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
	-- Pies (#82): bigger enemies sometimes drop one (Enemies.luau PieDropChance). Walk over it to heal.
	-- A pie stays on the floor while the chef is at full HP, so it can be saved for later.
	PieHealFraction = 0.2, -- of max HP
	PiePickupDistance = 2.5, -- studs from the chef's centre to the pie
	MaxPiesOnGround = 15, -- past this, new pies aren't dropped
	-- Rotten Tomato puddles (#117): past this many on the floor, a new one removes the oldest.
	MaxPuddles = 10,
	-- Sour Lemon juice blobs in the air at once (#118); past this, lemons skip a shot.
	MaxJuiceShots = 30,
	-- Lunchbox (#120): elites always drop one. Walk over it for free "Order Up!" picks.
	EliteLunchboxUpgrades = 1,
	LunchboxPickupDistance = 2.5, -- studs from the chef's centre
	MaxLunchboxesOnGround = 6, -- past this, new ones aren't dropped

	-- Elites (#120, PRD §3.4): bigger, tougher versions of normal enemies, on the chapter's
	-- Elites schedule (Chapters.luau). On top of the normal per-minute scaling; speed unchanged.
	-- An elite Rotten Tomato's puddle is EliteSizeScale wider; an elite Sour Lemon's shot does
	-- EliteDamageScale more.
	EliteSizeScale = 1.5,
	EliteHpScale = 6,
	EliteDamageScale = 1.5,
	EliteTipScale = 5,
	EliteGlowColor = Color3.fromRGB(255, 200, 50),

	-- Revive (PRD §2.7)
	RevivesPerRun = 1,
	ReviveGemCost = 30,

	-- Performance (PRD §8.3)
	MaxAliveEnemies = 150,

	-- Enemy scaling over the run (PRD §3.4). Enemies get tougher every minute of run time
	-- (paused time doesn't count), compounding: HP x(1 + growth) per minute. With 0.20 that is
	-- x1.7 at 3:00 and x3.0 at 6:00; damage with 0.085 is x1.6 at 6:00. Each enemy keeps the
	-- strength it spawned with. Speed never scales (Fruit Flies are already faster than the chef),
	-- and bosses don't scale (their numbers are tuned in Bosses.luau); their minions do.
	EnemyHpGrowthPerMinute = 0.20, -- was 0.26: gadget builds hit a wall at ~3:40 (#22 bot runs)
	EnemyDamageGrowthPerMinute = 0.085,

	-- Enemy spawning (PRD §2.1, §8.3). How many spawn per second is set per timeline phase in Chapters.luau.
	-- Which enemies can spawn at all. Phase 1 picks (PRD §9); the timeline skips anything not listed.
	-- Add ids here to put more enemies in the game. Checked by ConfigCheck.
	EnemyPool = { "MoldyBread", "FruitFlies", "RottenTomato", "Meatball", "SourLemon" },
	-- Enemies appear on a ring this far from the chef, just outside the camera view.
	-- With the camera above (pitch 55, distance 45, FOV 50) the farthest visible ground,
	-- a corner of a wide phone screen, is about 85 studs away. Retune if the camera changes.
	EnemySpawnRadius = 90,
	EnemyGroupSpread = 4, -- studs; how far apart a group (e.g. Fruit Flies) spawns around its center

	-- Enemy movement (PRD §3.4)
	ChargeOvershootDistance = 25, -- studs a charger rolls past the chef before it turns and aims again
	-- Before every charge (on spawn and each re-aim) a charger stops and wobbles this long, then
	-- rolls at where the chef is (#119): a tell, so dodging is a skill, not luck.
	ChargeWindupSeconds = 0.4,
	-- How hard overlapping enemies push apart each frame: 0 = not at all, 1 = fully separated at once.
	-- Lower is smoother but lets the swarm squash together more.
	EnemySeparationStrength = 0.5,
}
