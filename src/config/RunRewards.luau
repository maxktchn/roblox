--!strict
-- What a finished run pays (P2-5 #106, design: docs/superpowers/specs/2026-11-21-run-rewards-design.md).
-- Paid by time survived (capped at RunRules.RunLengthSeconds), plus a bonus for a clear, then
-- multiplied by the chapter's RewardScale (Chapters.luau). RewardMath does the sums.
--
-- GoldPerMinute / XpPerMinute    per minute survived (fractions of a minute count)
-- MaterialDropsPerMinute         per WHOLE minute survived; each drop is a random gear material
-- MinMaterialDrops               every run gives at least this many drops
-- ClearBonus                     added on top when the run is won

return {
	GoldPerMinute = 60,
	XpPerMinute = 25,
	MaterialDropsPerMinute = 4,
	MinMaterialDrops = 1,
	ClearBonus = { Gold = 140, Xp = 50, MaterialDrops = 5 },
}
