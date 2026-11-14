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
-- Not done here yet: ChooseCard/RequestReroll remotes and rerolls (#18), recipe cards (#20).

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
			table.insert(pool, {
				Kind = "Gadget",
				Id = id,
				Name = Gadgets[id].Name,
				FromLevel = from,
				ToLevel = from + 1,
				-- Gadget level numbers come in #19; until then upgrades just say "Level up".
				Description = if from == 0 then Gadgets[id].Behavior else "Level up",
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

-- If a level-up is waiting and nothing is on screen, draw and send the next offer.
local function offerNext()
	if currentOffer or pendingLevelUps == 0 then
		return
	end
	local player = Players:GetPlayers()[1]
	if not player then
		return -- no one to show it to yet; tried again on the next tip or choice
	end
	pendingLevelUps -= 1
	local cards = drawCards()
	currentOffer = cards
	offerCards:FireClient(player, cards)
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

-- Take card number `index` (1 to 3) from the current offer. Returns true if it was applied.
-- The ChooseCard remote (#18) validates the player's input and then calls this.
function UpgradeService.chooseCard(index: number): boolean
	local offer = currentOffer
	local card = offer and offer[index]
	if not card then
		return false
	end
	applyCard(card)
	currentOffer = nil
	offerNext()
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
end

function UpgradeService:init() end

function UpgradeService:start()
	offerCards = Remotes.get("OfferCards")
end

return UpgradeService
