--!strict
-- Developer-only tools (not part of the game design).
--
-- Playtest DEV panel (DevCommandService + DevPanelController): buttons to level up, jump the
-- clock, start the boss, give items, heal, god mode, remove enemies, and run the playtest bot
-- (PlaytestBotService + PlaytestBotController: plays runs by itself and prints their
-- reports). Shown only to devs: same access rule as /stress (Server/DevAccess).
--
-- Stress test (issue #12, PRD §8.3): type /stress in chat during a run to max every Phase 1
-- weapon, keep RunRules.MaxAliveEnemies enemies alive, keep the chef alive, and show an
-- FPS readout. Allowed in Studio, for the experience's owner, and for the ids below.
-- Remove or empty this before launch.

return {
	-- Roblox user ids (the number in your profile URL) allowed to use the dev commands.
	DevUserIds = {
		34785286, -- thatcher989
	},

	-- Most runs the playtest bot can be asked to play in one go (DEV panel - / + buttons).
	BotMaxRuns = 10,

	-- How many spawn groups per second while stress testing: enough to refill the cap
	-- as fast as maxed weapons clear it.
	StressSpawnsPerSecond = 20,

	-- Where the run clock is held while stress testing: inside the final phase (5:25 to 6:00),
	-- so all Phase 1 enemies spawn and the boss never arrives.
	StressRunSeconds = 340,

	-- Length of the measured test: the readout shows a summary after this many seconds.
	StressMeasureSeconds = 60,
}
