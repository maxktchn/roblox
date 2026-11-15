--!strict
-- Kitchen Gadgets, the shared upgrade pool (PRD §3.2). All 7 are in the MVP.
-- Recipes live in Recipes.luau. Shape and level fields are explained in Shared/WeaponTypes.
-- Numbers are Phase 1 starting values: tune here, then update the table in PRD §3.2.
-- Gadgets without Levels aren't playable yet (not in RunRules.UpgradePool).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponTypes = require(ReplicatedStorage.Shared.WeaponTypes)

export type Gadget = {
	Name: string,
	Behavior: string, -- description for players
	Shape: WeaponTypes.Shape?,
	Levels: { WeaponTypes.WeaponLevel }?,
	FxColor: Color3?, -- colour of its effect
}

local Gadgets: { [string]: Gadget } = {
	PepperShaker = {
		Name = "Pepper Shaker",
		Behavior = "Cone spray that burns",
		Shape = "Arc",
		FxColor = Color3.fromRGB(230, 60, 30),
		Levels = {
			{ Damage = 3, Cooldown = 1.2, Range = 9, ArcDegrees = 60, BurnDps = 2, BurnSeconds = 2 },
			{ Damage = 4, Cooldown = 1.2, Range = 9, ArcDegrees = 60, BurnDps = 3, BurnSeconds = 2 },
			{ Damage = 4, Cooldown = 1.2, Range = 10, ArcDegrees = 75, BurnDps = 3, BurnSeconds = 2 },
			{ Damage = 5, Cooldown = 1.2, Range = 10, ArcDegrees = 75, BurnDps = 4, BurnSeconds = 2 },
			{ Damage = 5, Cooldown = 0.9, Range = 10, ArcDegrees = 90, BurnDps = 4, BurnSeconds = 3 },
		},
	},
	EggGrenade = { Name = "Egg Grenade", Behavior = "Lobbed, splash damage" },
	PizzaCutter = { Name = "Pizza Cutter", Behavior = "Disc that bounces between enemies" },
	Blender = {
		Name = "Blender",
		Behavior = "Damage zone around you",
		Shape = "Aura",
		FxColor = Color3.fromRGB(120, 200, 255),
		Levels = {
			{ Damage = 2, Cooldown = 0.5, Range = 6 },
			{ Damage = 3, Cooldown = 0.5, Range = 6 },
			{ Damage = 3, Cooldown = 0.5, Range = 7.5 },
			{ Damage = 4, Cooldown = 0.5, Range = 7.5 },
			{ Damage = 4, Cooldown = 0.4, Range = 9 },
		},
	},
	SpinningForks = {
		Name = "Spinning Forks",
		Behavior = "Forks orbit you",
		Shape = "Orbit",
		FxColor = Color3.fromRGB(200, 200, 210),
		Levels = {
			{ Damage = 3, Cooldown = 0.6, Range = 7, Count = 2, Speed = 180 },
			{ Damage = 3, Cooldown = 0.6, Range = 7, Count = 3, Speed = 180 },
			{ Damage = 4, Cooldown = 0.6, Range = 7, Count = 3, Speed = 180 },
			{ Damage = 4, Cooldown = 0.6, Range = 8, Count = 4, Speed = 180 },
			{ Damage = 6, Cooldown = 0.6, Range = 8, Count = 4, Speed = 240 },
		},
	},
	Toaster = {
		Name = "Toaster",
		Behavior = "Launches toast at the nearest enemies",
		Shape = "Projectile",
		FxColor = Color3.fromRGB(210, 150, 70),
		Levels = {
			{ Damage = 6, Cooldown = 1.4, Range = 40, Count = 1, Speed = 45 },
			{ Damage = 6, Cooldown = 1.4, Range = 40, Count = 2, Speed = 45 },
			{ Damage = 8, Cooldown = 1.4, Range = 40, Count = 2, Speed = 45 },
			{ Damage = 8, Cooldown = 1.2, Range = 40, Count = 3, Speed = 45 },
			{ Damage = 11, Cooldown = 1.2, Range = 40, Count = 4, Speed = 45 },
		},
	},
	SqueezeBottle = { Name = "Squeeze Bottle", Behavior = "Drops a ketchup trail that slows enemies" },
}

return Gadgets
