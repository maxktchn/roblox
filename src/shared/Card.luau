--!strict
-- What one "Order Up!" card looks like (PRD §2.3, §7.3).
-- The server builds cards (UpgradeService) and sends them to the client (OfferCards);
-- the client only draws them (UpgradeUIController). Types only, no code.

-- Starter: the player's starter weapon.   Gadget / Ingredient: the shared pool.
-- Recipe: evolves a max-level weapon (PRD §2.5). Filler: shown only when nothing else is left (Pie).
-- BossPower: an unlocked boss power (PRD §3.8); works like a gadget card.
export type Kind = "Starter" | "Gadget" | "Ingredient" | "Recipe" | "Filler" | "BossPower"

export type Card = {
	Kind: Kind,
	Id: string, -- config id, e.g. "ChefsKnife", "HotSauce", "SushiMasterBlade", "Pie"
	Name: string, -- display name, e.g. "Hot Sauce"
	FromLevel: number, -- 0 = NEW
	ToLevel: number, -- 0 for recipes and fillers (they have no level)
	Description: string, -- one line: what taking this card changes
}

return {}
