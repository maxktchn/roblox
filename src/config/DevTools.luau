--!strict
-- Developer-only tools (not part of the game design).
--
-- Stress test (issue #12, PRD §8.3): type /stress in chat during a run to max every Phase 1
-- weapon, keep RunRules.MaxAliveEnemies enemies alive, keep the chef alive, and show an
-- FPS readout. Allowed in Studio, for the experience's owner, and for the ids below.
-- Remove or empty this before launch.

return {
	-- Roblox user ids (the number in your profile URL) allowed to use /stress.
	DevUserIds = {
		34785286, -- thatcher989
	},

	-- How many spawn groups per second while stress testing: enough to refill the cap
	-- as fast as maxed weapons clear it.
	StressSpawnsPerSecond = 20,

	-- Where the run clock is held while stress testing: inside the final phase (9:00 to 10:00),
	-- so all Phase 1 enemies spawn and the boss never arrives.
	StressRunSeconds = 545,

	-- Length of the measured test: the readout shows a summary after this many seconds.
	StressMeasureSeconds = 60,
}
