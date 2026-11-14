--!strict
-- Tips/XP, "Order Up!" card draws, rerolls, recipe cards, loadout limits (PRD §2.3 to §2.5). Validates every ChooseCard against the cards it offered.
--
-- Flow: addTips fills the tip bar -> each full bar is one pending level-up ->
-- one at a time, draw 3 cards and send them with OfferCards -> the player picks ->
-- chooseCard applies it -> the next pending level-up (if any) is offered.
--
-- Who owns what (so there is one source of truth for each thing):
--   weapon levels (starter + gadgets) -> WeaponService
--   ingredient levels                 -> StatsService
--   tips, level, the current offer    -> here
-- Not done here yet: recipe cards (#20).
--
-- Security (PRD §8.4): the client only ever sends ChooseCard(index) and RequestReroll().
-- Both are checked below; anything unexpected is ignored, never trusted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Card = require(ReplicatedStorage.Shared.Card)
local Gadgets = require(ReplicatedStorage.Config.Gadgets)
local Ingredients = require(ReplicatedStorage.Config.Ingredients)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)
local Starters = require(ReplicatedStorage.Config.Starters)
local StatsService = require(script.Parent.StatsService)
local WeaponService = require(script.Parent.WeaponService)

type Card = Card.Card

local UpgradeService = {}

local random = Random.new()

local tips = 0 -- tips in the current bar
local level = 1 -- the player's run level (starts at 1)
local pendingLevelUps = 0 -- full bars waiting for their "Order Up!"
local currentOffer: { Card }? = nil -- the cards on screen right now, or nil
local rerollsLeft = RunRules.RerollsPerRun -- rerolls the player can still use this run

local offerCards: RemoteEvent

-- Tips needed to go from `fromLevel` to the next level (5, 8, 11, ...).
local function tipsNeeded(fromLevel: number): number
	return RunRules.FirstLevelTips + RunRules.ExtraTipsPerLevel * (fromLevel - 1)
end

-- How config field names appear on cards. Fields not listed here show their own name.
local STAT_LABELS: { [string]: { name: string, unit: string } } = {
	Damage = { name = "Damage", unit = "" },
	Cooldown = { name = "Cooldown", unit = "s" },
	Range = { name = "Range", unit = "" },
	ArcDegrees = { name = "Arc", unit = "°" },
	Count = { name = "Amount", unit = "" },
	Speed = { name = "Speed", unit = "" },
	BurnDps = { name = "Burn", unit = "/s" },
	BurnSeconds = { name = "Burn time", unit = "s" },
}

-- One line saying what changes between two levels of a weapon, built from its config numbers.
-- Example: "Arc 90° → 100°, Cooldown 0.8s → 0.65s". Works for any weapon with number fields.
local function describeChange(before: { [string]: any }, after: { [string]: any }): string
	local keys = {}
	for key, value in after do
		if type(value) == "number" and before[key] ~= value then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	local parts = {}
	for _, key in keys do
		local label = STAT_LABELS[key] or { name = key, unit = "" }
		table.insert(parts, `{label.name} {before[key]}{label.unit} → {after[key]}{label.unit}`)
	end
	return if #parts > 0 then table.concat(parts, ", ") else "Level up"
end

-- How many of the 6 shared slots are used (owned gadgets + owned ingredients).
local function slotsUsed(): number
	local used = 0
	for _, id in RunRules.UpgradePool.Gadgets do
		if WeaponService.getWeaponLevel(id) then
			used += 1
		end
	end
	for _, id in RunRules.UpgradePool.Ingredients do
		if StatsService.getIngredientLevel(id) then
			used += 1
		end
	end
	return used
end

-- Every card that could be offered right now (PRD §2.3, §2.4).
local function buildPool(): { Card }
	local pool: { Card } = {}
	local slotsFree = slotsUsed() < RunRules.SharedSlots

	-- The starter is always owned; it can only be upgraded.
	local starter = Starters[RunRules.Starter]
	local starterLevel = WeaponService.getWeaponLevel(RunRules.Starter)
	if starterLevel and starterLevel < RunRules.StarterMaxLevel and starter.Levels then
		table.insert(pool, {
			Kind = "Starter",
			Id = RunRules.Starter,
			Name = starter.Name,
			FromLevel = starterLevel,
			ToLevel = starterLevel + 1,
			Description = describeChange(starter.Levels[starterLevel], starter.Levels[starterLevel + 1]),
		})
	end

	-- Gadgets: upgrade if owned and not maxed; new only if a shared slot is free.
	for _, id in RunRules.UpgradePool.Gadgets do
		local owned = WeaponService.getWeaponLevel(id)
		if (owned and owned < RunRules.SharedItemMaxLevel) or (not owned and slotsFree) then
			local from = owned or 0
			local gadgetLevels = Gadgets[id].Levels
			table.insert(pool, {
				Kind = "Gadget",
				Id = id,
				Name = Gadgets[id].Name,
				FromLevel = from,
				ToLevel = from + 1,
				-- NEW shows what it does; upgrades show what the numbers change to.
				Description = if from == 0 or not gadgetLevels
					then Gadgets[id].Behavior
					else describeChange(gadgetLevels[from], gadgetLevels[from + 1]),
			})
		end
	end

	-- Ingredients: same rules as gadgets.
	for _, id in RunRules.UpgradePool.Ingredients do
		local owned = StatsService.getIngredientLevel(id)
		if (owned and owned < RunRules.SharedItemMaxLevel) or (not owned and slotsFree) then
			local from = owned or 0
			table.insert(pool, {
				Kind = "Ingredient",
				Id = id,
				Name = Ingredients[id].Name,
				FromLevel = from,
				ToLevel = from + 1,
				Description = Ingredients[id].Description,
			})
		end
	end

	return pool
end

-- Pick up to CardsPerLevelUp different cards at random. If nothing is left, offer a Pie.
local function drawCards(): { Card }
	local pool = buildPool()
	-- Shuffle (Fisher-Yates), then take the first few.
	for i = #pool, 2, -1 do
		local j = random:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local cards: { Card } = {}
	for i = 1, math.min(RunRules.CardsPerLevelUp, #pool) do
		table.insert(cards, pool[i])
	end
	if #cards == 0 then
		table.insert(cards, {
			Kind = "Filler",
			Id = "Pie",
			Name = "Pie",
			FromLevel = 0,
			ToLevel = 0,
			Description = `Heal {math.round(RunRules.PieHealFraction * 100)}% HP`,
		})
	end
	return cards
end

-- The run's one player (PRD §8.1), or nil before they join.
local function getRunPlayer(): Player?
	return Players:GetPlayers()[1]
end

-- (Re)send the open offer to the client, so its screen shows exactly what the server has.
local function sendOffer()
	local player = getRunPlayer()
	if player and currentOffer then
		offerCards:FireClient(player, currentOffer, rerollsLeft)
	end
end

-- If a level-up is waiting and nothing is on screen, draw and send the next offer.
local function offerNext()
	if currentOffer or pendingLevelUps == 0 then
		return
	end
	if not getRunPlayer() then
		return -- no one to show it to yet; tried again on the next tip or choice
	end
	pendingLevelUps -= 1
	currentOffer = drawCards()
	RunManager.setPaused(true) -- the run stands still until a card is picked
	sendOffer()
end

-- Do what a card says.
local function applyCard(card: Card)
	if card.Kind == "Starter" or card.Kind == "Gadget" then
		WeaponService.setWeaponLevel(card.Id, card.ToLevel)
	elseif card.Kind == "Ingredient" then
		StatsService.setIngredientLevel(card.Id, card.ToLevel)
	elseif card.Id == "Pie" then
		RunManager.healPlayer(RunRules.PieHealFraction)
	end
end

-- Add tips (XP) when the player picks one up. Fills the tip bar and triggers "Order Up!".
function UpgradeService.addTips(amount: number)
	if amount <= 0 then
		return
	end
	tips += amount
	-- One pickup can fill several bars; each full bar is one level-up.
	while tips >= tipsNeeded(level) do
		tips -= tipsNeeded(level)
		level += 1
		pendingLevelUps += 1
	end
	offerNext()
end

-- Replace the open offer with a fresh draw, using up one reroll. Returns true if it worked.
function UpgradeService.reroll(): boolean
	if not currentOffer or rerollsLeft <= 0 then
		return false
	end
	rerollsLeft -= 1
	currentOffer = drawCards()
	sendOffer()
	return true
end

-- How many rerolls are left this run.
function UpgradeService.getRerollsLeft(): number
	return rerollsLeft
end

-- Take card number `index` (1 to 3) from the current offer. Returns true if it was applied.
-- The ChooseCard remote handler below validates the player's input before calling this.
function UpgradeService.chooseCard(index: number): boolean
	local offer = currentOffer
	local card = offer and offer[index]
	if not card then
		return false
	end
	applyCard(card)
	currentOffer = nil
	offerNext()
	if not currentOffer then
		RunManager.setPaused(false) -- no more cards waiting: back to the kitchen
	end
	return true
end

-- The cards on screen right now, or nil if no offer is open.
function UpgradeService.getCurrentOffer(): { Card }?
	return currentOffer
end

-- For the HUD (#21): current level, tips in this bar, tips needed to fill it.
function UpgradeService.getProgress(): (number, number, number)
	return level, tips, tipsNeeded(level)
end

-- Start a fresh run: level 1, empty bar, no offer.
function UpgradeService.reset()
	tips = 0
	level = 1
	pendingLevelUps = 0
	currentOffer = nil
	rerollsLeft = RunRules.RerollsPerRun
	RunManager.setPaused(false)
end

function UpgradeService:init() end

-- True if `value` is a whole number from 1 to `max`. Rejects strings, tables, nil,
-- 1.5, NaN (NaN is the only value not equal to itself) and infinity.
local function isCardIndex(value: unknown, max: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= max
end

function UpgradeService:start()
	offerCards = Remotes.get("OfferCards")

	-- ChooseCard(index): only from the run's player, only while an offer is open,
	-- only a whole number pointing at one of the offered cards.
	Remotes.get("ChooseCard").OnServerEvent:Connect(function(player: Player, index: unknown)
		if player ~= getRunPlayer() or not currentOffer then
			return -- not our player, or nothing to choose (e.g. a double tap): ignore
		end
		if isCardIndex(index, #currentOffer) then
			UpgradeService.chooseCard(index :: number)
		else
			-- Bad input while cards are open: the client already hid its screen,
			-- so send the same cards again rather than leave the player stuck.
			sendOffer()
		end
	end)

	-- RequestReroll(): no arguments are read. Works only with an offer open and rerolls left.
	Remotes.get("RequestReroll").OnServerEvent:Connect(function(player: Player)
		if player ~= getRunPlayer() or not currentOffer then
			return
		end
		if not UpgradeService.reroll() then
			sendOffer() -- no rerolls left: resend so the client's button shows the real count
		end
	end)
end

return UpgradeService
