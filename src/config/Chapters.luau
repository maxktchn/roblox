--!strict
-- Chapters and run timelines (PRD §3.6, §3.7). Chapters unlock in order.
-- Timeline times are in seconds. Elite timing and wave sizes are tuned in Phase 1.
-- SpawnsPerSecond counts spawn groups: most enemies spawn alone, Fruit Flies in a group
-- of GroupSize (Enemies.luau). RunManager only spawns enemies listed in RunRules.EnemyPool.

export type Phase = {
	From: number,
	To: number,
	Enemies: { string },
	SpawnsPerSecond: number,
	Note: string?,
}

-- A swarm event (#121, the dinner rush): from At (run-clock seconds) for Seconds, normal spawns
-- run SpawnScale times faster, still capped at RunRules.MaxAliveEnemies. Name shows on the HUD
-- Warning seconds before it starts and stays (smaller) until it ends. SoundId (an
-- "rbxassetid://..." id) plays with the warning; nil = no sound yet.
export type Rush = {
	Name: string,
	At: number,
	Seconds: number,
	SpawnScale: number,
	Warning: number,
	SoundId: string?,
}

export type Chapter = {
	Name: string,
	Order: number,
	Notes: string,
	MiniBoss: string?,
	FinalBoss: string,
	Timeline: { Phase }?,
	-- Run-clock seconds an elite arrives (#120), in order. Held clock time doesn't count.
	Elites: { number }?,
	Rushes: { Rush }?,
	Mvp: boolean,
}

local Chapters: { [string]: Chapter } = {
	DinerKitchen = {
		Name = "Diner Kitchen",
		Order = 1,
		Notes = "Starter map",
		MiniBoss = "BigCheese",
		FinalBoss = "MicrowaveMonster",
		-- A 6-minute run (RunRules.RunLengthSeconds); phases must run back to back up to it.
		Timeline = {
			-- Warm-up: slow Moldy Bread only, so the player can level up a couple of times
			-- before the fast Fruit Flies (faster than the chef) arrive.
			{ From = 0, To = 40, Enemies = { "MoldyBread" }, SpawnsPerSecond = 0.6 },
			{ From = 40, To = 75, Enemies = { "MoldyBread", "FruitFlies" }, SpawnsPerSecond = 0.6 },
			{
				From = 75,
				To = 180,
				Enemies = { "MoldyBread", "FruitFlies", "RottenTomato", "Meatball" },
				SpawnsPerSecond = 1,
				Note = "First elite at 1:50",
			},
			{
				From = 180,
				To = 325,
				Enemies = { "MoldyBread", "FruitFlies", "RottenTomato", "Meatball", "SourLemon" },
				SpawnsPerSecond = 1.4,
				Note = "Larger waves; dinner rush swarm at 4:30",
			},
			{
				From = 325,
				To = 360,
				Enemies = { "MoldyBread", "FruitFlies", "RottenTomato", "Meatball", "SourLemon" },
				SpawnsPerSecond = 2,
				Note = "Final heavy wave",
			},
		},
		-- 1:50, 2:40, 3:40, 4:15, 5:00, 5:40. The clock holds at 3:00 for The Big Cheese, so
		-- 3:40 always comes after it.
		Elites = { 110, 160, 220, 255, 300, 340 },
		-- 4:30 to 4:50: spawns from every side at 3x (1.4 -> 4.2 groups a second).
		Rushes = {
			{ Name = "DINNER RUSH!", At = 270, Seconds = 20, SpawnScale = 3, Warning = 2, SoundId = nil },
		},
		Mvp = true,
	},
	Bakery = {
		Name = "Bakery",
		Order = 2,
		Notes = "Flour clouds that block vision",
		FinalBoss = "Doughzilla",
		Mvp = false,
	},
	SushiBar = {
		Name = "Sushi Bar",
		Order = 3,
		Notes = "Conveyor belts that move the player",
		FinalBoss = "KrakenRoll",
		Mvp = false,
	},
	WalkInFreezer = {
		Name = "Walk-in Freezer",
		Order = 4,
		Notes = "Ice floor where players slide",
		FinalBoss = "PantryRatKing",
		Mvp = false,
	},
}

return Chapters
