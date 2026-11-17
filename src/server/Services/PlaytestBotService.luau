--!strict
-- Playtest bot (#22), server half. Dev only: started from the DEV panel (choose how many runs, then "Start bot").
-- It plays several runs in a row by itself and collects their run reports, so you can test
-- balance changes without playing every run yourself.
--
--   * The client half (PlaytestBotController) walks the chef and aims while the player has
--     the attribute "BotRunning" = true.
--   * This half picks the "Order Up!" cards, using one strategy per run (STRATEGIES, in turn),
--     and starts the next run a few seconds after one ends.
--   * When every run is done it prints one combined report in the Output window and shows
--     it on the DEV panel (RunReport remote).
--
-- The bot is not a person: it dodges and picks cards by simple rules. Use it to compare
-- builds and changes with each other, not to say how hard the game feels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Card = require(ReplicatedStorage.Shared.Card)
local DevAccess = require(script.Parent.Parent.DevAccess)
local DevTools = require(ReplicatedStorage.Config.DevTools)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RestartService = require(script.Parent.RestartService)
local RunManager = require(script.Parent.RunManager)
local RunReportService = require(script.Parent.RunReportService)
local UnlockService = require(script.Parent.UnlockService)
local UpgradeService = require(script.Parent.UpgradeService)

type Card = Card.Card

local PlaytestBotService = {}

-- One strategy per run, used in this order (and again from the top for more runs).
--   KnifeFirst:  levels the starter first, then gadgets
--   GadgetFirst: takes gadgets first, the knife last
--   Balanced:    mostly random
local STRATEGIES = { "KnifeFirst", "GadgetFirst", "Balanced" }
local SECONDS_BETWEEN_RUNS = 4 -- time to read the run-over screen before the next run
local PICK_EVERY_SECONDS = 0.4 -- how often the bot looks for open cards

-- Which ingredient the bot likes most (higher = picked first).
local INGREDIENT_LIKES: { [string]: number } =
	{ HotSauce = 4, Salt = 3, Coffee = 3, BeefJerky = 2, Bread = 2, FridgeMagnet = 1, Butter = 1 }

-- Points per card kind for each strategy. The highest-scoring card is picked.
local KIND_SCORES: { [string]: { [string]: number } } = {
	KnifeFirst = { Starter = 300, BossPower = 200, Gadget = 150, Ingredient = 100 },
	GadgetFirst = { Gadget = 300, BossPower = 280, Ingredient = 150, Starter = 50 },
}

local random = Random.new()
local running = false
local runsWanted = 0
local runNumber = 0
local reports: { string } = {}
-- Boss powers unlocked when the bot was started. Every run starts with exactly these, so a
-- boss win in one run doesn't give the next run a power (use "Unlock powers" before starting
-- the bot to test with them).
local startingUnlocks: { [string]: boolean } = {}
local closeCards: RemoteEvent
local runReport: RemoteEvent

local function strategyFor(run: number): string
	return STRATEGIES[(run - 1) % #STRATEGIES + 1]
end

local function getPlayer(): Player?
	return Players:GetPlayers()[1]
end

local function setStatus(text: string)
	local player = getPlayer()
	if player then
		player:SetAttribute("BotStatus", text)
	end
end

-- How much the bot wants this card. A little randomness so runs differ.
local function score(card: Card, strategy: string): number
	if card.Kind == "Recipe" then
		return 1000 -- a recipe is always worth taking
	end
	local points = random:NextNumber() * 5
	local kinds = KIND_SCORES[strategy]
	if kinds then
		points += kinds[card.Kind] or 0
	else
		points += random:NextNumber() * 100 -- Balanced
	end
	if card.Kind == "Ingredient" then
		points += (INGREDIENT_LIKES[card.Id] or 0) * 5
	end
	return points
end

-- Pick the best card from the open offer, if there is one.
local function pickCard()
	local offer = UpgradeService.getCurrentOffer()
	if not offer or RunManager.isRunOver() then
		return
	end
	local strategy = strategyFor(runNumber)
	local best, bestScore = 1, -math.huge
	for index, card in offer do
		local points = score(card, strategy)
		if points > bestScore then
			best, bestScore = index, points
		end
	end
	UpgradeService.chooseCard(best)
	-- The server picked, not the player's screen: tell the client to hide the cards.
	local player = getPlayer()
	if player and not UpgradeService.getCurrentOffer() then
		closeCards:FireClient(player)
	end
end

local function stopBot(text: string)
	running = false
	local player = getPlayer()
	if player then
		player:SetAttribute("BotRunning", false)
	end
	setStatus(text)
end

-- All runs done: one combined report. The first lines are a short summary, one per run.
local function finish()
	local summary = { `BOT REPORT: {#reports} run(s)` }
	for _, report in reports do
		-- First line of each report: "[Bot run 1: KnifeFirst] RUN REPORT: WON at 6:42 · ..."
		table.insert(summary, string.split(report, "\n")[1])
	end
	local text = table.concat(summary, "\n") .. "\n\n" .. table.concat(reports, "\n\n")
	print(`\n{text}`)
	local player = getPlayer()
	if player and DevAccess.isAllowed(player) then
		runReport:FireClient(player, text)
	end
	stopBot(`Bot done: {#reports} run(s), report in Output`)
end

local function startRun(run: number)
	runNumber = run
	setStatus(`Bot run {run}/{runsWanted}: {strategyFor(run)}`)
	for _, id in UnlockService.getUnlocked() do
		if not startingUnlocks[id] then
			UnlockService.lock(id)
		end
	end
	RestartService.restart()
end

-- A run ended: save its report, then start the next run or finish.
local function onRunOver()
	local report = RunReportService.getLastReport()
	if report then
		table.insert(reports, `[Bot run {runNumber}: {strategyFor(runNumber)}] {report}`)
	end
	task.delay(SECONDS_BETWEEN_RUNS, function()
		if not running then
			return -- stopped while waiting
		end
		if runNumber >= runsWanted then
			finish()
		else
			startRun(runNumber + 1)
		end
	end)
end

-- Start `runs` bot runs (up to DevTools.BotMaxRuns) from a fresh run, or 0 to stop.
function PlaytestBotService.play(runs: number)
	if runs <= 0 then
		if running then
			stopBot("Bot stopped")
		end
		return
	end
	local player = getPlayer()
	if not player then
		return
	end
	running = true
	runsWanted = math.min(runs, DevTools.BotMaxRuns)
	table.clear(reports)
	table.clear(startingUnlocks)
	for _, id in UnlockService.getUnlocked() do
		startingUnlocks[id] = true
	end
	player:SetAttribute("BotRunning", true)
	startRun(1)
end

function PlaytestBotService.isRunning(): boolean
	return running
end

function PlaytestBotService:start()
	closeCards = Remotes.get("CloseCards")
	runReport = Remotes.get("RunReport")

	task.spawn(function()
		while true do
			task.wait(PICK_EVERY_SECONDS)
			if running then
				pickCard()
			end
		end
	end)

	-- The run's result is the player's "RunState" attribute (RunManager). RunReportService
	-- builds the report when it changes, so read it a moment later.
	local function watch(player: Player)
		player:GetAttributeChangedSignal("RunState"):Connect(function()
			local state = player:GetAttribute("RunState")
			if running and (state == "Lost" or state == "Won") then
				task.delay(0.5, onRunOver)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

return PlaytestBotService
