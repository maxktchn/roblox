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

export type Chapter = {
	Name: string,
	Order: number,
	Notes: string,
	MiniBoss: string?,
	FinalBoss: string,
	Timeline: { Phase }?,
	Mvp: boolean,
}

local Chapters: { [string]: Chapter } = {
	DinerKitchen = {
		Name = "Diner Kitchen",
		Order = 1,
		Notes = "Starter map",
		MiniBoss = "BigCheese",
		FinalBoss = "MicrowaveMonster",
		Timeline = {
			-- First minute: slow Moldy Bread only, so the player can level up a couple of times
			-- before the fast Fruit Flies (faster than the chef) arrive.
			{ From = 0, To = 60, Enemies = { "MoldyBread" }, SpawnsPerSecond = 0.6 },
			{ From = 60, To = 120, Enemies = { "MoldyBread", "FruitFlies" }, SpawnsPerSecond = 0.6 },
			{
				From = 120,
				To = 300,
				Enemies = { "MoldyBread", "FruitFlies", "RottenTomato", "Meatball" },
				SpawnsPerSecond = 1,
				Note = "First elite at 3:00",
			},
			{
				From = 300,
				To = 540,
				Enemies = { "MoldyBread", "FruitFlies", "RottenTomato", "Meatball", "SourLemon" },
				SpawnsPerSecond = 1.4,
				Note = "Larger waves; dinner rush swarm at 7:30",
			},
			{
				From = 540,
				To = 600,
				Enemies = { "MoldyBread", "FruitFlies", "RottenTomato", "Meatball", "SourLemon" },
				SpawnsPerSecond = 2,
				Note = "Final heavy wave",
			},
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
