--!strict
-- Gear meta progression (PRD §4.1 to §4.4, §4.8; design: docs/superpowers/specs/2026-11-17-gear-design.md).
-- Every number here is a starting value: gear needs a lot of balancing to feel right.
--
-- Items        one per slot (#105). Utensil items are starters (their names come from Starters.luau).
--              Effect = the Epic and Legendary bonus effect numbers. They're a rough outline,
--              tuned once built. FryingPan and RollingPin effects are built with those starters (#107).
-- Stats        an item's bonus goes in a straight line from its rarity's First (Lv 1) to its Max
--              (max level). Attack = % damage, Hp = % max HP, as fractions (0.02 = +2%). Every
--              rarity's First must be above the previous rarity's Max, so merging (which resets
--              to Lv 1) is never a downgrade (ConfigCheck).
-- LevelCost    gold for Lv L -> L+1 = round(Gold * Growth^(L-1)); material = ceil(Material * Growth^(L-1)).
--              Placeholders until run rewards (#106) set how much a run pays.
-- SalvageGold  gold for salvaging an item, by rarity (plus 80% of what was spent levelling it).
--              Placeholders until #106.

export type Effect = { [string]: any }

export type Item = {
	Slot: string,
	Name: string?, -- nil for Utensil items: the starter's name is used
	Effect: { Epic: Effect, Legendary: Effect },
}

export type StatRange = { First: number, Max: number }

export type Rarity = { Id: string, Color: Color3, MaxLevel: number }

local Items: { [string]: Item } = {
	ChefsKnife = {
		Slot = "Utensil",
		Effect = {
			Epic = { Every = 5 }, -- every 5th attack also throws a knife
			Legendary = { Every = 3 },
		},
	},
	FryingPan = {
		Slot = "Utensil",
		Effect = {
			Epic = { StunSeconds = 0.5, Spreads = false },
			Legendary = { StunSeconds = 1, Spreads = true }, -- the stun spreads to enemies next to it
		},
	},
	RollingPin = {
		Slot = "Utensil",
		Effect = {
			Epic = { Slow = 0.3, SlowSeconds = 2, DamageTakenBonus = 0 },
			Legendary = { Slow = 0.5, SlowSeconds = 2, DamageTakenBonus = 0.2 },
		},
	},
	ChefsHat = {
		Slot = "Hat",
		Name = "Chef's Hat",
		Effect = {
			Epic = { FreePicks = 1 }, -- free "Order Up!" picks at the start of every run
			Legendary = { FreePicks = 2 },
		},
	},
	Apron = {
		Slot = "Apron",
		Name = "Apron",
		Effect = {
			Epic = { BlockEverySeconds = 12 }, -- blocks one hit, then is ready again after this long
			Legendary = { BlockEverySeconds = 7 },
		},
	},
	OvenMitts = {
		Slot = "Mitts",
		Name = "Oven Mitts",
		Effect = {
			Epic = { Chance = 0.1, BurnDps = 5, BurnSeconds = 3, Spreads = false },
			Legendary = { Chance = 0.2, BurnDps = 5, BurnSeconds = 3, Spreads = true }, -- fire spreads on death
		},
	},
	Shoes = {
		Slot = "Shoes",
		Name = "Shoes",
		Effect = {
			Epic = { SpeedBoost = 0.3, BoostSeconds = 2, SafeSeconds = 0 }, -- after a hit
			Legendary = { SpeedBoost = 0.3, BoostSeconds = 2, SafeSeconds = 1 }, -- plus 1 s of no damage
		},
	},
}

-- Ordered low to high
local Rarities: { Rarity } = {
	{ Id = "Common", Color = Color3.fromRGB(160, 160, 160), MaxLevel = 10 },
	{ Id = "Fine", Color = Color3.fromRGB(80, 190, 90), MaxLevel = 20 },
	{ Id = "Rare", Color = Color3.fromRGB(60, 130, 230), MaxLevel = 30 },
	{ Id = "Epic", Color = Color3.fromRGB(160, 80, 220), MaxLevel = 40 },
	{ Id = "Legendary", Color = Color3.fromRGB(240, 190, 40), MaxLevel = 50 },
}

local Stats: { Attack: { [string]: StatRange }, Hp: { [string]: StatRange } } = {
	Attack = {
		Common = { First = 0.02, Max = 0.05 },
		Fine = { First = 0.08, Max = 0.14 },
		Rare = { First = 0.16, Max = 0.26 },
		Epic = { First = 0.30, Max = 0.42 },
		Legendary = { First = 0.48, Max = 0.60 },
	},
	Hp = {
		Common = { First = 0.03, Max = 0.07 },
		Fine = { First = 0.10, Max = 0.18 },
		Rare = { First = 0.20, Max = 0.33 },
		Epic = { First = 0.38, Max = 0.52 },
		Legendary = { First = 0.60, Max = 0.75 },
	},
}

return {
	Slots = {
		Utensil = { MainStat = "Attack", Material = "Sharpener" }, -- sets the starter weapon
		Hat = { MainStat = "Attack", Material = "HatPattern" },
		Apron = { MainStat = "Hp", Material = "ApronPattern" },
		Mitts = { MainStat = "Attack", Material = "MittPattern" },
		Shoes = { MainStat = "Hp", Material = "ShoePattern" },
	},

	Items = Items,
	Rarities = Rarities,
	Stats = Stats,

	LevelCost = { Gold = 100, Material = 1, Growth = 1.08 },

	SalvageGold = { Common = 20, Fine = 60, Rare = 180, Epic = 540, Legendary = 1620 },

	MergeCopies = 3, -- 3 of the same item at the same tier -> 1 at the next tier, at Lv 1
	SalvageRefund = 0.8, -- share of levelling spend given back by salvage and merge

	Chests = {
		Basic = { Currency = "Gold", StarterDropChance = 0.01 },
		Premium = { Currency = "Gems", StarterDropChance = 0.05, EpicPity = 30, StarterPity = 40 },
	},
}
