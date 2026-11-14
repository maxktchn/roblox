--!strict
-- Talents (PRD §4.5). Phase 2+. One node per account level, bought with gold.
-- Node values and gold costs are designed later.

return {
	StandardCycle = { "Attack", "MaxHp", "Armor", "PieHealing" },
	SpecialEvery = 5, -- every 5th account level is a special node
	SpecialExamples = { "ExtraStartingPie", "ExtraReroll" },
}
