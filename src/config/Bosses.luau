--!strict
-- Bosses (PRD §3.5). Which chapter uses which boss is set in Chapters.luau.

export type Boss = {
	Name: string,
	Mechanics: string,
	Mvp: boolean,
}

local Bosses: { [string]: Boss } = {
	BigCheese = { Name = "The Big Cheese", Mechanics = "Splits into smaller cheeses when damaged", Mvp = true },
	MicrowaveMonster = {
		Name = "Microwave Monster",
		Mechanics = "Summons minions and sends out damage pulses",
		Mvp = true,
	},
	Doughzilla = {
		Name = "Doughzilla",
		Mechanics = "Giant dough that grows bigger by absorbing flour clouds",
		Mvp = false,
	},
	KrakenRoll = {
		Name = "Kraken Roll",
		Mechanics = "Sushi kraken that grabs the player from the conveyor belts",
		Mvp = false,
	},
	PantryRatKing = { Name = "Pantry Rat King", Mechanics = "TBD", Mvp = false },
}

return Bosses
