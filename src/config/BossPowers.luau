--!strict
-- Boss Powers (PRD §3.8). Beating a chapter's final boss unlocks its power for good
-- (UnlockService); after that it can show up as an "Order Up!" card. A power works like a
-- gadget: it uses one of the shared slots and levels 1 to 5. Powers have no recipes and are
-- never sold. Which powers exist in the game is RunRules.UpgradePool.BossPowers.
-- Shape and level fields are explained in Shared/WeaponTypes.
-- Numbers are Phase 1 starting values: tune here, then update the table in PRD §3.8.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponTypes = require(ReplicatedStorage.Shared.WeaponTypes)

export type BossPower = {
	Name: string,
	Behavior: string, -- description for players (shown on its NEW card)
	Boss: string, -- the boss (id in Bosses.luau) whose defeat unlocks it
	Shape: WeaponTypes.Shape,
	FxColor: Color3, -- colour of its effect
	Levels: { WeaponTypes.WeaponLevel },
}

local BossPowers: { [string]: BossPower } = {
	MicrowavePulse = {
		Name = "Microwave Pulse",
		Behavior = "A shockwave ring blasts enemies back",
		Boss = "MicrowaveMonster",
		Shape = "Pulse",
		FxColor = Color3.fromRGB(255, 190, 70),
		Levels = {
			{ Damage = 12, Cooldown = 3.0, Range = 14, Speed = 30, Knockback = 4 },
			{ Damage = 15, Cooldown = 2.8, Range = 15, Speed = 32, Knockback = 5 },
			{ Damage = 19, Cooldown = 2.6, Range = 17, Speed = 34, Knockback = 6 },
			{ Damage = 24, Cooldown = 2.4, Range = 19, Speed = 36, Knockback = 7 },
			{ Damage = 30, Cooldown = 2.2, Range = 22, Speed = 40, Knockback = 8 },
		},
	},
}

return BossPowers
