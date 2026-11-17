--!strict
-- Normal enemies (PRD §3.4). Enemies are data + simple models, never Humanoids (PRD §8.3).
-- Combat numbers are Phase 1 starting values: tune here, then update the table in PRD §3.4.
--
-- Hp:     hit points
-- Speed:  studs per second (the chef walks at 16)
-- Damage: contact damage to the chef, before armor
-- Tips:   tip (XP) value it drops when defeated (PRD §2.4, §2.6)
-- Size:   size of the enemy's part, in studs
-- Shape:  "Block" or "Ball" (one simple part each, so the swarm stays cheap on phones)
-- Movement: how it moves, handled in EnemyService (one code path per movement, not per enemy):
--   "Chase"  walks straight at the chef every frame
--   "Charge" winds up (stops and wobbles, RunRules.ChargeWindupSeconds), then picks a
--            direction toward the chef and rolls straight; winds up and re-aims after it
--            overshoots the chef or reaches a wall
--   "KeepAway" keeps between KeepAway.Min and KeepAway.Max studs from the chef: walks in when
--            further, backs away when closer (always facing the chef), stands still in between
--            (Sour Lemon #118). Needs KeepAway.
-- GroupSize: how many spawn together in one cluster (1 if left out)
-- PieDropChance: chance (0 to 1) it drops a Pie that heals the chef (PRD §2.6). Left out = never.
--                 Bigger enemies only: Fruit Flies come in swarms, so pies from them would be everywhere.
-- HurtCooldown: seconds before the chef can be hurt again after this enemy's hit
--               (RunRules.ChefHurtCooldown if left out; the boss hits harder but slower)
-- SplitInto, SplitCount: when it dies, SplitCount enemies of type SplitInto appear where it
--               died (MiniBossService, The Big Cheese #84). Left out = no split.
-- DeathPuddle: when it dies (to anything), a puddle that slows the chef appears where it died
--               (PuddleService, Rotten Tomato #117). Left out = no puddle.
--   Width    studs across
--   Seconds  how long it stays (it fades out over the last second)
--   Slow     how much slower the chef walks while standing in one (0.4 = 40% slower; doesn't stack)
--   Color    the puddle's colour
-- CanBeElite: true = the elite schedule (Chapters.luau Elites, #120) can pick it. Elites are
--               bigger, tougher versions (RunRules Elite... values) that drop a Lunchbox.
-- IsElite: set only on the elite versions EnemyService makes (type "Elite_<id>"); never in this file.
-- KeepAway: Min and Max studs from the chef for "KeepAway" movement.
-- Shot: a ranged attack (JuiceService, Sour Lemon #118). Within Range studs of the chef it shoots
--               every Every seconds (the first FirstDelay seconds after getting in range).
--               Tell: it swells to Swell times its size for Windup seconds, then a blob (Size
--               studs, Color) flies flat at Speed studs/s to where the chef was, and stops there.
--               Damage is before armor, and grows over the run like contact damage.
--               Plant = true: after its first shot it stops moving for good (it still turns to
--               face the chef) and only shoots while the chef is within Range.

export type DeathPuddle = {
	Width: number,
	Seconds: number,
	Slow: number,
	Color: Color3,
}

export type KeepAway = {
	Min: number,
	Max: number,
}

export type Shot = {
	Every: number,
	FirstDelay: number,
	Windup: number,
	Swell: number,
	Speed: number,
	Damage: number,
	Range: number,
	Size: number,
	Color: Color3,
	Plant: boolean?,
}

export type Enemy = {
	Name: string,
	Role: string,
	Behavior: string,
	Mvp: boolean,
	Hp: number,
	Speed: number,
	Damage: number,
	Tips: number,
	Size: Vector3,
	Shape: "Block" | "Ball",
	Color: Color3,
	Movement: "Chase" | "Charge" | "KeepAway",
	GroupSize: number?,
	PieDropChance: number?,
	HurtCooldown: number?,
	SplitInto: string?,
	SplitCount: number?,
	DeathPuddle: DeathPuddle?,
	KeepAway: KeepAway?,
	Shot: Shot?,
	CanBeElite: boolean?,
	IsElite: boolean?,
}

local Enemies: { [string]: Enemy } = {
	MoldyBread = {
		Name = "Moldy Bread",
		Role = "Basic swarm",
		Behavior = "Walks straight at the player",
		Mvp = true,
		Hp = 25,
		Speed = 8,
		Damage = 5,
		Tips = 2,
		PieDropChance = 0.045,
		Size = Vector3.new(3, 3.5, 1.2),
		Shape = "Block",
		Color = Color3.fromRGB(150, 170, 90),
		Movement = "Chase",
		CanBeElite = true,
	},
	FruitFlies = {
		Name = "Fruit Flies",
		Role = "Fast swarm",
		Behavior = "Fast, low HP, spawn in large groups",
		Mvp = true,
		Hp = 6,
		Speed = 17, -- just faster than the chef (16): can't simply be outrun
		Damage = 2,
		Tips = 1,
		Size = Vector3.new(1.5, 1.5, 1.5),
		Shape = "Ball",
		Color = Color3.fromRGB(60, 50, 70),
		Movement = "Chase",
		GroupSize = 6,
	},
	RottenTomato = {
		Name = "Rotten Tomato",
		Role = "Area denial",
		Behavior = "Bursts on death, leaves a slowing puddle",
		Mvp = true,
		Hp = 35,
		Speed = 7,
		Damage = 6,
		Tips = 3,
		PieDropChance = 0.045,
		Size = Vector3.new(3, 3, 3),
		Shape = "Ball",
		Color = Color3.fromRGB(170, 60, 50),
		Movement = "Chase",
		CanBeElite = true,
		-- Area denial (#117): it bursts into a puddle that slows (never hurts) the chef.
		DeathPuddle = {
			Width = 6,
			Seconds = 4,
			Slow = 0.4,
			Color = Color3.fromRGB(150, 40, 35),
		},
	},
	Meatball = {
		Name = "Meatball",
		Role = "Charger",
		Behavior = "Rolls toward the player in a straight line",
		Mvp = true,
		Hp = 40,
		Speed = 24, -- well above the chef's 16: has to be dodged, not outrun
		Damage = 6, -- low per hit: it's fast and rolls back through, so it hits often
		Tips = 4,
		PieDropChance = 0.045,
		Size = Vector3.new(3.5, 3.5, 3.5),
		Shape = "Ball",
		Color = Color3.fromRGB(120, 70, 45),
		Movement = "Charge",
		CanBeElite = true,
	},
	SourLemon = {
		Name = "Sour Lemon",
		Role = "Ranged",
		Behavior = "Keeps distance and squirts juice",
		Mvp = true,
		Hp = 30,
		Speed = 9,
		Damage = 6,
		Tips = 3,
		PieDropChance = 0.045,
		Size = Vector3.new(2.8, 2.8, 2.8),
		Shape = "Ball",
		Color = Color3.fromRGB(245, 220, 60),
		-- Ranged (#118): keeps its distance (slower than the chef, so it can be caught) and lobs
		-- a slow, telegraphed blob of juice that walking sideways dodges. After its first shot
		-- it plants itself and stops moving (#122 playtest), shooting whenever the chef is in range.
		Movement = "KeepAway",
		CanBeElite = true,
		KeepAway = { Min = 18, Max = 25 },
		Shot = {
			Every = 3,
			FirstDelay = 1.5,
			Windup = 0.5,
			Swell = 1.3,
			Speed = 20,
			Damage = 8,
			Range = 45,
			Size = 1.2,
			Color = Color3.fromRGB(255, 235, 50),
			Plant = true,
		},
	},
	SpaghettiMonster = {
		Name = "Spaghetti Monster",
		Role = "Disabler",
		Behavior = "Slows the player when touching",
		Mvp = false,
		Hp = 30,
		Speed = 6,
		Damage = 4,
		Tips = 4,
		PieDropChance = 0.045,
		Size = Vector3.new(4, 4, 4),
		Shape = "Ball",
		Color = Color3.fromRGB(240, 200, 110),
		Movement = "Chase",
	},
	BurntToast = {
		Name = "Burnt Toast",
		Role = "Tank",
		Behavior = "Slow, high HP",
		Mvp = false,
		Hp = 80,
		Speed = 4,
		Damage = 12,
		Tips = 8,
		PieDropChance = 0.045,
		Size = Vector3.new(4, 4.5, 1.6),
		Shape = "Block",
		Color = Color3.fromRGB(60, 40, 30),
		Movement = "Chase",
	},
	-- The Big Cheese's pieces (#84, Bosses.luau): they only appear when a bigger piece splits,
	-- never in the normal waves (not in RunRules.EnemyPool), and they don't get run-time scaling.
	CheeseWedge = {
		Name = "Cheese Wedge",
		Role = "Mini-boss piece",
		Behavior = "Chases the chef; splits into 2 Cheese Cubes",
		Mvp = true,
		Hp = 240, -- doubled with The Big Cheese (was 120)
		Speed = 10,
		Damage = 8,
		Tips = 6,
		Size = Vector3.new(3.5, 3, 3.5),
		Shape = "Block",
		Color = Color3.fromRGB(255, 215, 100),
		Movement = "Chase",
		SplitInto = "CheeseCube",
		SplitCount = 2,
	},
	CheeseCube = {
		Name = "Cheese Cube",
		Role = "Mini-boss piece",
		Behavior = "Small and fast; just slower than the chef",
		Mvp = true,
		Hp = 80, -- doubled with The Big Cheese (was 40)
		Speed = 15,
		Damage = 5,
		Tips = 3,
		Size = Vector3.new(2, 2, 2),
		Shape = "Block",
		Color = Color3.fromRGB(255, 230, 150),
		Movement = "Chase",
	},
	-- The Microwave Monster's popcorn (#92, Bosses.luau Fight.Popcorn...): fired from the boss,
	-- never in the normal waves, no run-time scaling. It does no contact damage: when it dies
	-- (shot down, touching the chef, or after Fight.PopcornSeconds) it pops, and the pop hurts.
	PopcornKernel = {
		Name = "Popcorn Kernel",
		Role = "Boss attack",
		Behavior = "Follows the chef, then pops",
		Mvp = true,
		Hp = 400, -- lives long enough to get out of the door under a late-game build (was 150)
		Speed = 13, -- the chef runs at 16: you can outrun it, but not lose it
		Damage = 0, -- the pop does the damage, not the touch
		Tips = 5, -- only when shot down (a pop from touching or timing out drops nothing)
		Size = Vector3.new(2.5, 2.5, 2.5),
		Shape = "Ball",
		Color = Color3.fromRGB(255, 240, 190),
		Movement = "Chase",
	},
}

return Enemies
