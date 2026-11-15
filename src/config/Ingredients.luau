--!strict
-- Ingredients, passive upgrades (PRD §3.3). All 7 are in the MVP.
-- PerLevel is added once per ingredient level. Percentages are fractions (0.10 = 10%).

export type Stat = "Damage" | "MoveSpeed" | "Cooldown" | "CritChance" | "MaxHp" | "Armor" | "PickupRange"

export type Ingredient = {
	Name: string,
	Stat: Stat,
	PerLevel: number,
	Description: string,
}

local Ingredients: { [string]: Ingredient } = {
	HotSauce = { Name = "Hot Sauce", Stat = "Damage", PerLevel = 0.06, Description = "+6% damage" },
	Butter = { Name = "Butter", Stat = "MoveSpeed", PerLevel = 0.08, Description = "+8% move speed" },
	Coffee = { Name = "Coffee", Stat = "Cooldown", PerLevel = -0.08, Description = "-8% weapon cooldowns" },
	Salt = { Name = "Salt", Stat = "CritChance", PerLevel = 0.05, Description = "+5% crit chance" },
	Bread = { Name = "Bread", Stat = "MaxHp", PerLevel = 0.10, Description = "+10% max HP" },
	BeefJerky = { Name = "Beef Jerky", Stat = "Armor", PerLevel = 1, Description = "+1 armor" },
	FridgeMagnet = {
		Name = "Fridge Magnet",
		Stat = "PickupRange",
		PerLevel = 0.20,
		Description = "+20% tip pickup range",
	},
}

return Ingredients
