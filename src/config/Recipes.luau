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
	ShotSize: Vector3?, -- Projectile only, like Gadgets
	Aimed: boolean?, -- a starter's recipe stays aimed like the starter (PRD §3.1)
	AimAtNearest: boolean?, -- sprays at the nearest enemy, like its gadget (see Gadgets.luau)
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
	-- Each swing also leaves a burning arc on the floor (FireArc, #148).
	FlambePan = {
		Name = "Flambé Pan",
		Weapon = "FryingPan",
		Ingredient = "Butter",
		Description = "Each swing leaves a burning arc on the floor",
		Shape = "Arc",
		Aimed = true,
		FxColor = Color3.fromRGB(255, 120, 30),
		Levels = {
			{
				Damage = 30,
				Cooldown = 0.8,
				Range = 10,
				ArcDegrees = 200,
				Knockback = 6,
				FireArc = { Splats = 5, Width = 4, Seconds = 2.5, Damage = 3 },
			},
		},
	},
	-- A wide pin that flattens what it rolls over: can't move for 1 s, +20% damage (Flatten, #147).
	Steamroller = {
		Name = "Steamroller",
		Weapon = "RollingPin",
		Ingredient = "Bread",
		Description = "A wide pin that flattens enemies: stuck for 1 s and taking +20% damage",
		Shape = "Projectile",
		Aimed = true,
		FxColor = Color3.fromRGB(235, 205, 150),
		ShotSize = Vector3.new(6, 1.4, 1.4),
		Levels = {
			{
				Damage = 40,
				Cooldown = 1.1,
				Range = 28,
				Count = 1,
				Speed = 32,
				Pierce = 99,
				Width = 6,
				Flatten = { Seconds = 1, DamageBonus = 0.2 },
			},
		},
	},
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
		AimAtNearest = true,
		FxColor = Color3.fromRGB(190, 80, 255),
		Levels = {
			{ Damage = 7, Cooldown = 0.7, Range = 13, ArcDegrees = 120, BurnDps = 8, BurnSeconds = 3 },
		},
	},
	BreakfastBomb = {
		Name = "Breakfast Bomb",
		Weapon = "EggGrenade",
		Ingredient = "Bread",
		Description = "Eggs burst into mini-eggs that splash again",
		Shape = "Lob",
		FxColor = Color3.fromRGB(255, 200, 80),
		Levels = {
			{
				Damage = 20,
				Cooldown = 1.7,
				Range = 30,
				Count = 3,
				Radius = 7,
				Cluster = { Count = 4, Distance = 6, Damage = 9, Radius = 4 },
			},
		},
	},
	PizzaParty = {
		Name = "Pizza Party",
		Weapon = "PizzaCutter",
		Ingredient = "Coffee",
		Description = "Three discs at once, sharing the crowd",
		Shape = "Bounce",
		FxColor = Color3.fromRGB(255, 170, 60),
		Levels = {
			{ Damage = 18, Cooldown = 1.0, Range = 30, Count = 3, Speed = 40, Bounces = 2, BounceRange = 14 },
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
	ButteredBarrage = {
		Name = "Buttered Barrage",
		Weapon = "Toaster",
		Ingredient = "Butter",
		Description = "Toast pierces and leaves slippery butter",
		Shape = "Projectile",
		FxColor = Color3.fromRGB(255, 215, 90),
		Levels = {
			{
				Damage = 16,
				Cooldown = 1.0,
				Range = 40,
				Count = 6,
				Speed = 45,
				Pierce = 3,
				Slick = { Width = 4, Seconds = 3, Slow = 0.3 },
			},
		},
	},
	DeepFreeze = {
		Name = "Deep Freeze",
		Weapon = "IceCubeTray",
		Ingredient = "FridgeMagnet",
		Description = "Freezes enemies solid; frozen ones take +25% damage",
		Shape = "Projectile",
		FxColor = Color3.fromRGB(110, 190, 255),
		ShotSize = Vector3.new(1.6, 1.6, 1.6),
		Levels = {
			{
				Damage = 20,
				Cooldown = 1.0,
				Range = 40,
				Count = 5,
				Speed = 35,
				Pierce = 3,
				PierceFalloff = 0.4,
				Spread = 15,
				Freeze = 1.5,
				FrozenBonus = 0.25,
			},
		},
	},
	CondimentFlood = {
		Name = "Condiment Flood",
		Weapon = "SqueezeBottle",
		Ingredient = "Salt",
		Description = "A wide trail that can crit, and pools while you stand still",
		Shape = "Trail",
		FxColor = Color3.fromRGB(240, 120, 20),
		Levels = {
			{
				Damage = 8,
				Cooldown = 0.3,
				Range = 0,
				Width = 6,
				Seconds = 4,
				Slow = 0.5,
				StillEvery = 0.6,
				CanCrit = true,
			},
		},
	},
}

return Recipes
