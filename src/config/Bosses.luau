--!strict
-- Bosses (PRD §3.5). Which chapter uses which boss is set in Chapters.luau.
--
-- Body: the boss as an enemy (same fields as Enemies.luau), so every weapon can hit it.
--       Bosses without a Body aren't playable yet.
-- Fight: the final-boss fight (BossService, issue #11). Numbers are Phase 1 starting values:
--   ArenaRadius   studs; a ring of counters closes around the chef and boss this wide
--   SummonEvery   seconds between minion summons
--   SummonEnemy   which enemy it summons (an id from Enemies.luau)
--   SummonCount   how many per summon (the alive cap still applies)
--   PulseEvery    seconds between damage pulses
--   PulseWarning  seconds the pulse ring grows (the warning) before it hits
--   PulseRadius   studs from the boss's center that the pulse reaches
--   PulseDamage   damage to the chef if inside the pulse, before armor
-- Two HP phases (#91): phase 1 is the walking, summoning and pulsing above. Below Phase2At the
-- boss takes turns: a laser turn (runs to the middle of the ring and stands there; no pulses
-- or new minions) then a walking turn (phase 1 again), over and over until it dies.
--   Phase2At           fraction of max HP where phase 2 starts (0.5 = at half HP)
--   PhaseChangeSeconds the boss stops and flashes this long when phase 2 starts
--   LaserWalkSpeed     studs per second on its way to the middle for a laser turn
--   LaserSeconds       how long each laser turn lasts once it reaches the middle
--   WalkingSeconds     how long each walking turn lasts
-- Homing popcorn (#92), in phase 1 and the walking turns:
--   PopcornEvery       seconds between kernels
--   PopcornWarning     seconds the microwave door glows before a kernel flies out
--   PopcornEnemy       which enemy it fires (an id from Enemies.luau)
--   PopcornSeconds     a kernel pops on its own after this long
--   PopWarning         seconds the pop's warning ring grows before it hits
--   PopRadius          studs from the kernel that the pop reaches
--   PopDamage          damage to the chef if inside the pop, before armor
-- Spinning lasers (#93), during each laser turn once the boss is in the middle:
--   LaserCount         beams, evenly spaced (6 = 60 degrees apart)
--   LaserWarning       seconds of thin see-through beams first (part of LaserSeconds)
--   LaserTurnSpeed     degrees per second the beams sweep once live
--   LaserWidth         studs wide when live
--   LaserDamage        damage to the chef per hit, before armor
--   LaserHitCooldown   seconds before the lasers can hit the chef again
--   LaserReverseAt     when the beams switch direction, as a fraction of the live time
--                      (0.5 = halfway through)
--   LaserReverseTell   seconds before the switch that the beams slow to a stop and go a
--                      little paler: a hint, meant to be easy to miss
-- Power: the boss power (id in BossPowers.luau) that defeating this boss unlocks (PRD §3.8).
-- Trail: a damaging trail of puddles the boss leaves as it walks (TrailService, #99).
--   Spacing       studs walked between puddles
--   Seconds       how long a puddle stays (it fades out over the last second)
--   Width         studs across a puddle
--   Damage        damage to the chef for stepping in one, before armor
--   HitCooldown   seconds before the trail can hurt the chef again
--   Color         the puddles' colour

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enemies = require(ReplicatedStorage.Config.Enemies)

export type BossFight = {
	ArenaRadius: number,
	SummonEvery: number,
	SummonEnemy: string,
	SummonCount: number,
	PulseEvery: number,
	PulseWarning: number,
	PulseRadius: number,
	PulseDamage: number,
	Phase2At: number,
	PhaseChangeSeconds: number,
	LaserWalkSpeed: number,
	LaserSeconds: number,
	WalkingSeconds: number,
	PopcornEvery: number,
	PopcornWarning: number,
	PopcornEnemy: string,
	PopcornSeconds: number,
	PopWarning: number,
	PopRadius: number,
	PopDamage: number,
	LaserCount: number,
	LaserWarning: number,
	LaserTurnSpeed: number,
	LaserWidth: number,
	LaserDamage: number,
	LaserHitCooldown: number,
	LaserReverseAt: number,
	LaserReverseTell: number,
}

export type BossTrail = {
	Spacing: number,
	Seconds: number,
	Width: number,
	Damage: number,
	HitCooldown: number,
	Color: Color3,
}

export type Boss = {
	Name: string,
	Mechanics: string,
	Mvp: boolean,
	Body: Enemies.Enemy?,
	Fight: BossFight?,
	Power: string?,
	Trail: BossTrail?,
}

local Bosses: { [string]: Boss } = {
	-- Mini-boss at 3:00 (MiniBossService): the run clock holds at 3:00 until every piece is gone.
	BigCheese = {
		Name = "The Big Cheese",
		Mechanics = "Leaves a melted cheese trail; splits on death: 1 -> 3 Cheese Wedges -> 6 Cheese Cubes",
		Mvp = true,
		Body = {
			Name = "The Big Cheese",
			Role = "Mini-boss",
			Behavior = "Walks slowly at the chef; splits into 3 Cheese Wedges",
			Mvp = true,
			Hp = 1200, -- doubled after the first playtest (was 600: beaten in 9 s)
			Speed = 6,
			Damage = 12,
			Tips = 20,
			PieDropChance = 1, -- always drops a pie when it splits: a breather for weak builds
			Size = Vector3.new(6, 6, 6),
			Shape = "Ball",
			Color = Color3.fromRGB(255, 200, 60),
			Movement = "Chase",
			SplitInto = "CheeseWedge",
			SplitCount = 3,
		},
		-- Melted cheese (#99): stepping in it hurts, so it can't be kited round the same ground.
		-- Only the big one leaves a trail, not its Wedges or Cubes.
		Trail = {
			Spacing = 1.5,
			Seconds = 4,
			Width = 3,
			Damage = 20,
			HitCooldown = 1,
			Color = Color3.fromRGB(255, 205, 40),
		},
	},
	MicrowaveMonster = {
		Name = "Microwave Monster",
		Mechanics = "Summons minions, sends out damage pulses and fires homing popcorn; below half HP, takes turns with spinning lasers in the middle",
		Mvp = true,
		Body = {
			Name = "Microwave Monster",
			Role = "Final boss",
			Behavior = "Walks slowly at the chef",
			Mvp = true,
			Hp = 5000, -- two HP phases (#91): aiming for a fight of about 60 s
			Speed = 5,
			Damage = 25, -- 4 touches take a full-HP chef (100)
			HurtCooldown = 1, -- at most one touch hit per second
			Tips = 50,
			-- 8 wide: the chef stops 5.5 studs from its center and is touched within 6.25, so the
			-- knife (10) can hit it from outside touch range.
			Size = Vector3.new(8, 7, 7),
			Shape = "Block",
			Color = Color3.fromRGB(225, 228, 232),
			Movement = "Chase",
		},
		Power = "MicrowavePulse",
		Fight = {
			ArenaRadius = 38,
			SummonEvery = 7,
			SummonEnemy = "MoldyBread",
			SummonCount = 4,
			PulseEvery = 6,
			PulseWarning = 1.2,
			PulseRadius = 16,
			PulseDamage = 20,
			Phase2At = 0.5,
			PhaseChangeSeconds = 1,
			LaserWalkSpeed = 15, -- 3x its walk, still just slower than the chef (16)
			LaserSeconds = 8,
			WalkingSeconds = 8,
			PopcornEvery = 10,
			PopcornWarning = 0.6,
			PopcornEnemy = "PopcornKernel",
			PopcornSeconds = 8,
			PopWarning = 0.5,
			PopRadius = 8,
			PopDamage = 20,
			LaserCount = 6, -- was 3: too easy in playtest
			LaserWarning = 1.5,
			-- At the ring's edge (~35 studs out) 25 degrees/s is ~15 studs/s: just under the
			-- chef's 16, so you can run around with the beams anywhere in the arena.
			LaserTurnSpeed = 25,
			LaserWidth = 2,
			LaserDamage = 35,
			LaserHitCooldown = 1,
			LaserReverseAt = 0.5,
			LaserReverseTell = 0.6,
		},
	},
	Doughzilla = {
		Name = "Doughzilla",
		Mechanics = "Giant dough that grows bigger by absorbing flour clouds",
		Mvp = false,
	},
	KrakenRoll = {
		Name = "Kraken Roll",
		Mechanics = "Sushi kraken that grabs the player from the conveyor belts",
		Mvp = false,
	},
	PantryRatKing = { Name = "Pantry Rat King", Mechanics = "TBD", Mvp = false },
}

return Bosses
