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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local Gear = require(ReplicatedStorage.Config.Gear)
local GearMath = require(ReplicatedStorage.Shared.GearMath)
local StatsService = require(script.Parent.StatsService)

local GearService = {}

-- The item everyone always owns (it can't be salvaged away).
local FREE_ITEM = "ChefsKnife"

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
end

function GearService:start()
	DataService.onLoaded(function(player: Player, data: DataService.Data)
		repair(data.Gear)
		if player == getRunPlayer() and not runGearSet then
			GearService.startRun()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		runGearSet = false
	end)
end

return GearService
