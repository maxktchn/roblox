--!strict
-- Account levels and talents (PRD §4.5; design: docs/superpowers/specs/2026-11-20-talents-chests-design.md).
-- Every number is a starting value, set in runs: a typical run pays about 100 account XP and
-- 250 gold (run rewards, #106).
--
-- MaxLevel      the account's top level, and the number of talent nodes (one per level).
-- Xp            XP to go from account Lv L to L+1 = Base + Step * (L - 1). With 100 XP a run:
--               Lv 5 after ~4 runs, Lv 10 after ~12, Lv 30 after ~76.
-- Cost          gold for node N = Base + Step * (N - 1): 125 for node 1, 502 for node 30.
-- SpecialEvery  every node on a multiple of this is a special one (from Specials).
-- StandardCycle the other nodes take these in turn: node 1 the first, node 2 the second, ...
--               skipping the specials (so node 6 is the first entry again).
-- Specials      by node number. Kinds:
--                 Reroll       +Amount rerolls per run
--                 StartingPie  Amount pies on the floor beside the chef at 0:00
--                 FreePick     Amount free "Order Up!" picks at the start of each run
--                 PickupRange  +Amount (0.1 = +10%) tip pickup range
--                 MoveSpeed    +Amount (0.05 = +5%) move speed
-- Standard stats: Attack and MaxHp add to gear's % totals, Armor is flat (like Beef Jerky), and
-- PieHealing multiplies the pie's heal (0.05 = 5% more of RunRules.PieHealFraction).
-- TalentMath turns this into the node list; the effects are applied by TalentService.

export type Kind =
	"Attack"
	| "MaxHp"
	| "Armor"
	| "PieHealing"
	| "Reroll"
	| "StartingPie"
	| "FreePick"
	| "PickupRange"
	| "MoveSpeed"

export type NodeConfig = { Kind: Kind, Amount: number, Text: string }

export type Config = {
	MaxLevel: number,
	Xp: { Base: number, Step: number },
	Cost: { Base: number, Step: number },
	SpecialEvery: number,
	StandardCycle: { NodeConfig },
	Specials: { [number]: NodeConfig },
}

local Talents: Config = {
	MaxLevel = 30,
	Xp = { Base = 80, Step = 13 },
	Cost = { Base = 125, Step = 13 },
	SpecialEvery = 5,
	StandardCycle = {
		{ Kind = "Attack", Amount = 0.02, Text = "+2% attack" },
		{ Kind = "MaxHp", Amount = 0.03, Text = "+3% max HP" },
		{ Kind = "Armor", Amount = 0.5, Text = "+0.5 armor" },
		{ Kind = "PieHealing", Amount = 0.05, Text = "+5% pie healing" },
	},
	Specials = {
		[5] = { Kind = "Reroll", Amount = 1, Text = "+1 reroll per run" },
		[10] = { Kind = "StartingPie", Amount = 1, Text = "Start each run with a Pie" },
		[15] = { Kind = "FreePick", Amount = 1, Text = "+1 free Order Up! pick per run" },
		[20] = { Kind = "PickupRange", Amount = 0.1, Text = "+10% tip pickup range" },
		[25] = { Kind = "Reroll", Amount = 1, Text = "+1 reroll per run" },
		[30] = { Kind = "MoveSpeed", Amount = 0.05, Text = "+5% move speed" },
	},
}

return Talents
