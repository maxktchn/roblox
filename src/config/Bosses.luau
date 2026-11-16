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
-- Power: the boss power (id in BossPowers.luau) that defeating this boss unlocks (PRD §3.8).

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
}

export type Boss = {
	Name: string,
	Mechanics: string,
	Mvp: boolean,
	Body: Enemies.Enemy?,
	Fight: BossFight?,
	Power: string?,
}

local Bosses: { [string]: Boss } = {
	-- Mini-boss at 3:00 (MiniBossService): the run clock holds at 3:00 until every piece is gone.
	BigCheese = {
		Name = "The Big Cheese",
		Mechanics = "Splits on death: 1 -> 3 Cheese Wedges -> 6 Cheese Cubes",
		Mvp = true,
		Body = {
			Name = "The Big Cheese",
			Role = "Mini-boss",
			Behavior = "Walks slowly at the chef; splits into 3 Cheese Wedges",
			Mvp = true,
			Hp = 600,
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
	},
	MicrowaveMonster = {
		Name = "Microwave Monster",
		Mechanics = "Summons minions and sends out damage pulses; below half HP, takes turns with a laser turn in the middle",
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
