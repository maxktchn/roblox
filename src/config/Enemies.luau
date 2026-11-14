--!strict
-- Normal enemies (PRD §3.4). Enemies are data + simple models, never Humanoids (PRD §8.3).
-- Hp, speed and damage are added in Phase 1 tuning.

export type Enemy = {
	Name: string,
	Role: string,
	Behavior: string,
	Mvp: boolean,
}

local Enemies: { [string]: Enemy } = {
	MoldyBread = { Name = "Moldy Bread", Role = "Basic swarm", Behavior = "Walks straight at the player", Mvp = true },
	FruitFlies = {
		Name = "Fruit Flies",
		Role = "Fast swarm",
		Behavior = "Fast, low HP, spawn in large groups",
		Mvp = true,
	},
	RottenTomato = {
		Name = "Rotten Tomato",
		Role = "Area denial",
		Behavior = "Bursts on death, leaves a slowing puddle",
		Mvp = true,
	},
	Meatball = {
		Name = "Meatball",
		Role = "Charger",
		Behavior = "Rolls toward the player in a straight line",
		Mvp = true,
	},
	SourLemon = { Name = "Sour Lemon", Role = "Ranged", Behavior = "Keeps distance and squirts juice", Mvp = true },
	SpaghettiMonster = {
		Name = "Spaghetti Monster",
		Role = "Disabler",
		Behavior = "Slows the player when touching",
		Mvp = false,
	},
	BurntToast = { Name = "Burnt Toast", Role = "Tank", Behavior = "Slow, high HP", Mvp = false },
}

return Enemies
