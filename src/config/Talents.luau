--!strict
-- Account levels and talents (PRD §4.5; design: docs/superpowers/specs/2026-11-20-talents-chests-design.md).
-- Every number is a starting value, set in runs: it assumes a typical run pays about 100 account
-- XP (run rewards, #106, sets the real amount; then these get rescaled to keep the same pacing).
--
-- MaxLevel  the account's top level (the end of the 30-node talent path).
-- Xp        XP to go from account Lv L to L+1 = Base + Step * (L - 1). With 100 XP a run:
--           Lv 5 after ~4 runs, Lv 10 after ~12, Lv 30 after ~76.
--
-- Talent nodes (StandardCycle, specials, costs) are filled in by P2-7b (#162).

return {
	MaxLevel = 30,
	Xp = { Base = 80, Step = 13 },

	-- P2-7b (#162) turns these into the node list.
	StandardCycle = { "Attack", "MaxHp", "Armor", "PieHealing" },
	SpecialEvery = 5, -- every 5th account level is a special node
	SpecialExamples = { "ExtraStartingPie", "ExtraReroll" },
}
