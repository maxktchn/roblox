--!strict
-- Every gear calculation, in one place (P2-4, design: docs/superpowers/specs/2026-11-17-gear-design.md).
-- Used by the server (GearService) and the client (the Gear screen), so the numbers the
-- screen shows are always the numbers the server uses. Pure functions: no services, no state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gear = require(ReplicatedStorage.Config.Gear)
local Starters = require(ReplicatedStorage.Config.Starters)

local GearMath = {}

-- One owned item, as stored in the save (Data.Gear.Items[id]).
export type ItemRecord = {
	Item: string, -- a key of Gear.Items
	Rarity: string, -- a Gear.Rarities Id
	Level: number,
	SpentGold: number, -- everything spent levelling it, for refunds
	SpentMaterial: number,
}

-- Which slot an item goes in (nil for an unknown item).
function GearMath.slot(itemId: string): string?
	local item = Gear.Items[itemId]
	return item and item.Slot
end

-- The material that levels an item ("Sharpener", "HatPattern", ...).
function GearMath.material(itemId: string): string?
	local slot = GearMath.slot(itemId)
	return slot and Gear.Slots[slot] and Gear.Slots[slot].Material
end

-- "Attack" or "Hp".
function GearMath.mainStat(itemId: string): ("Attack" | "Hp")?
	local slot = GearMath.slot(itemId)
	local stat = slot and Gear.Slots[slot] and Gear.Slots[slot].MainStat
	if stat == "Attack" or stat == "Hp" then
		return stat
	end
	return nil
end

-- The name players see. Utensil items use their starter's name.
function GearMath.itemName(itemId: string): string
	local item = Gear.Items[itemId]
	if item and item.Name then
		return item.Name
	end
	local starter = Starters[itemId]
	return if starter then starter.Name else itemId
end

-- Position of a rarity, 1 (Common) to 5 (Legendary).
function GearMath.rarityIndex(rarity: string): number?
	for index, entry in Gear.Rarities do
		if entry.Id == rarity then
			return index
		end
	end
	return nil
end

function GearMath.maxLevel(rarity: string): number?
	local index = GearMath.rarityIndex(rarity)
	return index and Gear.Rarities[index].MaxLevel
end

-- The rarity a merge makes, or nil for Legendary (it can't merge).
function GearMath.nextRarity(rarity: string): string?
	local index = GearMath.rarityIndex(rarity)
	local nextEntry = index and Gear.Rarities[index + 1]
	return nextEntry and nextEntry.Id
end

-- An item's bonus (0.16 = +16% damage or HP): a straight line from its rarity's First (Lv 1)
-- to its Max (max level). 0 for anything unknown.
function GearMath.bonus(itemId: string, rarity: string, level: number): number
	local stat = GearMath.mainStat(itemId)
	local range = stat and Gear.Stats[stat][rarity]
	local maxLevel = GearMath.maxLevel(rarity)
	if not (range and maxLevel) then
		return 0
	end
	local clamped = math.clamp(level, 1, maxLevel)
	if maxLevel <= 1 then
		return range.Max
	end
	return range.First + (range.Max - range.First) * (clamped - 1) / (maxLevel - 1)
end

-- Gold and material to go from `level` to `level + 1` (same for every rarity).
function GearMath.levelCost(level: number): (number, number)
	local scale = Gear.LevelCost.Growth ^ (level - 1)
	return math.round(Gear.LevelCost.Gold * scale), math.ceil(Gear.LevelCost.Material * scale)
end

-- What comes back from spending (merge and salvage): 80% (Gear.SalvageRefund), rounded down.
function GearMath.refund(spentGold: number, spentMaterial: number): (number, number)
	return math.floor(spentGold * Gear.SalvageRefund), math.floor(spentMaterial * Gear.SalvageRefund)
end

-- Gold and material for salvaging an item: its rarity's SalvageGold and 1 material, plus 80% of
-- what was spent levelling it.
function GearMath.salvage(record: ItemRecord): (number, number)
	local gold, material = GearMath.refund(record.SpentGold, record.SpentMaterial)
	return (Gear.SalvageGold[record.Rarity] or 0) + gold, 1 + material
end

return GearMath
