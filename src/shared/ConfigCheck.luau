--!strict
-- Catches broken references between config modules (typo'd ids, missing recipe parts).
-- The server runs this at boot; it returns a list of problems (empty = all good).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Config
local Bosses = require(Config.Bosses)
local Chapters = require(Config.Chapters)
local Enemies = require(Config.Enemies)
local Gadgets = require(Config.Gadgets)
local Ingredients = require(Config.Ingredients)
local Recipes = require(Config.Recipes)
local RunRules = require(Config.RunRules)
local Starters = require(Config.Starters)
local WeaponTypes = require(ReplicatedStorage.Shared.WeaponTypes)

local ConfigCheck = {}

function ConfigCheck.run(): { string }
	local problems: { string } = {}
	local function fail(message: string)
		table.insert(problems, message)
	end

	local recipeFor: { [string]: string } = {}
	for id, recipe in Recipes do
		if not (Starters[recipe.Weapon] or Gadgets[recipe.Weapon]) then
			fail(`Recipe {id}: unknown weapon "{recipe.Weapon}"`)
		end
		if not Ingredients[recipe.Ingredient] then
			fail(`Recipe {id}: unknown ingredient "{recipe.Ingredient}"`)
		end
		if recipeFor[recipe.Weapon] then
			fail(`Weapon {recipe.Weapon} has two recipes: {recipeFor[recipe.Weapon]} and {id}`)
		end
		recipeFor[recipe.Weapon] = id
	end

	for id in Starters do
		if not recipeFor[id] then
			fail(`Starter {id} has no recipe`)
		end
		if Gadgets[id] then
			fail(`{id} is both a starter and a gadget`)
		end
	end
	for id in Gadgets do
		if not recipeFor[id] then
			fail(`Gadget {id} has no recipe`)
		end
	end

	-- A playable weapon needs a Shape, the right number of Levels, and the fields its shape uses.
	type Weapon = { Shape: WeaponTypes.Shape?, Levels: { WeaponTypes.WeaponLevel }? }
	local function checkWeapon(id: string, weapon: Weapon, maxLevel: number)
		if not weapon.Shape or not weapon.Levels then
			fail(`Weapon {id}: needs Shape and Levels to be playable`)
			return
		end
		if #weapon.Levels ~= maxLevel then
			fail(`Weapon {id}: has {#weapon.Levels} levels, needs {maxLevel}`)
		end
		for i, stats in weapon.Levels do
			local needs = if weapon.Shape == "Arc"
				then stats.ArcDegrees
				elseif weapon.Shape == "Orbit" or weapon.Shape == "Projectile" then stats.Count and stats.Speed
				else true
			if not needs then
				fail(`Weapon {id} Lv {i}: missing a field its {weapon.Shape} shape needs`)
			end
			if (stats.BurnDps == nil) ~= (stats.BurnSeconds == nil) then
				fail(`Weapon {id} Lv {i}: BurnDps and BurnSeconds go together`)
			end
		end
	end

	local runStarter = Starters[RunRules.Starter]
	if not runStarter then
		fail(`RunRules.Starter: unknown starter "{RunRules.Starter}"`)
	else
		checkWeapon(RunRules.Starter, runStarter, RunRules.StarterMaxLevel)
	end

	for _, id in RunRules.UpgradePool.Gadgets do
		if not Gadgets[id] then
			fail(`RunRules.UpgradePool: unknown gadget "{id}"`)
		else
			checkWeapon(id, Gadgets[id], RunRules.SharedItemMaxLevel)
		end
	end
	for _, id in RunRules.UpgradePool.Ingredients do
		if not Ingredients[id] then
			fail(`RunRules.UpgradePool: unknown ingredient "{id}"`)
		end
	end

	for id, chapter in Chapters do
		if not Bosses[chapter.FinalBoss] then
			fail(`Chapter {id}: unknown final boss "{chapter.FinalBoss}"`)
		end
		if chapter.MiniBoss and not Bosses[chapter.MiniBoss] then
			fail(`Chapter {id}: unknown mini-boss "{chapter.MiniBoss}"`)
		end
		if chapter.Timeline then
			for _, phase in chapter.Timeline do
				for _, enemyId in phase.Enemies do
					if not Enemies[enemyId] then
						fail(`Chapter {id}: unknown enemy "{enemyId}"`)
					end
				end
			end
		end
	end

	return problems
end

return ConfigCheck
