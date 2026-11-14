--!strict
-- Signature Tools (PRD §3.1). The equipped Utensil is the run's starter weapon.
-- Recipes live in Recipes.luau. Combat numbers (damage, cooldown) are added in Phase 1 tuning.

export type Unlock = "Free" | "Achievement" | "Chest"

export type Starter = {
	Name: string,
	Attack: string,
	Unlock: Unlock,
	Achievement: string?,
	Mvp: boolean,
}

local Starters: { [string]: Starter } = {
	ChefsKnife = {
		Name = "Chef's Knife",
		Attack = "Quick slashes in the direction you face",
		Unlock = "Free",
		Mvp = true,
	},
	FryingPan = {
		Name = "Frying Pan",
		Attack = "Wide swing with heavy knockback",
		Unlock = "Chest",
		Mvp = true,
	},
	RollingPin = {
		Name = "Rolling Pin",
		Attack = "Rolls forward, hits everything in its path",
		Unlock = "Achievement",
		Achievement = "Clear Chapter 1",
		Mvp = true,
	},
	MeatCleaver = {
		Name = "Meat Cleaver",
		Attack = "Thrown, comes back like a boomerang",
		Unlock = "Achievement",
		Achievement = "Defeat 5,000 enemies total",
		Mvp = false,
	},
	Whisk = {
		Name = "Whisk",
		Attack = "Spinning flurry at close range",
		Unlock = "Chest",
		Mvp = false,
	},
	Ladle = {
		Name = "Ladle",
		Attack = "Lobs soup that leaves damaging puddles",
		Unlock = "Chest",
		Mvp = false,
	},
}

return Starters
