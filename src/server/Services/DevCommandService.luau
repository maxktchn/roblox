--!strict
-- Developer playtest tools, so you don't have to play 10 minutes to reach the boss.
-- The client shows a DEV panel of buttons (DevPanelController) only to devs; each button
-- sends DevAction(action, arg). The server checks the sender with DevAccess (Studio, the
-- experience's owner, or DevTools.DevUserIds) and validates every argument, so a normal
-- player can't use these even with a modified client. Remove before launch with DevTools.
--
-- Actions:
--   "LevelUp", count   gain `count` levels (1 to 20); the "Order Up!" cards come as normal
--   "SetTime", seconds jump the run clock (the boss arrives at RunLengthSeconds)
--   "Boss"             jump straight to the end of the timeline: the boss fight starts
--   "Give", id         +1 level of a gadget, ingredient or recipe (Lv 1 if not owned)
--   "Heal"             full HP
--   "God"              turn "can't die" on or off (HP refills every frame)
--   "Wipe"             remove every enemy (no tips, no kills)
--   "Restart"          start a fresh run right now, even mid-run (RestartService)
-- Replies go back with DevMessage(text) and show on the panel.
--
-- The player gets the attribute "IsDev" = true so the client knows to show the panel,
-- and "DevGod" = true/false for the god-mode button's label.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DevAccess = require(script.Parent.Parent.DevAccess)
local EnemyService = require(script.Parent.EnemyService)
local Gadgets = require(ReplicatedStorage.Config.Gadgets)
local Ingredients = require(ReplicatedStorage.Config.Ingredients)
local Recipes = require(ReplicatedStorage.Config.Recipes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RestartService = require(script.Parent.RestartService)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)
local Starters = require(ReplicatedStorage.Config.Starters)
local StatsService = require(script.Parent.StatsService)
local UpgradeService = require(script.Parent.UpgradeService)
local WeaponService = require(script.Parent.WeaponService)

local DevCommandService = {}

local MAX_LEVELS_AT_ONCE = 20

local devMessage: RemoteEvent
local godMode = false

local function reply(player: Player, text: string)
	devMessage:FireClient(player, text)
end

local function formatTime(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Tips needed to go from `level` to `level + 1` (same rule as UpgradeService, PRD §2.3).
local function tipsForLevel(level: number): number
	return RunRules.FirstLevelTips + RunRules.ExtraTipsPerLevel * (level - 1)
end

-- A whole number from the client, or nil. Rejects NaN, infinity and non-numbers.
local function toWholeNumber(value: unknown): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return math.floor(value)
end

-- +1 level of one item (Lv 1 if not owned yet), capped at its max level.
local function give(player: Player, id: string)
	if Ingredients[id] then
		local level = math.min((StatsService.getIngredientLevel(id) or 0) + 1, RunRules.SharedItemMaxLevel)
		StatsService.setIngredientLevel(id, level)
		reply(player, `{id} Lv {level}`)
		return
	end

	local weapon: any = Starters[id] or Gadgets[id] or Recipes[id]
	if not (weapon and weapon.Levels) then
		reply(player, `{id} isn't playable yet`)
		return
	end
	local recipe = Recipes[id]
	if recipe and WeaponService.getWeaponLevel(recipe.Weapon) then
		-- A recipe takes its weapon's place, like taking the recipe card does (PRD §2.5).
		WeaponService.replaceWeapon(recipe.Weapon, id)
		reply(player, `{recipe.Weapon} became {id}`)
		return
	end
	local level = math.min((WeaponService.getWeaponLevel(id) or 0) + 1, #weapon.Levels)
	WeaponService.setWeaponLevel(id, level)
	reply(player, `{id} Lv {level}`)
end

local ACTIONS: { [string]: (player: Player, arg: unknown) -> () } = {}

ACTIONS.LevelUp = function(player, arg)
	local count = math.clamp(toWholeNumber(arg) or 1, 1, MAX_LEVELS_AT_ONCE)
	local level, tips, needed = UpgradeService.getProgress()
	local total = needed - tips
	for extra = 1, count - 1 do
		total += tipsForLevel(level + extra)
	end
	UpgradeService.addTips(total)
	reply(player, `+{count} level(s): pick your cards`)
end

ACTIONS.SetTime = function(player, arg)
	local seconds = toWholeNumber(arg)
	if not seconds then
		return
	end
	seconds = math.clamp(seconds, 0, RunRules.RunLengthSeconds)
	RunManager.setRunSeconds(seconds)
	reply(player, `Clock set to {formatTime(seconds)}`)
end

ACTIONS.Boss = function(player)
	-- Reaching RunLengthSeconds is what starts the fight (RunManager -> BossService).
	RunManager.setRunSeconds(RunRules.RunLengthSeconds)
	reply(player, "Here comes the boss")
end

ACTIONS.Give = function(player, arg)
	-- Only config ids are accepted: anything else is ignored.
	if type(arg) == "string" and (Ingredients[arg] or Starters[arg] or Gadgets[arg] or Recipes[arg]) then
		give(player, arg)
	end
end

ACTIONS.Heal = function(player)
	RunManager.healPlayer(1)
	reply(player, "Healed")
end

ACTIONS.God = function(player)
	godMode = not godMode
	player:SetAttribute("DevGod", godMode)
	reply(player, if godMode then "God mode ON" else "God mode OFF")
end

ACTIONS.Restart = function(player)
	RestartService.restart()
	reply(player, "New run started")
end

ACTIONS.Wipe = function(player)
	EnemyService.clearAll()
	reply(player, "Enemies removed")
end

local function markDev(player: Player)
	if DevAccess.isAllowed(player) then
		player:SetAttribute("IsDev", true)
		player:SetAttribute("DevGod", godMode)
	end
end

function DevCommandService:start()
	devMessage = Remotes.get("DevMessage")

	for _, player in Players:GetPlayers() do
		markDev(player)
	end
	Players.PlayerAdded:Connect(markDev)

	-- DevAction(action, arg): only from devs, only known actions. Arguments are checked
	-- inside each action.
	Remotes.get("DevAction").OnServerEvent:Connect(function(player: Player, action: unknown, arg: unknown)
		if not DevAccess.isAllowed(player) or type(action) ~= "string" then
			return
		end
		local handler = ACTIONS[action]
		if handler then
			handler(player, arg)
		end
	end)

	RunService.Heartbeat:Connect(function()
		if godMode and not RunManager.isRunOver() then
			RunManager.healPlayer(1)
		end
	end)
end

return DevCommandService
