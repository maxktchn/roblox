--!strict
-- Kitchen Gadgets, the shared upgrade pool (PRD §3.2). All 7 are in the MVP.
-- Recipes live in Recipes.luau. Combat numbers are added in Phase 1 tuning.

export type Gadget = {
	Name: string,
	Behavior: string,
}

local Gadgets: { [string]: Gadget } = {
	PepperShaker = { Name = "Pepper Shaker", Behavior = "Cone spray that burns" },
	EggGrenade = { Name = "Egg Grenade", Behavior = "Lobbed, splash damage" },
	PizzaCutter = { Name = "Pizza Cutter", Behavior = "Disc that bounces between enemies" },
	Blender = { Name = "Blender", Behavior = "Damage zone around you" },
	SpinningForks = { Name = "Spinning Forks", Behavior = "Forks orbit you" },
	Toaster = { Name = "Toaster", Behavior = "Launches toast at the nearest enemies" },
	SqueezeBottle = { Name = "Squeeze Bottle", Behavior = "Drops a ketchup trail that slows enemies" },
}

return Gadgets
