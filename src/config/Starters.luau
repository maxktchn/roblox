--!strict
-- Signature Tools (PRD §3.1). The equipped Utensil is the run's starter weapon.
-- Recipes live in Recipes.luau. Shape and level fields are explained in Shared/WeaponTypes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponTypes = require(ReplicatedStorage.Shared.WeaponTypes)

export type Unlock = "Free" | "Achievement" | "Chest"

export type Starter = {
	Name: string,
	Attack: string, -- description for players
	Unlock: Unlock,
	Achievement: string?,
	Mvp: boolean,
	-- Only starters playable so far have these:
	Shape: WeaponTypes.Shape?,
	Levels: { WeaponTypes.WeaponLevel }?,
	FxColor: Color3?, -- colour of its attack effect
}

local Starters: { [string]: Starter } = {
	ChefsKnife = {
		Name = "Chef's Knife",
		Attack = "Quick slashes in the direction you face",
		Unlock = "Free",
		Mvp = true,
		Shape = "Arc",
		FxColor = Color3.fromRGB(235, 245, 255),
		Levels = {
			{ Damage = 10, Cooldown = 0.8, Range = 10, ArcDegrees = 90 },
			{ Damage = 13, Cooldown = 0.8, Range = 10, ArcDegrees = 90 },
			{ Damage = 13, Cooldown = 0.65, Range = 11, ArcDegrees = 100 },
			{ Damage = 18, Cooldown = 0.65, Range = 12, ArcDegrees = 100 },
			{ Damage = 24, Cooldown = 0.55, Range = 12, ArcDegrees = 120 },
		},
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
