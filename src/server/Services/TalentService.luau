--!strict
-- Account XP, levels and the talent path (P2-7a #161, P2-7b #162, PRD §4.5;
-- design: docs/superpowers/specs/2026-11-20-talents-chests-design.md).
--
-- The ONLY service that changes the save's Talents section: { Level, Xp, Bought }.
--   Level   account level, 1 to Talents.MaxLevel
--   Xp      XP into the current level (at the max level it keeps adding up, unused for now)
--   Bought  talent nodes bought, in order (node N needs account Lv N; TalentMath has the nodes)
--
-- addXp() is the one way XP is added: run rewards (#106) call it when a run ends, DEV tools
-- call it too. A big grant can give several levels at once.
--
-- Buying: TalentAction("Buy") from the TALENTS tab buys the next node, only between runs, when
-- the account level has reached it and there's the gold. The reply is TalentResult(bought?, why?).
--
-- Effects: every time GearService fixes a run's gear (a run starts), the bought nodes' totals go
-- to StatsService (attack, HP, armor, pie healing, pickup range, speed) and, in a run, add
-- rerolls, free picks and the starting Pie. The playtest bot can use a set number of nodes
-- instead (DEV "BotTalents"), only for its own runs; that never changes the save.
--
-- Player attributes set here:
--   "AccountLevel", "AccountXp", "AccountXpNeeded"  for the lobby's Home screen (XpNeeded is nil at
--                                                    the max level)
--   "TalentsBought"                     nodes bought, for the TALENTS tab and the banner
--   "JustLeveledAccount" = <new level>  levels gained since this run started (not in the lobby), for
--                                       the run-over banner; cleared when a new run starts
--   "BotTalents"                        the bot's node count (DEV); nil = the save's

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local GearService = require(script.Parent.GearService)
local PickupService = require(script.Parent.PickupService)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunManager = require(script.Parent.RunManager)
local StatsService = require(script.Parent.StatsService)
local TalentMath = require(ReplicatedStorage.Shared.TalentMath)
local Talents = require(ReplicatedStorage.Config.Talents)
local UpgradeService = require(script.Parent.UpgradeService)

local TalentService = {}

-- How far from the chef the starting Pie lands (studs, sideways).
local STARTING_PIE_OFFSET = Vector3.new(5, 0, 0)

local talentResult: RemoteEvent? = nil
local botNodes: number? = nil -- DEV: nodes the bot's runs use (nil = the save's)

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
	player:SetAttribute("TalentsBought", talents.Bought)
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

-- How many talent nodes the player has bought (0 before the save loads).
function TalentService.getBought(player: Player): number
	local data = DataService.get(player)
	return if data then getTalents(data).Bought else 0
end

-- The nodes this run uses: the save's, or the DEV bot setting while the bot plays.
function TalentService.getRunNodes(player: Player): number
	if botNodes and player:GetAttribute("BotRunning") == true then
		return botNodes
	end
	return TalentService.getBought(player)
end

-- Buy the next node. Returns the node's number, or nil and why not.
function TalentService.buy(player: Player): (number?, string?)
	local data = DataService.get(player)
	if not data then
		return nil, "Your save is still loading"
	end
	if not RunManager.isRunOver() then
		return nil, "Buy talents between runs"
	end
	local talents = getTalents(data)
	local number = talents.Bought + 1
	if number > Talents.MaxLevel then
		return nil, "Every talent is bought"
	end
	if number > talents.Level then
		return nil, `Needs account Lv {number}`
	end
	local cost = TalentMath.cost(number)
	if GearService.getCurrency(player, "Gold") < cost then
		return nil, `Not enough gold: {cost} needed`
	end
	GearService.addCurrency(player, "Gold", -cost)
	talents.Bought = number
	syncAttributes(player, talents)
	DataService.saveNow(player)
	return number, nil
end

-- DEV: the bot's runs use `nodes` talent nodes (0 to MaxLevel), or nil for the save's.
function TalentService.setBotNodes(player: Player, nodes: number?)
	botNodes = if nodes then math.clamp(math.floor(nodes), 0, Talents.MaxLevel) else nil
	player:SetAttribute("BotTalents", botNodes)
end

-- The run's gear was just fixed (a run starts): turn the talents on for it.
local function applyRunTalents()
	local player = Players:GetPlayers()[1]
	if not player then
		return
	end
	local totals = TalentMath.totals(TalentService.getRunNodes(player))
	StatsService.setTalentBonuses({
		Attack = totals.Attack,
		MaxHp = totals.MaxHp,
		Armor = totals.Armor,
		PieHealing = totals.PieHealing,
		PickupRange = totals.PickupRange,
		MoveSpeed = totals.MoveSpeed,
	})
	if RunManager.isInLobby() or RunManager.isRunOver() then
		return -- the run perks are only for a run being played
	end
	UpgradeService.addRerolls(totals.Reroll)
	if totals.FreePick > 0 then
		UpgradeService.grantLevelUps(totals.FreePick)
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		for i = 1, totals.StartingPie do
			PickupService.dropPie(root.Position + STARTING_PIE_OFFSET * i)
		end
	end
end

local function onTalentAction(player: Player, action: unknown)
	if player ~= Players:GetPlayers()[1] or action ~= "Buy" then
		return
	end
	local bought, why = TalentService.buy(player)
	GearService.sendState(player) -- the new gold
	if talentResult then
		talentResult:FireClient(player, bought, why)
	end
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
		GearService.sendState(player)
		syncAttributes(player, getTalents(data))
	end
end

function TalentService:start()
	talentResult = Remotes.get("TalentResult")
	Remotes.get("TalentAction").OnServerEvent:Connect(onTalentAction)
	GearService.onRunGear(applyRunTalents)
	DataService.onLoaded(function(player: Player, data: DataService.Data)
		syncAttributes(player, getTalents(data))
	end)
end

return TalentService
