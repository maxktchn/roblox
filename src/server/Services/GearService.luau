--!strict
-- Gear and currencies (P2-4, PRD §4.1 to §4.4, design: docs/superpowers/specs/2026-11-17-gear-design.md).
--
-- The ONLY service that changes the save's Gear and Currencies sections. Run rewards (#106)
-- and chests (#108) add things through give() and addCurrency(), never by editing the table.
-- Every gear number comes from GearMath, which the Gear screen uses too.
--
-- Run gear: when a run starts, the equipped items are copied into the "run gear" and their
-- bonuses go to StatsService. Changing gear during a run changes nothing until the next run.
-- The very first run starts before the save has loaded (about a second), so its gear is fixed
-- when the save arrives instead. A save that loads again mid-run (DataService.reload) doesn't
-- touch the run gear.
--
-- Free knife: a loaded save with no Chef's Knife gets a Common Lv 1 one. If nothing (or a
-- missing item) is equipped in the Utensil slot, a knife is equipped there.
--
-- Gear actions (#137) come from the Gear screen through GearAction(action, arg), only between
-- runs, and every argument is checked:
--   "Equip", id           put the item in its slot
--   "LevelUp", id         +1 level for gold and the slot's material, up to the rarity's max level
--   "Merge", { id x3 }    3 different copies of the same item and rarity -> 1 at the next rarity,
--                         Lv 1, with 80% of the 3 copies' levelling spend back
--   "Salvage", id         destroy it for its rarity's gold, 1 material and 80% of its levelling
--                         spend; never the equipped item or the last Chef's Knife
-- After every action (and on load, when a run starts or ends, and after DEV gear changes) the
-- client gets GearState(state, message?): a copy of the items, equipped ids and currencies, plus
-- CanChange (false while a run is on). `message` says why an action was refused.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local Gear = require(ReplicatedStorage.Config.Gear)
local GearMath = require(ReplicatedStorage.Shared.GearMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunManager = require(script.Parent.RunManager)
local StatsService = require(script.Parent.StatsService)

local GearService = {}

-- The item everyone always owns (it can't be salvaged away).
local FREE_ITEM = "ChefsKnife"

-- What the Gear screen draws from (a copy: changing it changes nothing).
export type GearState = {
	Items: { [string]: GearMath.ItemRecord },
	Equipped: { [string]: string },
	Currencies: { [string]: number },
	CanChange: boolean, -- false while a run is on
}

local gearStateRemote: RemoteEvent? = nil

-- One equipped item, as fixed for this run.
export type RunItem = { Item: string, Rarity: string, Level: number }

local runGear: { [string]: RunItem } = {} -- [slot] = item
local runGearSet = false -- has the current run had its gear fixed yet?
local runGearCallbacks: { () -> () } = {}

local function getRunPlayer(): Player?
	return Players:GetPlayers()[1]
end

-- Add a new item to a save's gear and return its id.
local function addItem(gear: any, itemId: string, rarity: string, level: number): string
	local id = tostring(gear.NextId)
	gear.NextId += 1
	gear.Items[id] = { Item = itemId, Rarity = rarity, Level = level, SpentGold = 0, SpentMaterial = 0 }
	return id
end

-- Fix a loaded save's gear: forget equipped ids that don't exist (or sit in the wrong slot),
-- make sure a Chef's Knife is owned, and equip one if the Utensil slot is empty.
local function repair(gear: any)
	for slot, id in gear.Equipped do
		local record = gear.Items[id]
		if not record or GearMath.slot(record.Item) ~= slot then
			gear.Equipped[slot] = nil
		end
	end
	local knifeId: string? = nil
	for id, record in gear.Items do
		if record.Item == FREE_ITEM then
			knifeId = id
			break
		end
	end
	if not knifeId then
		knifeId = addItem(gear, FREE_ITEM, Gear.Rarities[1].Id, 1)
	end
	if not gear.Equipped.Utensil then
		gear.Equipped.Utensil = knifeId
	end
end

-- Make sure the save has gold and every slot's material (0 if missing), so a material added or
-- renamed in Gear.Slots never breaks levelling, merging or salvaging.
local function repairCurrencies(currencies: { [string]: number })
	if currencies.Gold == nil then
		currencies.Gold = 0
	end
	for _, slot in Gear.Slots do
		if currencies[slot.Material] == nil then
			currencies[slot.Material] = 0
		end
	end
end

-- Give a player a new item (DEV tools now; run rewards and chests later). Returns its id, or nil
-- if the save isn't loaded or the item or rarity is unknown. The level is kept within the rarity's cap.
function GearService.give(player: Player, itemId: string, rarity: string, level: number?): string?
	local data = DataService.get(player)
	local maxLevel = GearMath.maxLevel(rarity)
	if not (data and Gear.Items[itemId] and maxLevel) then
		return nil
	end
	return addItem(data.Gear, itemId, rarity, math.clamp(math.floor(level or 1), 1, maxLevel))
end

-- Add (or, with a negative amount, take) gold or a material. Never goes below 0.
function GearService.addCurrency(player: Player, name: string, amount: number)
	local data = DataService.get(player)
	if data and data.Currencies[name] ~= nil then
		data.Currencies[name] = math.max(data.Currencies[name] + amount, 0)
	end
end

-- How much gold or a material the player has (0 before the save loads).
function GearService.getCurrency(player: Player, name: string): number
	local data = DataService.get(player)
	return data and data.Currencies[name] or 0
end

-- A run is starting: fix the run gear from what's equipped and hand its bonuses to StatsService.
-- RestartService calls this after RunManager.reset(). Without a loaded save the run has no gear;
-- it's fixed when the save arrives.
function GearService.startRun()
	table.clear(runGear)
	local player = getRunPlayer()
	local data = player and DataService.get(player)
	local attack, hp = 0, 0
	runGearSet = data ~= nil
	if data then
		for slot, id in data.Gear.Equipped do
			local record = data.Gear.Items[id]
			if record and GearMath.slot(record.Item) == slot then
				runGear[slot] = { Item = record.Item, Rarity = record.Rarity, Level = record.Level }
				local bonus = GearMath.bonus(record.Item, record.Rarity, record.Level)
				if GearMath.mainStat(record.Item) == "Attack" then
					attack += bonus
				else
					hp += bonus
				end
			end
		end
	end
	StatsService.setGearBonuses(attack, hp)
	for _, callback in runGearCallbacks do
		task.spawn(callback)
	end
end

-- This run's gear, by slot. Don't change it.
function GearService.getRunGear(): { [string]: RunItem }
	return runGear
end

-- Run `callback` every time the run gear is fixed (a run starts, or the first save arrives).
-- GearEffectsService turns bonus effects on from here.
function GearService.onRunGear(callback: () -> ())
	table.insert(runGearCallbacks, callback)
end

--------------------------------------------------------------------------------
-- Gear actions (#137)
--------------------------------------------------------------------------------

-- "HatPattern" -> "Hat Pattern", for messages.
local function spaced(name: string): string
	return (string.gsub(name, "(%l)(%u)", "%1 %2"))
end

-- The player's save, if gear may change right now; otherwise nil and why not.
local function changeableData(player: Player): (DataService.Data?, string?)
	local data = DataService.get(player)
	if not data then
		return nil, "Your gear hasn't loaded yet"
	end
	if not RunManager.isRunOver() then
		return nil, "Change gear between runs"
	end
	return data, nil
end

-- True if `id` is equipped in any slot.
local function isEquipped(gear: any, id: string): boolean
	for _, equippedId in gear.Equipped do
		if equippedId == id then
			return true
		end
	end
	return false
end

-- A copy of the player's gear and currencies for the Gear screen (nil before the save loads).
function GearService.getState(player: Player): GearState?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	local items = {}
	for id, record in data.Gear.Items do
		items[id] = table.clone(record)
	end
	return {
		Items = items,
		Equipped = table.clone(data.Gear.Equipped),
		Currencies = table.clone(data.Currencies),
		CanChange = RunManager.isRunOver(),
	}
end

-- Send the player their gear state, with an optional message (why an action was refused).
function GearService.sendState(player: Player, message: string?)
	local state = GearService.getState(player)
	if state and gearStateRemote then
		gearStateRemote:FireClient(player, state, message)
	end
end

-- Put an item in its slot.
function GearService.equip(player: Player, id: string): (boolean, string?)
	local data, why = changeableData(player)
	if not data then
		return false, why
	end
	local record = data.Gear.Items[id]
	local slot = record and GearMath.slot(record.Item)
	if not (record and slot) then
		return false, "You don't have that item"
	end
	data.Gear.Equipped[slot] = id
	return true, nil
end

-- +1 level, for gold and the slot's material.
function GearService.levelUp(player: Player, id: string): (boolean, string?)
	local data, why = changeableData(player)
	if not data then
		return false, why
	end
	local record = data.Gear.Items[id]
	local material = record and GearMath.material(record.Item)
	local maxLevel = record and GearMath.maxLevel(record.Rarity)
	if not (record and material and maxLevel) then
		return false, "You don't have that item"
	end
	if record.Level >= maxLevel then
		return false, "Max level for this rarity: merge to go higher"
	end
	local gold, materialCost = GearMath.levelCost(record.Level)
	if data.Currencies.Gold < gold then
		return false, "Not enough gold"
	end
	if (data.Currencies[material] or 0) < materialCost then
		return false, `Not enough {spaced(material)}s`
	end
	data.Currencies.Gold -= gold
	data.Currencies[material] -= materialCost
	record.Level += 1
	record.SpentGold += gold
	record.SpentMaterial += materialCost
	return true, nil
end

-- Merge 3 different copies of the same item and rarity into 1 at the next rarity, Lv 1.
-- 80% of what was spent levelling the 3 comes back. If one of them was equipped, the new item is.
-- Returns the new item's id, or nil and why not.
function GearService.merge(player: Player, ids: { string }): (string?, string?)
	local data, why = changeableData(player)
	if not data then
		return nil, why
	end
	local gear = data.Gear
	if #ids ~= Gear.MergeCopies then
		return nil, `Pick {Gear.MergeCopies} copies to merge`
	end
	local first = gear.Items[ids[1]]
	if not first then
		return nil, "You don't have that item"
	end
	local seen: { [string]: boolean } = {}
	for _, id in ids do
		local record = gear.Items[id]
		if not record then
			return nil, "You don't have that item"
		end
		if seen[id] then
			return nil, `Pick {Gear.MergeCopies} different copies`
		end
		seen[id] = true
		if record.Item ~= first.Item or record.Rarity ~= first.Rarity then
			return nil, "Copies must be the same item and rarity"
		end
	end
	local nextRarity = GearMath.nextRarity(first.Rarity)
	if not nextRarity then
		return nil, `{first.Rarity} is the highest rarity`
	end
	local material = GearMath.material(first.Item)
	if not material then
		return nil, "You don't have that item"
	end

	local spentGold, spentMaterial, wasEquipped = 0, 0, false
	for _, id in ids do
		local record = gear.Items[id]
		spentGold += record.SpentGold
		spentMaterial += record.SpentMaterial
		wasEquipped = wasEquipped or isEquipped(gear, id)
	end
	local refundGold, refundMaterial = GearMath.refund(spentGold, spentMaterial)
	local itemId = first.Item
	for _, id in ids do
		gear.Items[id] = nil
	end
	local newId = addItem(gear, itemId, nextRarity, 1)
	local slot = GearMath.slot(itemId)
	if wasEquipped and slot then
		gear.Equipped[slot] = newId
	end
	data.Currencies.Gold += refundGold
	data.Currencies[material] += refundMaterial
	return newId, nil
end

-- Destroy an item for its rarity's gold, 1 material and 80% of what levelling it cost.
function GearService.salvage(player: Player, id: string): (boolean, string?)
	local data, why = changeableData(player)
	if not data then
		return false, why
	end
	local gear = data.Gear
	local record = gear.Items[id]
	local material = record and GearMath.material(record.Item)
	if not (record and material) then
		return false, "You don't have that item"
	end
	if isEquipped(gear, id) then
		return false, "Equip something else in its slot first"
	end
	if record.Item == FREE_ITEM then
		local knives = 0
		for _, other in gear.Items do
			if other.Item == FREE_ITEM then
				knives += 1
			end
		end
		if knives <= 1 then
			return false, `You always keep one {GearMath.itemName(FREE_ITEM)}`
		end
	end
	local gold, materialBack = GearMath.salvage(record)
	gear.Items[id] = nil
	data.Currencies.Gold += gold
	data.Currencies[material] += materialBack
	return true, nil
end

-- The GearAction remote: check the arguments, do the action, then send the new state (with why,
-- if it was refused). Anything malformed is ignored.
function GearService.handleAction(player: Player, action: unknown, arg: unknown)
	local ok, why = false, nil :: string?
	if action == "Merge" then
		if type(arg) ~= "table" then
			return
		end
		local list = arg :: { [any]: any }
		local ids: { string } = {}
		for index = 1, Gear.MergeCopies do
			local id = list[index]
			if type(id) ~= "string" then
				return
			end
			table.insert(ids, id)
		end
		if list[Gear.MergeCopies + 1] ~= nil then
			return
		end
		local newId
		newId, why = GearService.merge(player, ids)
		ok = newId ~= nil
	elseif action == "Equip" or action == "LevelUp" or action == "Salvage" then
		if type(arg) ~= "string" then
			return
		end
		if action == "Equip" then
			ok, why = GearService.equip(player, arg)
		elseif action == "LevelUp" then
			ok, why = GearService.levelUp(player, arg)
		else
			ok, why = GearService.salvage(player, arg)
		end
	else
		return
	end
	GearService.sendState(player, if ok then nil else why)
end

-- DEV: put the player's Gear and Currencies back to a new save's (just the free knife).
function GearService.resetGear(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.Gear = { NextId = 1, Items = {}, Equipped = {} }
	for name in data.Currencies do
		data.Currencies[name] = 0
	end
	repair(data.Gear)
	repairCurrencies(data.Currencies)
end

function GearService:start()
	gearStateRemote = Remotes.get("GearState")
	Remotes.get("GearAction").OnServerEvent:Connect(GearService.handleAction)
	DataService.onLoaded(function(player: Player, data: DataService.Data)
		repair(data.Gear)
		repairCurrencies(data.Currencies)
		if player == getRunPlayer() and not runGearSet then
			GearService.startRun()
		end
		GearService.sendState(player)
	end)
	-- A run starting or ending changes CanChange.
	local function watch(player: Player)
		player:GetAttributeChangedSignal("RunState"):Connect(function()
			GearService.sendState(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function()
		runGearSet = false
	end)
end

return GearService
