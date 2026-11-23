--!strict
-- The player's ingredients and the stat bonuses they give (PRD §3.3). The ONE place stats are computed.
--
-- This module requires only config, never another service. That lets every service
-- (WeaponService, RunManager, UpgradeService...) require it without circular requires.
--
-- How to use a stat: percent stats are fractions, so the final value is base * (1 + bonus).
-- Damage and max HP also include gear (P2-4), so use the multipliers for those:
--   damage = baseDamage * StatsService.getDamageMultiplier()
--   maxHp  = RunRules.ChefMaxHp * StatsService.getMaxHpMultiplier()
-- Flat stats (Armor) are added as-is:  hit = rawDamage - StatsService.getStat("Armor")
--
-- Talents (P2-7b #162) are set when a run starts, like gear: Attack and MaxHp add to gear's %
-- totals, and Armor, PickupRange and MoveSpeed are included in getStat (on top of ingredients).
-- Pie healing is getPieHealMultiplier().
--
-- The chef's walk speed is set here too, and only here (#117): base RunRules.ChefWalkSpeed,
-- plus Butter's MoveSpeed bonus, times any slow (a Rotten Tomato puddle, PuddleService).

--
-- Owned levels are also copied onto the player as "Ingredient_<id>" attributes for the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ingredients = require(ReplicatedStorage.Config.Ingredients)
local RunRules = require(ReplicatedStorage.Config.RunRules)

local StatsService = {}

-- Ingredient id -> level (1 to 5). Missing = not owned.
local ingredientLevels: { [string]: number } = {}
-- How much slower the chef walks right now (0 = full speed, 0.4 = 40% slower).
local slow = 0
-- This run's gear bonuses (GearService sets them when a run starts, P2-4). Gear is its own
-- multiplier on top of ingredients, so a gear upgrade isn't watered down by Hot Sauce or Bread.
local gearAttack = 0
local gearHp = 0
-- This run's talent bonuses (TalentService sets them when a run starts, #162).
local talentAttack = 0
local talentHp = 0
local talentStats: { [string]: number } = {} -- Armor, PickupRange, MoveSpeed
local talentPieHealing = 0
-- A short burst of extra walk speed (0.3 = 30% faster; the Shoes' bonus effect after a hit).
local speedBoost = 0

-- Copy owned ingredient levels onto the run's player (nil = not owned).
local function syncAttributes()
	local player = Players:GetPlayers()[1]
	if player then
		for id in Ingredients do
			player:SetAttribute(`Ingredient_{id}`, ingredientLevels[id])
		end
	end
end

-- Forward declaration: the chef's speed depends on getStat, defined below.
local applyWalkSpeed: () -> ()

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
	applyWalkSpeed()
end

-- Current level of an ingredient, or nil if the player doesn't own it.
function StatsService.getIngredientLevel(ingredientId: string): number?
	return ingredientLevels[ingredientId]
end

-- Total bonus for one stat from every owned ingredient. 0 when none give it.
-- Examples: Hot Sauce Lv 2 -> getStat("Damage") == 0.12; Beef Jerky Lv 2 -> getStat("Armor") == 2.
function StatsService.getStat(stat: Ingredients.Stat): number
	local total = talentStats[stat] or 0
	for ingredientId, level in ingredientLevels do
		local ingredient = Ingredients[ingredientId]
		if ingredient.Stat == stat then
			total += ingredient.PerLevel * level
		end
	end
	return total
end

-- Set this run's gear bonuses (0.28 = +28%). GearService calls this when a run starts; reset()
-- leaves them alone.
function StatsService.setGearBonuses(attack: number, hp: number)
	gearAttack = attack
	gearHp = hp
end

-- Set this run's talent bonuses (TalentService, when a run starts; reset() leaves them alone).
-- Fractions except Armor (flat): { Attack = 0.12, MaxHp = 0.18, Armor = 3, PieHealing = 0.3,
-- PickupRange = 0.1, MoveSpeed = 0.05 }.
function StatsService.setTalentBonuses(bonuses: {
	Attack: number,
	MaxHp: number,
	Armor: number,
	PieHealing: number,
	PickupRange: number,
	MoveSpeed: number,
})
	talentAttack = bonuses.Attack
	talentHp = bonuses.MaxHp
	talentPieHealing = bonuses.PieHealing
	talentStats = { Armor = bonuses.Armor, PickupRange = bonuses.PickupRange, MoveSpeed = bonuses.MoveSpeed }
	applyWalkSpeed()
end

-- Everything that multiplies the chef's damage: gear and talent Attack, then ingredients (Hot Sauce).
function StatsService.getDamageMultiplier(): number
	return (1 + gearAttack + talentAttack) * (1 + StatsService.getStat("Damage"))
end

-- Everything that multiplies the chef's max HP: gear and talent HP, then ingredients (Bread).
function StatsService.getMaxHpMultiplier(): number
	return (1 + gearHp + talentHp) * (1 + StatsService.getStat("MaxHp"))
end

-- How much more a pie heals than RunRules.PieHealFraction (talents: 1.3 = 30% more).
function StatsService.getPieHealMultiplier(): number
	return 1 + talentPieHealing
end

-- The chef's walk speed right now, in studs per second.
function StatsService.getWalkSpeed(): number
	return RunRules.ChefWalkSpeed * (1 + StatsService.getStat("MoveSpeed")) * (1 + speedBoost) * (1 - slow)
end

-- Make the chef walk `fraction` faster (0.3 = 30%), or 0 to stop (GearEffectsService, Shoes).
function StatsService.setSpeedBoost(fraction: number)
	fraction = math.max(fraction, 0)
	if fraction ~= speedBoost then
		speedBoost = fraction
		applyWalkSpeed()
	end
end

-- Slow the chef down by `fraction` (0.4 = 40% slower), or 0 for full speed. Slows don't
-- stack: the latest call wins (PuddleService, #117).
function StatsService.setSlow(fraction: number)
	fraction = math.clamp(fraction, 0, 0.95)
	if fraction ~= slow then
		slow = fraction
		applyWalkSpeed()
	end
end

-- Copy the walk speed onto the chef's Humanoid (it replicates to the client, which moves the chef).
function applyWalkSpeed()
	local player = Players:GetPlayers()[1]
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = StatsService.getWalkSpeed()
	end
end

-- Forget everything (start of a new run).
function StatsService.reset()
	table.clear(ingredientLevels)
	slow = 0
	speedBoost = 0
	syncAttributes()
	applyWalkSpeed()
end

local function watchPlayer(player: Player)
	syncAttributes()
	-- A new chef (joining, or "Play again") gets the right speed too.
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Humanoid", 10)
		applyWalkSpeed()
	end)
	applyWalkSpeed()
end

function StatsService:start()
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
end

return StatsService
