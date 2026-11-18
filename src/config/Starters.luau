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
	-- Aimed: swings toward where the player aims (mouse / aim stick) instead of the way the
	-- chef faces (PRD §2.2). Only starters and their recipes; checked by ConfigCheck.
	Aimed: boolean?,
	ShotSize: Vector3?, -- Projectile only: the flying part (the Rolling Pin's pin; X is set from Width)
}

local Starters: { [string]: Starter } = {
	ChefsKnife = {
		Name = "Chef's Knife",
		Attack = "Quick slashes toward where you aim",
		Aimed = true,
		Unlock = "Free",
		Mvp = true,
		Shape = "Arc",
		FxColor = Color3.fromRGB(235, 245, 255),
		Levels = {
			{ Damage = 10, Cooldown = 0.8, Range = 10, ArcDegrees = 90 },
			{ Damage = 13, Cooldown = 0.8, Range = 10, ArcDegrees = 90 },
			{ Damage = 13, Cooldown = 0.65, Range = 11, ArcDegrees = 100 },
			{ Damage = 16, Cooldown = 0.65, Range = 12, ArcDegrees = 100 },
			{ Damage = 20, Cooldown = 0.55, Range = 12, ArcDegrees = 120 },
		},
	},
	-- P2-6b (#148): a half-circle swing that knocks enemies back (elites half as far, bosses not
	-- at all). A little less damage than the knife; it buys space instead.
	FryingPan = {
		Name = "Frying Pan",
		Attack = "Wide swing toward where you aim, knocking enemies back",
		Aimed = true,
		Unlock = "Chest",
		Mvp = true,
		Shape = "Arc",
		FxColor = Color3.fromRGB(70, 70, 80),
		Levels = {
			{ Damage = 12, Cooldown = 1.1, Range = 9, ArcDegrees = 180, Knockback = 3 },
			{ Damage = 15, Cooldown = 1.1, Range = 9, ArcDegrees = 180, Knockback = 3 },
			{ Damage = 15, Cooldown = 0.95, Range = 9.5, ArcDegrees = 190, Knockback = 3.5 },
			{ Damage = 18, Cooldown = 0.95, Range = 10, ArcDegrees = 190, Knockback = 3.5 },
			{ Damage = 20, Cooldown = 0.85, Range = 10, ArcDegrees = 200, Knockback = 4 },
		},
	},
	-- P2-6a (#147): a pin rolls toward where you aim and hits every enemy in its path once.
	-- Range is how far it rolls; Width how wide its path is. Full damage for FullDamageRange
	-- studs, then it fades to MinDamageScale by the end of the roll, so the crowd you aim at
	-- takes the hit and stragglers far behind only get grazed.
	RollingPin = {
		Name = "Rolling Pin",
		Attack = "Rolls toward where you aim, hitting everything in its path",
		Aimed = true,
		Unlock = "Achievement",
		Achievement = "Clear Chapter 1",
		Mvp = true,
		Shape = "Projectile",
		FxColor = Color3.fromRGB(205, 160, 110),
		ShotSize = Vector3.new(4, 1, 1),
		Levels = {
			{
				Damage = 14,
				Cooldown = 1.4,
				Range = 20,
				Count = 1,
				Speed = 32,
				Pierce = 99,
				Width = 4,
				FullDamageRange = 8,
				MinDamageScale = 0.4,
			},
			{
				Damage = 17,
				Cooldown = 1.4,
				Range = 20,
				Count = 1,
				Speed = 32,
				Pierce = 99,
				Width = 4,
				FullDamageRange = 8,
				MinDamageScale = 0.4,
			},
			{
				Damage = 17,
				Cooldown = 1.2,
				Range = 22,
				Count = 1,
				Speed = 32,
				Pierce = 99,
				Width = 4.5,
				FullDamageRange = 9,
				MinDamageScale = 0.4,
			},
			{
				Damage = 20,
				Cooldown = 1.2,
				Range = 24,
				Count = 1,
				Speed = 32,
				Pierce = 99,
				Width = 4.5,
				FullDamageRange = 9,
				MinDamageScale = 0.4,
			},
			{
				Damage = 24,
				Cooldown = 1.0,
				Range = 26,
				Count = 1,
				Speed = 32,
				Pierce = 99,
				Width = 5,
				FullDamageRange = 10,
				MinDamageScale = 0.4,
			},
		},
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
