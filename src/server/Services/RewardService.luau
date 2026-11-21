--!strict
-- Run rewards (P2-5 #106, design: docs/superpowers/specs/2026-11-21-run-rewards-design.md).
--
-- When a run ends (won or lost) the player is paid by time survived: gold, account XP and random
-- gear materials (RewardMath, numbers in Config/RunRewards), times the chapter's RewardScale. A
-- clear adds a bonus. The first clear of a chapter also gives its FirstClearReward gear item,
-- once ever (recorded in the save's Rewards.FirstClears). Runs never drop other gear.
--
-- Paid in RunManager.onRunEnded, before RunState changes, so it's in the run-end save
-- (DataService) and the banner's attributes are set before the banner shows. Nothing is paid
-- if the save hasn't loaded. Quitting mid-run pays nothing.
--
-- Player attributes, for the run-over banner (cleared when the next run starts):
--   "RewardGold", "RewardXp"   numbers paid
--   "RewardMaterials"          what was rolled, as RewardMath.formatMaterials text
--   "RewardFirstClear"         e.g. "Rare Chef's Hat", only on a chapter's first clear

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chapters = require(ReplicatedStorage.Config.Chapters)
local Gear = require(ReplicatedStorage.Config.Gear)
local RewardMath = require(ReplicatedStorage.Shared.RewardMath)

local DataService = require(script.Parent.DataService)
local GearService = require(script.Parent.GearService)
local RunManager = require(script.Parent.RunManager)
local TalentService = require(script.Parent.TalentService)

local RewardService = {}

export type Paid = RewardMath.Payout & { Materials: { [string]: number } }

local ATTRIBUTES = { "RewardGold", "RewardXp", "RewardMaterials", "RewardFirstClear" }

local rng = Random.new()

local function getRunPlayer(): Player?
	return Players:GetPlayers()[1]
end

-- Pay a run's gold, XP and materials for the current chapter (no first-clear item). Returns
-- what was paid, or nil when the save hasn't loaded. DEV reward buttons use this too.
function RewardService.pay(player: Player, seconds: number, won: boolean): Paid?
	if not DataService.get(player) then
		return nil
	end
	local chapter = Chapters[RunManager.getChapter()]
	local payout = RewardMath.payout(seconds, won, if chapter then chapter.RewardScale else 1)
	local materials = RewardMath.rollMaterials(payout.MaterialDrops, rng)
	GearService.addCurrency(player, "Gold", payout.Gold)
	for material, count in materials do
		GearService.addCurrency(player, material, count)
	end
	TalentService.addXp(player, payout.Xp)
	return {
		Gold = payout.Gold,
		Xp = payout.Xp,
		MaterialDrops = payout.MaterialDrops,
		Materials = materials,
	}
end

-- Remove the banner's reward attributes (a new run is starting).
function RewardService.clearRewards()
	local player = getRunPlayer()
	if player then
		for _, name in ATTRIBUTES do
			player:SetAttribute(name, nil)
		end
	end
end

-- A chapter's first clear: give its item once ever. Returns its banner text, or nil.
local function giveFirstClear(player: Player, chapterId: string): string?
	local data = DataService.get(player)
	local reward = Chapters[chapterId] and Chapters[chapterId].FirstClearReward
	if not (data and reward) then
		return nil
	end
	data.Rewards.FirstClears = data.Rewards.FirstClears or {}
	local given = data.Rewards.FirstClears :: { [string]: boolean }
	if given[chapterId] then
		return nil
	end
	local itemId = GearService.give(player, reward.Item, reward.Rarity, 1)
	if not itemId then
		return nil
	end
	data.Gear.Items[itemId].New = true
	given[chapterId] = true
	GearService.sendState(player)
	return `{reward.Rarity} {Gear.Items[reward.Item].Name or reward.Item}`
end

local function onRunEnded(result: "Won" | "Lost")
	RewardService.clearRewards()
	local player = getRunPlayer()
	if not player then
		return
	end
	local paid = RewardService.pay(player, RunManager.getRunSeconds(), result == "Won")
	if not paid then
		return -- the save hasn't loaded: nothing paid, the banner hides the reward rows
	end
	player:SetAttribute("RewardGold", paid.Gold)
	player:SetAttribute("RewardXp", paid.Xp)
	player:SetAttribute("RewardMaterials", RewardMath.formatMaterials(paid.Materials))
	if result == "Won" then
		player:SetAttribute("RewardFirstClear", giveFirstClear(player, RunManager.getChapter()))
	end
end

function RewardService:init() end

function RewardService:start()
	RunManager.onRunEnded(onRunEnded)
end

return RewardService
