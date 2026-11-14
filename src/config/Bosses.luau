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
	BigCheese = { Name = "The Big Cheese", Mechanics = "Splits into smaller cheeses when damaged", Mvp = true },
	MicrowaveMonster = {
		Name = "Microwave Monster",
		Mechanics = "Summons minions and sends out damage pulses",
		Mvp = true,
		Body = {
			Name = "Microwave Monster",
			Role = "Final boss",
			Behavior = "Walks slowly at the chef",
			Mvp = true,
			Hp = 3500, -- lowered for 6-minute runs (weaker builds by the boss)
			Speed = 5,
			Damage = 25, -- 4 touches take a full-HP chef (100)
			HurtCooldown = 1, -- at most one touch hit per second
			Tips = 50,
			-- 8 wide: the chef stops 5.5 studs from its center and is touched within 6.25, so the
			-- knife (10) can hit it from outside touch range. The Blender (6 at Lv 1) can't (see #22).
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
