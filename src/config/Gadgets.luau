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
	ShotSize: Vector3?, -- Projectile only: size of the flying part (a toast slice if left out)
	-- Arc only: attack toward the nearest enemy instead of the way the chef walks (which is
	-- usually away from the enemies). Falls back to the chef's facing when nothing is near.
	AimAtNearest: boolean?,
}

local Gadgets: { [string]: Gadget } = {
	PepperShaker = {
		Name = "Pepper Shaker",
		Behavior = "Sprays a burning cone at the nearest enemy",
		Shape = "Arc",
		AimAtNearest = true,
		FxColor = Color3.fromRGB(230, 60, 30),
		Levels = {
			{ Damage = 4, Cooldown = 1.2, Range = 9, ArcDegrees = 75, BurnDps = 3, BurnSeconds = 2 },
			{ Damage = 5, Cooldown = 1.2, Range = 9, ArcDegrees = 75, BurnDps = 4, BurnSeconds = 2 },
			{ Damage = 5, Cooldown = 1.2, Range = 10, ArcDegrees = 90, BurnDps = 4, BurnSeconds = 2 },
			{ Damage = 7, Cooldown = 1.2, Range = 10, ArcDegrees = 90, BurnDps = 6, BurnSeconds = 2 },
			{ Damage = 7, Cooldown = 0.9, Range = 10, ArcDegrees = 105, BurnDps = 6, BurnSeconds = 3 },
		},
	},
	-- Lob (#129): slow and splashy, for crowds. The egg lands where the enemy was, so it can miss fast ones.
	EggGrenade = {
		Name = "Egg Grenade",
		Behavior = "Lobbed, splash damage",
		Shape = "Lob",
		FxColor = Color3.fromRGB(255, 240, 200),
		Levels = {
			{ Damage = 12, Cooldown = 2.0, Range = 30, Count = 1, Radius = 5 },
			{ Damage = 14, Cooldown = 2.0, Range = 30, Count = 1, Radius = 5.5 },
			{ Damage = 14, Cooldown = 1.8, Range = 30, Count = 2, Radius = 5.5 },
			{ Damage = 17, Cooldown = 1.8, Range = 30, Count = 2, Radius = 6.5 },
			{ Damage = 20, Cooldown = 1.6, Range = 30, Count = 2, Radius = 7 },
		},
	},
	-- Bounce (#130): one disc that chains through a crowd, hitting each enemy once.
	PizzaCutter = {
		Name = "Pizza Cutter",
		Behavior = "Disc that bounces between enemies",
		Shape = "Bounce",
		FxColor = Color3.fromRGB(220, 225, 235),
		Levels = {
			{ Damage = 9, Cooldown = 1.5, Range = 30, Count = 1, Speed = 40, Bounces = 3, BounceRange = 12 },
			{ Damage = 11, Cooldown = 1.5, Range = 30, Count = 1, Speed = 40, Bounces = 4, BounceRange = 12 },
			{ Damage = 11, Cooldown = 1.3, Range = 30, Count = 1, Speed = 40, Bounces = 5, BounceRange = 13 },
			{ Damage = 14, Cooldown = 1.3, Range = 30, Count = 1, Speed = 40, Bounces = 6, BounceRange = 13 },
			{ Damage = 16, Cooldown = 1.1, Range = 30, Count = 1, Speed = 40, Bounces = 7, BounceRange = 14 },
		},
	},
	SpinningForks = {
		Name = "Spinning Forks",
		Behavior = "Forks orbit you",
		Shape = "Orbit",
		FxColor = Color3.fromRGB(200, 200, 210),
		Levels = {
			{ Damage = 4, Cooldown = 0.6, Range = 7, Count = 2, Speed = 180 },
			{ Damage = 4, Cooldown = 0.6, Range = 7, Count = 3, Speed = 180 },
			{ Damage = 5, Cooldown = 0.6, Range = 7, Count = 3, Speed = 180 },
			{ Damage = 5, Cooldown = 0.6, Range = 8, Count = 4, Speed = 180 },
			{ Damage = 8, Cooldown = 0.6, Range = 8, Count = 4, Speed = 240 },
		},
	},
	Toaster = {
		Name = "Toaster",
		Behavior = "Launches toast at the nearest enemies",
		Shape = "Projectile",
		FxColor = Color3.fromRGB(210, 150, 70),
		Levels = {
			{ Damage = 8, Cooldown = 1.4, Range = 40, Count = 1, Speed = 45 },
			{ Damage = 8, Cooldown = 1.4, Range = 40, Count = 2, Speed = 45 },
			{ Damage = 10, Cooldown = 1.4, Range = 40, Count = 2, Speed = 45 },
			{ Damage = 10, Cooldown = 1.2, Range = 40, Count = 3, Speed = 45 },
			{ Damage = 14, Cooldown = 1.2, Range = 40, Count = 4, Speed = 45 },
		},
	},
	-- The 7th gadget (#132, replacing the Blender): piercing ice cubes that slow. Best down a
	-- line of enemies, where the Toaster is best on single ones.
	IceCubeTray = {
		Name = "Ice Cube Tray",
		Behavior = "Slides ice cubes that pierce through enemies and slow them",
		Shape = "Projectile",
		FxColor = Color3.fromRGB(170, 225, 255),
		ShotSize = Vector3.new(1.3, 1.3, 1.3),
		Levels = {
			{ Damage = 9, Cooldown = 1.6, Range = 30, Count = 1, Speed = 35, Pierce = 99, Spread = 15, Slow = 0.25 },
			{ Damage = 11, Cooldown = 1.6, Range = 32, Count = 1, Speed = 35, Pierce = 99, Spread = 15, Slow = 0.25 },
			{ Damage = 11, Cooldown = 1.4, Range = 32, Count = 2, Speed = 35, Pierce = 99, Spread = 15, Slow = 0.3 },
			{ Damage = 13, Cooldown = 1.4, Range = 35, Count = 2, Speed = 35, Pierce = 99, Spread = 15, Slow = 0.3 },
			{ Damage = 15, Cooldown = 1.2, Range = 35, Count = 3, Speed = 35, Pierce = 99, Spread = 15, Slow = 0.35 },
		},
	},
	-- Trail (#131): rewards kiting. Nothing is dropped while the chef stands still.
	SqueezeBottle = {
		Name = "Squeeze Bottle",
		Behavior = "Drops a ketchup trail that slows enemies",
		Shape = "Trail",
		FxColor = Color3.fromRGB(200, 30, 30),
		Levels = {
			{ Damage = 2, Cooldown = 0.3, Range = 0, Width = 3, Seconds = 2.0, Slow = 0.3 },
			{ Damage = 3, Cooldown = 0.3, Range = 0, Width = 3, Seconds = 2.5, Slow = 0.3 },
			{ Damage = 3, Cooldown = 0.3, Range = 0, Width = 3.5, Seconds = 2.5, Slow = 0.35 },
			{ Damage = 4, Cooldown = 0.3, Range = 0, Width = 3.5, Seconds = 3.0, Slow = 0.35 },
			{ Damage = 5, Cooldown = 0.3, Range = 0, Width = 4, Seconds = 3.5, Slow = 0.4 },
		},
	},
}

return Gadgets
