--!strict
-- Run report for playtesting and tuning (#22). Dev only: it changes nothing in the game.
--
-- During a run it notes: when each level-up happened, every item gained (cards, recipes,
-- DEV panel gifts), kills per enemy type, HP lost per source (enemy type or boss pulse),
-- and the lowest HP. When the run ends (RunState "Lost" or "Won") it adds the damage each
-- weapon dealt (WeaponService) and:
--   * prints the report in the Output window (copy it into #22 from there), and
--   * sends it to devs with the RunReport remote, shown on screen by DevPanelController.
-- RestartService calls RunReportService.reset() when a new run starts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossPowers = require(ReplicatedStorage.Config.BossPowers)
local Bosses = require(ReplicatedStorage.Config.Bosses)
local DevAccess = require(script.Parent.Parent.DevAccess)
local Enemies = require(ReplicatedStorage.Config.Enemies)
local EnemyService = require(script.Parent.EnemyService)
local Gadgets = require(ReplicatedStorage.Config.Gadgets)
local Ingredients = require(ReplicatedStorage.Config.Ingredients)
local Recipes = require(ReplicatedStorage.Config.Recipes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)
local Starters = require(ReplicatedStorage.Config.Starters)
local WeaponService = require(script.Parent.WeaponService)

local RunReportService = {}

-- Show "level at" these run times: 1:00, 2:00, halfway and the end of the run.
local CHECKPOINTS = { 60, 120, RunRules.RunLengthSeconds // 2, RunRules.RunLengthSeconds }

type Event = { seconds: number, text: string }

local levelUps: { Event } = {}
local itemsGained: { Event } = {}
local killsByType: { [string]: number } = {}
local damageTakenBy: { [string]: number } = {}
local lowestHp = math.huge
local reported = false

-- Last value we saw for each player attribute, to tell a level going up from going down.
local lastValues: { [string]: any } = {}

local runReport: RemoteEvent

local function formatTime(seconds: number): string
	local whole = math.floor(seconds)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- Display name for any config id (weapon, ingredient, enemy, boss).
local function nameOf(id: string): string
	local config: any = Starters[id]
		or Gadgets[id]
		or Recipes[id]
		or BossPowers[id]
		or Ingredients[id]
		or Enemies[id]
		or Bosses[id]
	if id == "BossPulse" then
		return "Boss pulse"
	end
	return if config and config.Name then config.Name else id
end

-- "Fruit Flies 160 (75%), Moldy Bread 40 (19%)", biggest first.
local function breakdown(totals: { [string]: number }): string
	local entries = {}
	local sum = 0
	for id, value in totals do
		table.insert(entries, { id = id, value = value })
		sum += value
	end
	if sum <= 0 then
		return "none"
	end
	table.sort(entries, function(a, b)
		return a.value > b.value
	end)
	local parts = {}
	for _, entry in entries do
		table.insert(parts, `{nameOf(entry.id)} {math.round(entry.value)} ({math.round(entry.value / sum * 100)}%)`)
	end
	return table.concat(parts, ", ")
end

-- The level the player had reached by `seconds` into the run.
local function levelAt(seconds: number): number
	local level = 1
	for _, event in levelUps do
		if event.seconds <= seconds then
			level = tonumber(string.match(event.text, "%d+")) or level
		end
	end
	return level
end

local function buildReport(result: string): string
	local player = Players:GetPlayers()[1]
	local endSeconds = RunManager.getRunSeconds()
	local level = player and player:GetAttribute("Level") or 1
	local kills = player and player:GetAttribute("Kills") or 0

	-- "Lv 3 at 1:00, Lv 5 at 2:00, not reached 3:00, ..."
	local checkpoints = {}
	for _, seconds in CHECKPOINTS do
		if seconds <= endSeconds then
			table.insert(checkpoints, `Lv {levelAt(seconds)} at {formatTime(seconds)}`)
		else
			table.insert(checkpoints, `not reached {formatTime(seconds)}`)
		end
	end

	local function eventList(events: { Event }): string
		if #events == 0 then
			return "none"
		end
		local parts = {}
		for _, event in events do
			table.insert(parts, `{event.text} {formatTime(event.seconds)}`)
		end
		return table.concat(parts, ", ")
	end

	local lines = {
		`RUN REPORT: {string.upper(result)} at {formatTime(endSeconds)} · Lv {level} · {kills} kills · lowest HP {if lowestHp
				== math.huge
			then "full"
			else math.round(lowestHp)}`,
		`Progress: {table.concat(checkpoints, ", ")}`,
		`Level-ups: {eventList(levelUps)}`,
		`Items: {eventList(itemsGained)}`,
		`Kills: {breakdown(killsByType)}`,
		`Damage dealt: {breakdown(WeaponService.getDamageByWeapon())}`,
		`Damage taken: {breakdown(damageTakenBy)}`,
	}
	return table.concat(lines, "\n")
end

local function sendReport(result: string)
	if reported then
		return
	end
	reported = true
	local text = buildReport(result)
	print(`\n{text}`)
	for _, player in Players:GetPlayers() do
		if DevAccess.isAllowed(player) then
			runReport:FireClient(player, text)
		end
	end
end

-- Start counting a fresh run.
function RunReportService.reset()
	table.clear(levelUps)
	table.clear(itemsGained)
	table.clear(killsByType)
	table.clear(damageTakenBy)
	lowestHp = math.huge
	reported = false
end

local function onAttributeChanged(player: Player, name: string)
	local value = player:GetAttribute(name)
	local old = lastValues[name]
	lastValues[name] = value
	local seconds = RunManager.getRunSeconds()

	if name == "RunState" then
		if value == "Lost" or value == "Won" then
			sendReport(value)
		end
		return
	end

	-- Only count things going up; resets (Lv back to 1, items removed) are ignored.
	local goesUp = type(value) == "number" and (type(old) ~= "number" or value > old)
	if not goesUp then
		return
	end
	if name == "Level" then
		table.insert(levelUps, { seconds = seconds, text = `Lv{value}` })
		return
	end
	local id = string.match(name, "^Weapon_(.+)$") or string.match(name, "^Ingredient_(.+)$")
	if id then
		-- The starter at Lv 1 is given at the start of every run, not picked.
		if id == RunRules.Starter and value == 1 then
			return
		end
		table.insert(itemsGained, { seconds = seconds, text = `{nameOf(id)} {value}` })
	end
end

local function watchPlayer(player: Player)
	for name, value in player:GetAttributes() do
		lastValues[name] = value
	end
	player.AttributeChanged:Connect(function(name: string)
		onAttributeChanged(player, name)
	end)
end

function RunReportService:start()
	runReport = Remotes.get("RunReport")

	EnemyService.onEnemyKilled(function(_enemyId, enemyType)
		killsByType[enemyType] = (killsByType[enemyType] or 0) + 1
	end)

	RunManager.onPlayerDamaged(function(hpLost: number, source: string?)
		local key = source or "Unknown"
		damageTakenBy[key] = (damageTakenBy[key] or 0) + hpLost
		lowestHp = math.min(lowestHp, (RunManager.getHp()))
	end)

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
end

return RunReportService
