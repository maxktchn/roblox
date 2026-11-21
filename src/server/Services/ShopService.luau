--!strict
-- Basic Chests (P2-7d #164, PRD §4.8; design: docs/superpowers/specs/2026-11-20-talents-chests-design.md).
-- Premium Chests, gems, gamepasses and ProcessReceipt come in Phase 3 (PRD §5).
--
-- The client only asks to open 1 or Gear.Chests.Basic.BulkCount chests (ChestAction(count)). The
-- server checks the gold, rolls every chest here, gives the items (marked New, so the Gear tab's
-- NEW badge shows) and sends back what came out: ChestResult(results) or ChestResult(nil, why).
-- The client never says what it got.
--
-- One roll:
--   1. StarterDropChance: a chest starter, Common Lv 1 (an MVP starter without an UnlockRule, other
--      than the free Chef's Knife: today only the Frying Pan).
--   2. Otherwise a gear item: a random slot, a random item from it that chests drop (any non-starter
--      item, and the Chef's Knife for the Utensil slot), at a rarity rolled from Rarities, Lv 1.
-- Duplicates are just more copies for merging (#105).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local Gear = require(ReplicatedStorage.Config.Gear)
local GearService = require(script.Parent.GearService)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunManager = require(script.Parent.RunManager)
local Starters = require(ReplicatedStorage.Config.Starters)

local ShopService = {}

-- The free starter everyone owns: chests drop it as the Utensil slot's gear item, never as a
-- "starter" drop.
local FREE_ITEM = "ChefsKnife"

-- What one chest gave.
export type ChestResult = { Item: string, Rarity: string, Starter: boolean }

local chestResult: RemoteEvent? = nil

-- Chest starters, sorted (the same order every time).
local function chestStarters(): { string }
	local ids = {}
	for id, starter in Starters do
		if starter.Mvp and not starter.UnlockRule and id ~= FREE_ITEM and Gear.Items[id] then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- Every slot's items that chests drop as gear, sorted by slot then item.
local function gearPool(): { [string]: { string } }
	local pool: { [string]: { string } } = {}
	for id, item in Gear.Items do
		if not Starters[id] or id == FREE_ITEM then
			pool[item.Slot] = pool[item.Slot] or {}
			table.insert(pool[item.Slot], id)
		end
	end
	for _, ids in pool do
		table.sort(ids)
	end
	return pool
end

local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- A rarity from Chests.Basic.Rarities, walking Gear.Rarities low to high.
local function rollRarity(random: Random): string
	local odds = Gear.Chests.Basic.Rarities
	local roll = random:NextNumber()
	local last = "Common"
	for _, rarity in Gear.Rarities do
		local chance = odds[rarity.Id]
		if chance then
			last = rarity.Id
			if roll < chance then
				return rarity.Id
			end
			roll -= chance
		end
	end
	return last -- rounding: the odds add up to (almost exactly) 1
end

-- One Basic Chest roll (no gold, nothing given). Tests call it with a seeded Random.
function ShopService.roll(random: Random): ChestResult
	local starters = chestStarters()
	if #starters > 0 and random:NextNumber() < Gear.Chests.Basic.StarterDropChance then
		return { Item = starters[random:NextInteger(1, #starters)], Rarity = "Common", Starter = true }
	end
	local pool = gearPool()
	local slots = sortedKeys(pool)
	local items = pool[slots[random:NextInteger(1, #slots)]]
	return { Item = items[random:NextInteger(1, #items)], Rarity = rollRarity(random), Starter = false }
end

local random = Random.new()

-- Give `count` rolls to the player (each item marked New). Returns what came out.
local function giveRolls(player: Player, count: number): { ChestResult }
	local data = DataService.get(player)
	local results = {}
	if not data then
		return results
	end
	for _ = 1, count do
		local result = ShopService.roll(random)
		local id = GearService.give(player, result.Item, result.Rarity, 1)
		if id then
			data.Gear.Items[id].New = true
			table.insert(results, result)
		end
	end
	return results
end

-- Open `count` Basic Chests (1 or BulkCount) for gold. Returns the results, or nil and why not.
function ShopService.open(player: Player, count: number): ({ ChestResult }?, string?)
	local chest = Gear.Chests.Basic
	if count ~= 1 and count ~= chest.BulkCount then
		return nil, nil
	end
	if not DataService.get(player) then
		return nil, "Your save hasn't loaded yet"
	end
	if not RunManager.isRunOver() then
		return nil, "Open chests between runs"
	end
	local price = chest.Price * count
	if GearService.getCurrency(player, "Gold") < price then
		return nil, `Not enough gold: {price} needed`
	end
	GearService.addCurrency(player, "Gold", -price)
	local results = giveRolls(player, count)
	DataService.saveNow(player)
	return results, nil
end

-- DEV ("Give chest roll"): one roll without paying, with the reveal.
function ShopService.giveFreeRoll(player: Player): ChestResult?
	local results = giveRolls(player, 1)
	GearService.sendState(player)
	if chestResult and results[1] then
		chestResult:FireClient(player, results, nil, 0)
	end
	return results[1]
end

-- The ChestAction remote: (count). Anything malformed is ignored.
local function onChestAction(player: Player, count: unknown)
	if type(count) ~= "number" then
		return
	end
	local results, why = ShopService.open(player, count)
	if not (results or why) then
		return
	end
	GearService.sendState(player)
	if chestResult then
		chestResult:FireClient(player, results, why, count)
	end
end

function ShopService:start()
	chestResult = Remotes.get("ChestResult")
	Remotes.get("ChestAction").OnServerEvent:Connect(onChestAction)
end

return ShopService
