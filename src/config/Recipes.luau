--!strict
-- Recipes / evolutions (PRD §2.5, §3.1, §3.2).
-- Condition: Weapon at max level + Ingredient owned (any level).
-- Weapon is an id from Starters or Gadgets; Ingredient is an id from Ingredients.
--
-- Taking a recipe replaces its weapon in the same slot. A recipe is a weapon with a single
-- level: Shape, Levels (one entry) and FxColor work exactly like Starters and Gadgets
-- (see Shared/WeaponTypes). Recipes without them aren't playable yet; ConfigCheck makes
-- sure every recipe the Phase 1 pool can reach has them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponTypes = require(ReplicatedStorage.Shared.WeaponTypes)

export type Recipe = {
	Name: string,
	Weapon: string,
	Ingredient: string,
	Description: string?,
	Shape: WeaponTypes.Shape?,
	Levels: { WeaponTypes.WeaponLevel }?,
	FxColor: Color3?,
	Aimed: boolean?, -- a starter's recipe stays aimed like the starter (PRD §3.1)
}

local Recipes: { [string]: Recipe } = {
	-- Starters
	SushiMasterBlade = {
		Name = "Sushi Master Blade",
		Weapon = "ChefsKnife",
		Ingredient = "Salt",
		Description = "Crit combos",
		Shape = "Arc",
		Aimed = true,
		FxColor = Color3.fromRGB(255, 130, 150),
		Levels = {
			{ Damage = 30, Cooldown = 0.45, Range = 13, ArcDegrees = 150, CritBonus = 0.25 },
		},
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
	GhostPepperBlaster = {
		Name = "Ghost Pepper Blaster",
		Weapon = "PepperShaker",
		Ingredient = "HotSauce",
		Description = "A huge cone of burning spice",
		Shape = "Arc",
		FxColor = Color3.fromRGB(190, 80, 255),
		Levels = {
			{ Damage = 7, Cooldown = 0.7, Range = 13, ArcDegrees = 120, BurnDps = 8, BurnSeconds = 3 },
		},
	},
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
		Shape = "Aura",
		FxColor = Color3.fromRGB(255, 120, 200),
		Levels = {
			{ Damage = 6, Cooldown = 0.35, Range = 12, PullStrength = 8 },
		},
	},
	FondueRing = {
		Name = "Fondue Ring",
		Weapon = "SpinningForks",
		Ingredient = "BeefJerky",
		Description = "Burning orbit",
		Shape = "Orbit",
		FxColor = Color3.fromRGB(255, 200, 60),
		Levels = {
			{ Damage = 9, Cooldown = 0.5, Range = 9, Count = 6, Speed = 260, BurnDps = 4, BurnSeconds = 2 },
		},
	},
	ButteredBarrage = { Name = "Buttered Barrage", Weapon = "Toaster", Ingredient = "Butter" },
	CondimentFlood = { Name = "Condiment Flood", Weapon = "SqueezeBottle", Ingredient = "Salt" },
}

return Recipes
