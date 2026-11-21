--!strict
-- Account XP and levels (P2-7a #161, PRD §4.5; design: docs/superpowers/specs/2026-11-20-talents-chests-design.md).
--
-- The ONLY service that changes the save's Talents section: { Level, Xp, Bought }.
--   Level   account level, 1 to Talents.MaxLevel
--   Xp      XP into the current level (at the max level it keeps adding up, unused for now)
--   Bought  talent nodes bought, in order (P2-7b, #162)
--
-- addXp() is the one way XP is added: run rewards (#106) call it when a run ends, DEV tools
-- call it too. A big grant can give several levels at once.
--
-- Player attributes set here:
--   "AccountLevel", "AccountXp", "AccountXpNeeded"  for the lobby's Home screen (XpNeeded is nil at
--                                                    the max level)
--   "JustLeveledAccount" = <new level>  levels gained since this run started (not in the lobby), for
--                                       the run-over banner; cleared when a new run starts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local RunManager = require(script.Parent.RunManager)
local Talents = require(ReplicatedStorage.Config.Talents)

local TalentService = {}

export type TalentData = { Level: number, Xp: number, Bought: number }

-- XP to go from account Lv `level` to the next one.
function TalentService.xpToNext(level: number): number
	return Talents.Xp.Base + Talents.Xp.Step * (level - 1)
end

-- The save's Talents section with every field in range (a new save starts with an empty table).
local function getTalents(data: DataService.Data): TalentData
	local talents: any = data.Talents
	local level = if type(talents.Level) == "number" then math.floor(talents.Level) else 1
	talents.Level = math.clamp(level, 1, Talents.MaxLevel)
	talents.Xp = if type(talents.Xp) == "number" then math.max(math.floor(talents.Xp), 0) else 0
	talents.Bought = if type(talents.Bought) == "number" then math.clamp(talents.Bought, 0, talents.Level) else 0
	return talents
end

local function syncAttributes(player: Player, talents: TalentData)
	player:SetAttribute("AccountLevel", talents.Level)
	player:SetAttribute("AccountXp", talents.Xp)
	player:SetAttribute(
		"AccountXpNeeded",
		if talents.Level < Talents.MaxLevel then TalentService.xpToNext(talents.Level) else nil
	)
end

-- The player's account level (1 before the save loads).
function TalentService.getLevel(player: Player): number
	local data = DataService.get(player)
	return if data then getTalents(data).Level else 1
end

-- Add account XP; levels come as soon as there's enough. Returns the levels gained (0 if the save
-- hasn't loaded or the amount isn't a positive number).
function TalentService.addXp(player: Player, amount: number): number
	local data = DataService.get(player)
	if not data or amount ~= amount or amount <= 0 then
		return 0
	end
	local talents = getTalents(data)
	talents.Xp += math.floor(amount)
	local gained = 0
	while talents.Level < Talents.MaxLevel and talents.Xp >= TalentService.xpToNext(talents.Level) do
		talents.Xp -= TalentService.xpToNext(talents.Level)
		talents.Level += 1
		gained += 1
	end
	syncAttributes(player, talents)
	if gained > 0 and not RunManager.isInLobby() then
		player:SetAttribute("JustLeveledAccount", talents.Level)
	end
	return gained
end

-- A new run is starting: the banner shouldn't announce the last run's level again.
function TalentService.clearJustLeveled()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("JustLeveledAccount", nil)
	end
end

-- DEV: back to account Lv 1, 0 XP, no talents bought.
function TalentService.resetTalents(player: Player)
	local data = DataService.get(player)
	if data then
		data.Talents = { Level = 1, Xp = 0, Bought = 0 }
		syncAttributes(player, getTalents(data))
	end
end

function TalentService:start()
	DataService.onLoaded(function(player: Player, data: DataService.Data)
		syncAttributes(player, getTalents(data))
	end)
end

return TalentService
