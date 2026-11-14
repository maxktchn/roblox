--!strict
-- Gear meta progression (PRD §4.1 to §4.4, §4.8). Phase 2+.
-- Per-item gear entries (stats, Epic/Legendary bonus effects) get added here as they are designed.

return {
	Slots = {
		Utensil = { MainStat = "Attack", Material = "Sharpener" }, -- sets the starter weapon
		Hat = { MainStat = "Attack", Material = "HatPattern" },
		Apron = { MainStat = "Hp", Material = "ApronPattern" },
		Mitts = { MainStat = "Attack", Material = "MittPattern" },
		Shoes = { MainStat = "Hp", Material = "ShoePattern" },
	},

	-- Ordered low to high
	Rarities = {
		{ Id = "Common", Color = Color3.fromRGB(160, 160, 160), MaxLevel = 10 },
		{ Id = "Fine", Color = Color3.fromRGB(80, 190, 90), MaxLevel = 20 },
		{ Id = "Rare", Color = Color3.fromRGB(60, 130, 230), MaxLevel = 30 },
		{ Id = "Epic", Color = Color3.fromRGB(160, 80, 220), MaxLevel = 40 },
		{ Id = "Legendary", Color = Color3.fromRGB(240, 190, 40), MaxLevel = 50 },
	},

	MergeCopies = 3, -- 3 of the same item at the same tier -> 1 at the next tier
	SalvageRefund = 0.8,

	Chests = {
		Basic = { Currency = "Gold", StarterDropChance = 0.01 },
		Premium = { Currency = "Gems", StarterDropChance = 0.05, EpicPity = 30, StarterPity = 40 },
	},
}
