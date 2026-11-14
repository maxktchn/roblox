--!strict
-- Normal enemies (PRD §3.4). Enemies are data + simple models, never Humanoids (PRD §8.3).
-- Combat numbers are Phase 1 starting values: tune here, then update the table in PRD §3.4.
--
-- Hp:     hit points
-- Speed:  studs per second (the chef walks at 16)
-- Damage: contact damage to the chef, before armor
-- Size:   size of the enemy's part, in studs
-- Shape:  "Block" or "Ball" (one simple part each, so the swarm stays cheap on phones)
-- Movement: how it moves, handled in EnemyService (one code path per movement, not per enemy):
--   "Chase"  walks straight at the chef every frame
--   "Charge" picks a direction toward the chef and rolls straight; re-aims after it
--            overshoots the chef or reaches a wall
-- GroupSize: how many spawn together in one cluster (1 if left out)

export type Enemy = {
	Name: string,
	Role: string,
	Behavior: string,
	Mvp: boolean,
	Hp: number,
	Speed: number,
	Damage: number,
	Size: Vector3,
	Shape: "Block" | "Ball",
	Color: Color3,
	Movement: "Chase" | "Charge",
	GroupSize: number?,
}

local Enemies: { [string]: Enemy } = {
	MoldyBread = {
		Name = "Moldy Bread",
		Role = "Basic swarm",
		Behavior = "Walks straight at the player",
		Mvp = true,
		Hp = 10,
		Speed = 8,
		Damage = 5,
		Size = Vector3.new(3, 3.5, 1.2),
		Shape = "Block",
		Color = Color3.fromRGB(150, 170, 90),
		Movement = "Chase",
	},
	FruitFlies = {
		Name = "Fruit Flies",
		Role = "Fast swarm",
		Behavior = "Fast, low HP, spawn in large groups",
		Mvp = true,
		Hp = 3,
		Speed = 17, -- just faster than the chef (16): can't simply be outrun
		Damage = 2,
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
		Hp = 15,
		Speed = 7,
		Damage = 6,
		Size = Vector3.new(3, 3, 3),
		Shape = "Ball",
		Color = Color3.fromRGB(170, 60, 50),
		Movement = "Chase",
	},
	Meatball = {
		Name = "Meatball",
		Role = "Charger",
		Behavior = "Rolls toward the player in a straight line",
		Mvp = true,
		Hp = 25,
		Speed = 20,
		Damage = 10,
		Size = Vector3.new(3.5, 3.5, 3.5),
		Shape = "Ball",
		Color = Color3.fromRGB(120, 70, 45),
		Movement = "Charge",
	},
	SourLemon = {
		Name = "Sour Lemon",
		Role = "Ranged",
		Behavior = "Keeps distance and squirts juice",
		Mvp = true,
		Hp = 12,
		Speed = 9,
		Damage = 6,
		Size = Vector3.new(2.8, 2.8, 2.8),
		Shape = "Ball",
		Color = Color3.fromRGB(245, 220, 60),
		Movement = "Chase",
	},
	SpaghettiMonster = {
		Name = "Spaghetti Monster",
		Role = "Disabler",
		Behavior = "Slows the player when touching",
		Mvp = false,
		Hp = 30,
		Speed = 6,
		Damage = 4,
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
		Size = Vector3.new(4, 4.5, 1.6),
		Shape = "Block",
		Color = Color3.fromRGB(60, 40, 30),
		Movement = "Chase",
	},
}

return Enemies
