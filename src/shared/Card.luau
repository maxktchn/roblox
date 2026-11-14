--!strict
-- What one "Order Up!" card looks like (PRD §2.3, §7.3).
-- The server builds cards (UpgradeService) and sends them to the client (OfferCards);
-- the client only draws them (UpgradeUIController). Types only, no code.

-- Starter: the player's starter weapon.   Gadget / Ingredient: the shared pool.
-- Filler: shown only when nothing else is left (Pie).
export type Kind = "Starter" | "Gadget" | "Ingredient" | "Filler"

export type Card = {
	Kind: Kind,
	Id: string, -- config id, e.g. "ChefsKnife", "HotSauce", "Pie"
	Name: string, -- display name, e.g. "Hot Sauce"
	FromLevel: number, -- 0 = NEW
	ToLevel: number, -- 0 for fillers (they have no level)
	Description: string, -- one line: what taking this card changes
}

return {}
