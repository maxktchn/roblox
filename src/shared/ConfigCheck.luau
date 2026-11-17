--!strict
-- Catches broken references between config modules (typo'd ids, missing recipe parts).
-- The server runs this at boot; it returns a list of problems (empty = all good).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Config
local BossPowers = require(Config.BossPowers)
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
				elseif weapon.Shape == "Pulse" then (stats.Speed or 0) > 0 and stats.Range > 0
				else true
			if not needs then
				fail(`Weapon {id} Lv {i}: missing a field its {weapon.Shape} shape needs`)
			end
			if (stats.BurnDps == nil) ~= (stats.BurnSeconds == nil) then
				fail(`Weapon {id} Lv {i}: BurnDps and BurnSeconds go together`)
			end
			if stats.PullStrength and stats.PullStrength <= 0 then
				fail(`Weapon {id} Lv {i}: PullStrength must be more than 0`)
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

	-- Every recipe the current pool can reach must be playable (one level of numbers).
	for id, recipe in Recipes do
		local weaponReachable = recipe.Weapon == RunRules.Starter
			or table.find(RunRules.UpgradePool.Gadgets, recipe.Weapon) ~= nil
		local ingredientReachable = table.find(RunRules.UpgradePool.Ingredients, recipe.Ingredient) ~= nil
		if weaponReachable and ingredientReachable then
			checkWeapon(id, recipe, 1)
		end
	end

	-- Boss powers (PRD §3.8): every one in the pool must be playable at all 5 levels, and
	-- each boss's Power and each power's Boss must point at each other.
	for _, id in RunRules.UpgradePool.BossPowers do
		local power = BossPowers[id]
		if not power then
			fail(`RunRules.UpgradePool: unknown boss power "{id}"`)
		else
			checkWeapon(id, power, RunRules.SharedItemMaxLevel)
		end
	end
	for id, power in BossPowers do
		local boss = Bosses[power.Boss]
		if not boss then
			fail(`Boss power {id}: unknown boss "{power.Boss}"`)
		elseif boss.Power ~= id then
			fail(`Boss power {id}: boss {power.Boss} has Power "{boss.Power}", not "{id}"`)
		end
		if Gadgets[id] or Starters[id] or Recipes[id] then
			fail(`{id} is both a boss power and another weapon`)
		end
	end
	-- Aimed (PRD §2.2): only starters and starters' recipes, and only shapes with a direction.
	local function checkAimed(id: string, weapon: any, allowed: boolean)
		if not weapon.Aimed then
			return
		end
		if not allowed then
			fail(`Weapon {id}: Aimed is only for starters and their recipes`)
		elseif weapon.Shape ~= "Arc" then
			fail(`Weapon {id}: Aimed needs a shape with a direction (Arc)`)
		end
	end
	for id, starter in Starters do
		checkAimed(id, starter, true)
	end
	for id, gadget in Gadgets do
		checkAimed(id, gadget, false)
	end
	for id, recipe in Recipes do
		checkAimed(id, recipe, Starters[recipe.Weapon] ~= nil)
	end
	for id, power in BossPowers do
		checkAimed(id, power, false)
	end
	-- AimAtNearest: Arc weapons only, and not together with Aimed (one or the other picks the way).
	local function checkAimAtNearest(id: string, weapon: any)
		if weapon.AimAtNearest and (weapon.Shape ~= "Arc" or weapon.Aimed) then
			fail(`Weapon {id}: AimAtNearest is only for Arc weapons that aren't Aimed`)
		end
	end
	for id, gadget in Gadgets do
		checkAimAtNearest(id, gadget)
	end
	for id, recipe in Recipes do
		checkAimAtNearest(id, recipe)
	end
	if RunRules.AimMessagesPerSecond <= 0 then
		fail(`RunRules.AimMessagesPerSecond must be more than 0`)
	end

	if RunRules.BossPowerNewCardChance < 0 or RunRules.BossPowerNewCardChance > 1 then
		fail(`RunRules.BossPowerNewCardChance must be between 0 and 1`)
	end

	for id, boss in Bosses do
		if boss.Power and not BossPowers[boss.Power] then
			fail(`Boss {id}: unknown Power "{boss.Power}"`)
		end
		if boss.Fight and not Enemies[boss.Fight.SummonEnemy] then
			fail(`Boss {id}: unknown SummonEnemy "{boss.Fight.SummonEnemy}"`)
		end
		if boss.Fight and not boss.Body then
			fail(`Boss {id}: has a Fight but no Body`)
		end
		local fight = boss.Fight
		if fight then
			if fight.Phase2At <= 0 or fight.Phase2At >= 1 then
				fail(`Boss {id}: Phase2At must be between 0 and 1 (a fraction of max HP)`)
			end
			if fight.LaserWarning < 0 or fight.LaserWarning >= fight.LaserSeconds then
				fail(`Boss {id}: LaserWarning must be 0 or more and shorter than LaserSeconds`)
			end
			if fight.LaserCount ~= math.floor(fight.LaserCount) then
				fail(`Boss {id}: LaserCount must be a whole number`)
			end
			if not Enemies[fight.PopcornEnemy] then
				fail(`Boss {id}: unknown PopcornEnemy "{fight.PopcornEnemy}"`)
			end
			for _, field in
				{
					"PhaseChangeSeconds",
					"LaserWalkSpeed",
					"LaserSeconds",
					"WalkingSeconds",
					"PopcornEvery",
					"PopcornWarning",
					"PopcornSeconds",
					"PopWarning",
					"PopRadius",
					"PopDamage",
					"LaserCount",
					"LaserTurnSpeed",
					"LaserWidth",
					"LaserDamage",
					"LaserHitCooldown",
				}
			do
				if (fight :: any)[field] <= 0 then
					fail(`Boss {id}: {field} must be more than 0`)
				end
			end
		end
		if boss.Body and Enemies[id] then
			fail(`{id} is both a boss and an enemy`)
		end
	end

	for id, enemy in Enemies do
		if enemy.PieDropChance and (enemy.PieDropChance < 0 or enemy.PieDropChance > 1) then
			fail(`Enemy {id}: PieDropChance must be between 0 and 1`)
		end
	end

	-- Splits (The Big Cheese, #84): normal enemies and boss bodies alike.
	local function checkSplit(id: string, enemy: Enemies.Enemy)
		if not enemy.SplitInto then
			return
		end
		if not Enemies[enemy.SplitInto] then
			fail(`{id}: unknown SplitInto "{enemy.SplitInto}"`)
		end
		local count = enemy.SplitCount
		if not (count and count >= 1 and count == math.floor(count)) then
			fail(`{id}: SplitCount must be a whole number of 1 or more`)
		end
	end
	for id, enemy in Enemies do
		checkSplit(id, enemy)
	end
	for id, boss in Bosses do
		if boss.Body then
			checkSplit(id, boss.Body)
		end
	end

	for _, id in RunRules.EnemyPool do
		if not Enemies[id] then
			fail(`RunRules.EnemyPool: unknown enemy "{id}"`)
		end
	end

	for id, chapter in Chapters do
		if not Bosses[chapter.FinalBoss] then
			fail(`Chapter {id}: unknown final boss "{chapter.FinalBoss}"`)
		end
		if chapter.MiniBoss and not Bosses[chapter.MiniBoss] then
			fail(`Chapter {id}: unknown mini-boss "{chapter.MiniBoss}"`)
		elseif chapter.MiniBoss and not Bosses[chapter.MiniBoss].Body then
			fail(`Chapter {id}: mini-boss "{chapter.MiniBoss}" has no Body`)
		end
		if chapter.Timeline then
			-- Phases must run back to back from 0:00 to the end of the shift, with no gaps.
			local expectedFrom = 0
			for index, phase in chapter.Timeline do
				for _, enemyId in phase.Enemies do
					if not Enemies[enemyId] then
						fail(`Chapter {id}: unknown enemy "{enemyId}"`)
					end
				end
				if phase.From ~= expectedFrom then
					fail(`Chapter {id}: phase {index} starts at {phase.From}, expected {expectedFrom}`)
				end
				if phase.To <= phase.From then
					fail(`Chapter {id}: phase {index} ends before it starts`)
				end
				if phase.SpawnsPerSecond < 0 then
					fail(`Chapter {id}: phase {index} has a negative SpawnsPerSecond`)
				end
				expectedFrom = phase.To
			end
			if #chapter.Timeline > 0 and expectedFrom ~= RunRules.RunLengthSeconds then
				fail(`Chapter {id}: timeline ends at {expectedFrom}, RunLengthSeconds is {RunRules.RunLengthSeconds}`)
			end
		end
	end

	return problems
end

return ConfigCheck
