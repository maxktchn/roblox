--!strict
-- Recipes / evolutions (PRD §2.5, §3.1, §3.2).
-- Condition: Weapon at max level + Ingredient owned (any level).
-- Weapon is an id from Starters or Gadgets; Ingredient is an id from Ingredients.

export type Recipe = {
	Name: string,
	Weapon: string,
	Ingredient: string,
	Description: string?,
}

local Recipes: { [string]: Recipe } = {
	-- Starters
	SushiMasterBlade = {
		Name = "Sushi Master Blade",
		Weapon = "ChefsKnife",
		Ingredient = "Salt",
		Description = "Crit combos",
	},
	FlambePan = {
		Name = "Flambé Pan",
		Weapon = "FryingPan",
		Ingredient = "Butter",
		Description = "Leaves a fire trail",
	},
	Steamroller = { Name = "Steamroller", Weapon = "RollingPin", Ingredient = "Bread" },
	ButchersFury = { Name = "Butcher's Fury", Weapon = "MeatCleaver", Ingredient = "HotSauce" },
	HurricaneWhisk = { Name = "Hurricane Whisk", Weapon = "Whisk", Ingredient = "Coffee" },
	StewCauldron = { Name = "Stew Cauldron", Weapon = "Ladle", Ingredient = "BeefJerky" },

	-- Gadgets
	GhostPepperBlaster = { Name = "Ghost Pepper Blaster", Weapon = "PepperShaker", Ingredient = "HotSauce" },
	BreakfastBomb = {
		Name = "Breakfast Bomb",
		Weapon = "EggGrenade",
		Ingredient = "Bread",
		Description = "Cluster splash",
	},
	PizzaParty = { Name = "Pizza Party", Weapon = "PizzaCutter", Ingredient = "Coffee", Description = "Multiple discs" },
	SmoothieVortex = {
		Name = "Smoothie Vortex",
		Weapon = "Blender",
		Ingredient = "FridgeMagnet",
		Description = "Pulls enemies in",
	},
	FondueRing = {
		Name = "Fondue Ring",
		Weapon = "SpinningForks",
		Ingredient = "BeefJerky",
		Description = "Burning orbit",
	},
	ButteredBarrage = { Name = "Buttered Barrage", Weapon = "Toaster", Ingredient = "Butter" },
	CondimentFlood = { Name = "Condiment Flood", Weapon = "SqueezeBottle", Ingredient = "Salt" },
}

return Recipes
