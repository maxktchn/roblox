--!strict
-- The player's ingredients and the stat bonuses they give (PRD §3.3). The ONE place stats are computed.
--
-- This module requires only config, never another service. That lets every service
-- (WeaponService, RunManager, UpgradeService...) require it without circular requires.
--
-- How to use a stat: percent stats are fractions, so the final value is base * (1 + bonus).
--   damage = baseDamage * (1 + StatsService.getStat("Damage"))
-- Flat stats (Armor) are added as-is:  hit = rawDamage - StatsService.getStat("Armor")

--
-- Owned levels are also copied onto the player as "Ingredient_<id>" attributes for the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ingredients = require(ReplicatedStorage.Config.Ingredients)

local StatsService = {}

-- Ingredient id -> level (1 to 5). Missing = not owned.
local ingredientLevels: { [string]: number } = {}

-- Copy owned ingredient levels onto the run's player (nil = not owned).
local function syncAttributes()
	local player = Players:GetPlayers()[1]
	if player then
		for id in Ingredients do
			player:SetAttribute(`Ingredient_{id}`, ingredientLevels[id])
		end
	end
end

-- Set an ingredient's level (UpgradeService calls this when a card is taken, #16).
-- Level 0 removes it.
function StatsService.setIngredientLevel(ingredientId: string, level: number)
	assert(Ingredients[ingredientId], `Unknown ingredient "{ingredientId}"`)
	if level > 0 then
		ingredientLevels[ingredientId] = level
	else
		ingredientLevels[ingredientId] = nil
	end
	syncAttributes()
end

-- Current level of an ingredient, or nil if the player doesn't own it.
function StatsService.getIngredientLevel(ingredientId: string): number?
	return ingredientLevels[ingredientId]
end

-- Total bonus for one stat from every owned ingredient. 0 when none give it.
-- Examples: Hot Sauce Lv 2 -> getStat("Damage") == 0.2; Beef Jerky Lv 2 -> getStat("Armor") == 2.
function StatsService.getStat(stat: Ingredients.Stat): number
	local total = 0
	for ingredientId, level in ingredientLevels do
		local ingredient = Ingredients[ingredientId]
		if ingredient.Stat == stat then
			total += ingredient.PerLevel * level
		end
	end
	return total
end

-- Forget everything (start of a new run).
function StatsService.reset()
	table.clear(ingredientLevels)
	syncAttributes()
end

function StatsService:start()
	Players.PlayerAdded:Connect(syncAttributes)
end

return StatsService
