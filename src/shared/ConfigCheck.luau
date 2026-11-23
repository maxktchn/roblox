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
local Gear = require(Config.Gear)
local Ingredients = require(Config.Ingredients)
local Recipes = require(Config.Recipes)
local RunRewards = require(Config.RunRewards)
local RunRules = require(Config.RunRules)
local Saving = require(Config.Saving)
local Starters = require(Config.Starters)
local Talents = require(Config.Talents)
local WeaponTypes = require(ReplicatedStorage.Shared.WeaponTypes)

local ConfigCheck = {}

-- The numbers each gear item's Epic and Legendary effect must have (GearEffectsService and
-- WeaponService use them; #107 builds the Frying Pan's and Rolling Pin's).
local GEAR_EFFECT_NUMBERS: { [string]: { string } } = {
	ChefsKnife = { "Every" },
	ChefsHat = { "FreePicks" },
	Apron = { "BlockEverySeconds" },
	OvenMitts = { "Chance", "BurnDps", "BurnSeconds" },
	Shoes = { "SpeedBoost", "BoostSeconds", "SafeSeconds" },
	FryingPan = { "StunSeconds" },
	RollingPin = { "Slow", "SlowSeconds", "DamageTakenBonus" },
}

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
				elseif weapon.Shape == "Lob" then (stats.Count or 0) > 0 and (stats.Radius or 0) > 0
				elseif weapon.Shape == "Trail" then (stats.Width or 0) > 0
					and (stats.Seconds or 0) > 0
					and (stats.Slow or 0) >= 0
					and (stats.Slow or 0) < 1
					and stats.Cooldown > 0
				elseif weapon.Shape == "Bounce" then (stats.Count or 0) > 0
					and (stats.Speed or 0) > 0
					and (stats.Bounces or -1) >= 0
					and (stats.BounceRange or 0) > 0
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
			if stats.Pierce and stats.Pierce < 1 then
				fail(`Weapon {id} Lv {i}: Pierce must be 1 or more`)
			end
			if stats.PierceFalloff and (stats.PierceFalloff < 0 or stats.PierceFalloff >= 1) then
				fail(`Weapon {id} Lv {i}: PierceFalloff must be from 0 up to (not including) 1`)
			end
			if (stats.Spread and stats.Spread <= 0) or (stats.Freeze and stats.Freeze <= 0) then
				fail(`Weapon {id} Lv {i}: Spread and Freeze must be more than 0`)
			end
			if weapon.Shape == "Projectile" and stats.Slow and (stats.Slow <= 0 or stats.Slow >= 1) then
				fail(`Weapon {id} Lv {i}: Slow must be between 0 and 1`)
			end
			local slick = stats.Slick
			if slick and (slick.Width <= 0 or slick.Seconds <= 0 or slick.Slow <= 0 or slick.Slow >= 1) then
				fail(`Weapon {id} Lv {i}: Slick needs Width and Seconds above 0 and Slow between 0 and 1`)
			end
			if weapon.Shape == "Projectile" and stats.Width and stats.Width <= 0 then
				fail(`Weapon {id} Lv {i}: Width must be more than 0`)
			end
			if (stats.FullDamageRange == nil) ~= (stats.MinDamageScale == nil) then
				fail(`Weapon {id} Lv {i}: FullDamageRange and MinDamageScale go together`)
			elseif
				stats.FullDamageRange
				and stats.MinDamageScale
				and (
					stats.FullDamageRange < 0
					or stats.FullDamageRange >= stats.Range
					or stats.MinDamageScale <= 0
					or stats.MinDamageScale > 1
				)
			then
				fail(`Weapon {id} Lv {i}: FullDamageRange must be under Range, MinDamageScale above 0 up to 1`)
			end
			if stats.Knockback and stats.Knockback <= 0 then
				fail(`Weapon {id} Lv {i}: Knockback must be more than 0`)
			end
			local flatten = stats.Flatten
			if flatten and (flatten.Seconds <= 0 or flatten.DamageBonus < 0) then
				fail(`Weapon {id} Lv {i}: Flatten needs Seconds above 0 and DamageBonus 0 or more`)
			end
			local fire = stats.FireArc
			if fire and (fire.Splats < 1 or fire.Width <= 0 or fire.Seconds <= 0 or fire.Damage <= 0) then
				fail(`Weapon {id} Lv {i}: FireArc needs Splats 1 or more and Width, Seconds, Damage above 0`)
			end
			local cluster = stats.Cluster
			if
				cluster and (cluster.Count < 1 or cluster.Distance <= 0 or cluster.Damage <= 0 or cluster.Radius <= 0)
			then
				fail(`Weapon {id} Lv {i}: Cluster needs Count 1 or more and Distance, Damage, Radius above 0`)
			end
		end
	end

	if not Starters[RunRules.Starter] then
		fail(`RunRules.Starter: unknown starter "{RunRules.Starter}"`)
	end
	-- Unlock rules (#151): exactly the "Achievement" starters have one, and it makes sense.
	for id, starter in Starters do
		local rule = starter.UnlockRule
		if (starter.Unlock == "Achievement") ~= (rule ~= nil) then
			fail(`Starter {id}: an UnlockRule goes with Unlock = "Achievement" (and only then)`)
		elseif rule and rule.Kind == "ClearChapter" and not (rule.Chapter and Chapters[rule.Chapter]) then
			fail(`Starter {id}: UnlockRule needs a Chapter from Chapters.luau`)
		elseif rule and rule.Kind == "Kills" and not (rule.Count and rule.Count > 0) then
			fail(`Starter {id}: UnlockRule needs a Count above 0`)
		end
	end
	-- Every MVP starter must be playable (the Utensil slot can hold any of them, #107).
	for id, starter in Starters do
		if starter.Mvp or starter.Levels then
			checkWeapon(id, starter, RunRules.StarterMaxLevel)
		end
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
		local starter = Starters[recipe.Weapon]
		local weaponReachable = (starter ~= nil and starter.Levels ~= nil)
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
		elseif weapon.Shape ~= "Arc" and weapon.Shape ~= "Projectile" then
			fail(`Weapon {id}: Aimed needs a shape with a direction (Arc or Projectile)`)
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
		local trail = boss.Trail
		if trail then
			if not boss.Body then
				fail(`Boss {id}: has a Trail but no Body`)
			end
			for _, field in { "Spacing", "Seconds", "Width", "Damage", "HitCooldown" } do
				if (trail :: any)[field] <= 0 then
					fail(`Boss {id}: Trail.{field} must be more than 0`)
				end
			end
		end
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
			if fight.LaserReverseAt <= 0 or fight.LaserReverseAt >= 1 then
				fail(`Boss {id}: LaserReverseAt must be between 0 and 1 (a fraction of the live time)`)
			end
			if fight.LaserReverseTell < 0 then
				fail(`Boss {id}: LaserReverseTell must be 0 or more`)
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
		if enemy.Movement == "KeepAway" then
			local keep = enemy.KeepAway
			if not keep then
				fail(`Enemy {id}: "KeepAway" movement needs KeepAway`)
			elseif keep.Min <= 0 or keep.Max <= keep.Min then
				fail(`Enemy {id}: KeepAway needs 0 < Min < Max`)
			end
		end
		local shot = enemy.Shot
		if shot then
			for _, field in { "Every", "Windup", "Swell", "Speed", "Damage", "Range", "Size" } do
				if (shot :: any)[field] <= 0 then
					fail(`Enemy {id}: Shot.{field} must be more than 0`)
				end
			end
			if shot.FirstDelay < 0 then
				fail(`Enemy {id}: Shot.FirstDelay can't be negative`)
			end
		end
		if enemy.IsElite then
			fail(`Enemy {id}: IsElite is set by EnemyService, not in Enemies.luau`)
		end
		if enemy.SlowTaken and (enemy.SlowTaken < 0 or enemy.SlowTaken > 1) then
			fail(`Enemy {id}: SlowTaken must be 0 to 1`)
		end
		if enemy.CanBeElite and enemy.GroupSize and enemy.GroupSize > 1 then
			fail(`Enemy {id}: enemies that spawn in groups can't be elites`)
		end
		local puddle = enemy.DeathPuddle
		if puddle then
			if puddle.Width <= 0 or puddle.Seconds <= 0 then
				fail(`Enemy {id}: DeathPuddle Width and Seconds must be more than 0`)
			end
			if puddle.Slow <= 0 or puddle.Slow >= 1 then
				fail(`Enemy {id}: DeathPuddle.Slow must be between 0 and 1`)
			end
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
	-- No loops (A splits into B, B into A): the fight would never end. Follow each enemy's
	-- chain of SplitInto; reaching an enemy already in the chain is a loop.
	for id in Enemies do
		local seen: { [string]: boolean } = {}
		local current: string? = id
		while current and Enemies[current] do
			if seen[current] then
				fail(`{id}: SplitInto goes round in a loop (back to "{current}")`)
				break
			end
			seen[current] = true
			current = Enemies[current].SplitInto
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
		if chapter.Elites then
			local last = -1
			for _, seconds in chapter.Elites do
				if seconds <= last or seconds < 0 or seconds >= RunRules.RunLengthSeconds then
					fail(`Chapter {id}: Elites times must be in order and inside the run`)
					break
				end
				last = seconds
			end
		end
		if chapter.Rushes then
			local lastEnd = -math.huge
			for index, rush in chapter.Rushes do
				if rush.Seconds <= 0 or rush.SpawnScale <= 0 or rush.Warning < 0 then
					fail(`Chapter {id}: rush {index} needs Seconds and SpawnScale above 0, Warning 0 or more`)
				end
				if rush.At - rush.Warning < lastEnd or rush.At + rush.Seconds > RunRules.RunLengthSeconds then
					fail(`Chapter {id}: rush {index} overlaps another or runs past the end of the run`)
				end
				lastEnd = rush.At + rush.Seconds
			end
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

	-- Saving (P2-1, #102): the save slot names the DataStore, so it can't be empty.
	if Saving.SaveSlot == "" then
		fail("Saving.SaveSlot must be a non-empty string")
	end
	-- ProfileStore takes over a save still held by a crashed server after 40 s (its SESSION_STEAL);
	-- giving up before that would leave the player unable to save for about 10 minutes.
	if Saving.LoadTimeoutSeconds <= 40 then
		fail("Saving.LoadTimeoutSeconds must be more than 40 (ProfileStore's session take-over)")
	end

	-- Gear (P2-4, #105).
	for id, item in Gear.Items do
		if not Gear.Slots[item.Slot] then
			fail(`Gear item {id}: unknown slot "{item.Slot}"`)
		end
		if item.Slot == "Utensil" and not Starters[id] then
			fail(`Gear item {id}: Utensil items must be starter ids`)
		elseif item.Slot ~= "Utensil" and not item.Name then
			fail(`Gear item {id}: needs a Name`)
		end
		if not (item.Effect and item.Effect.Epic and item.Effect.Legendary) then
			fail(`Gear item {id}: needs Effect.Epic and Effect.Legendary`)
		elseif type(item.Effect.Epic.Text) ~= "string" or type(item.Effect.Legendary.Text) ~= "string" then
			fail(`Gear item {id}: each effect needs a Text for players`)
		else
			-- The numbers the bonus effects use: a missing one would break the run every frame.
			local fields: { string } = GEAR_EFFECT_NUMBERS[id] or {}
			for _, field in fields do
				for _, rarity in { "Epic", "Legendary" } do
					local value = (item.Effect :: any)[rarity][field]
					if type(value) ~= "number" or value < 0 then
						fail(`Gear item {id}: Effect.{rarity}.{field} must be a number, 0 or more`)
					end
				end
			end
			if id == "ChefsKnife" and (item.Effect.Epic.Every < 1 or item.Effect.Legendary.Every < 1) then
				fail("Gear item ChefsKnife: Effect Every must be at least 1")
			end
		end
	end
	for _, stat in { "Attack", "Hp" } do
		local previousMax: number? = nil
		for _, rarity in Gear.Rarities do
			local range = (Gear.Stats :: any)[stat][rarity.Id]
			if not range then
				fail(`Gear.Stats.{stat} has no {rarity.Id}`)
				continue
			end
			if range.First >= range.Max then
				fail(`Gear.Stats.{stat}.{rarity.Id}: First must be below Max`)
			end
			-- Merging resets to Lv 1, so Lv 1 of a rarity must beat the rarity below at max level.
			if previousMax and range.First <= previousMax then
				fail(`Gear.Stats.{stat}.{rarity.Id}: First must be above the previous rarity's Max`)
			end
			previousMax = range.Max
		end
		for _, rarity in Gear.Rarities do
			if not Gear.SalvageGold[rarity.Id] then
				fail(`Gear.SalvageGold has no {rarity.Id}`)
			end
		end
	end
	local cost = Gear.LevelCost
	if cost.Gold <= 0 or cost.Material <= 0 or cost.Growth < 1 then
		fail("Gear.LevelCost: Gold and Material must be above 0, Growth at least 1")
	end

	-- Basic Chests (P2-7d, #164).
	local basic = Gear.Chests.Basic
	if basic.Price <= 0 or basic.BulkCount < 2 or basic.BulkCount ~= math.floor(basic.BulkCount) then
		fail("Gear.Chests.Basic: Price must be above 0, BulkCount a whole number of at least 2")
	end
	if basic.StarterDropChance < 0 or basic.StarterDropChance >= 1 then
		fail("Gear.Chests.Basic.StarterDropChance must be 0 or more and below 1")
	end
	local oddsTotal = 0
	local rarityIds = {}
	for _, rarity in Gear.Rarities do
		rarityIds[rarity.Id] = true
	end
	for rarityId, chance in basic.Rarities do
		if not rarityIds[rarityId] then
			fail(`Gear.Chests.Basic.Rarities: unknown rarity {rarityId}`)
		elseif chance <= 0 then
			fail(`Gear.Chests.Basic.Rarities.{rarityId} must be above 0`)
		end
		oddsTotal += chance
	end
	if math.abs(oddsTotal - 1) > 1e-6 then
		fail(`Gear.Chests.Basic.Rarities must add up to 1 (they add up to {oddsTotal})`)
	end

	-- Account levels (P2-7a, #161).
	if Talents.MaxLevel < 2 or Talents.MaxLevel ~= math.floor(Talents.MaxLevel) then
		fail("Talents.MaxLevel must be a whole number of at least 2")
	end
	if Talents.Xp.Base <= 0 or Talents.Xp.Step < 0 then
		fail("Talents.Xp: Base must be above 0, Step 0 or more")
	end

	-- The talent path (P2-7b, #162): every level 1 to MaxLevel has a node, specials sit on
	-- multiples of SpecialEvery, and every amount is above 0.
	if Talents.Cost.Base <= 0 or Talents.Cost.Step < 0 then
		fail("Talents.Cost: Base must be above 0, Step 0 or more")
	end
	if Talents.SpecialEvery < 1 or Talents.SpecialEvery % 1 ~= 0 then
		fail("Talents.SpecialEvery must be a whole number of at least 1")
	end
	local talentKinds = {
		Attack = "standard",
		MaxHp = "standard",
		Armor = "standard",
		PieHealing = "standard",
		Reroll = "special",
		StartingPie = "special",
		FreePick = "special",
		PickupRange = "special",
		MoveSpeed = "special",
	}
	local function checkTalentNode(where: string, node: any, group: string)
		if talentKinds[node.Kind] ~= group then
			fail(`{where}: Kind "{node.Kind}" isn't a {group} talent kind`)
		end
		if type(node.Amount) ~= "number" or node.Amount <= 0 then
			fail(`{where}: Amount must be above 0`)
		end
		if type(node.Text) ~= "string" or node.Text == "" then
			fail(`{where}: needs a Text for players`)
		end
	end
	if #Talents.StandardCycle == 0 then
		fail("Talents.StandardCycle needs at least one entry")
	end
	for i, node in Talents.StandardCycle do
		checkTalentNode(`Talents.StandardCycle[{i}]`, node, "standard")
	end
	for number, node in Talents.Specials do
		if number % Talents.SpecialEvery ~= 0 or number < 1 or number > Talents.MaxLevel then
			fail(`Talents.Specials[{number}] must be on a multiple of SpecialEvery, 1 to MaxLevel`)
		end
		checkTalentNode(`Talents.Specials[{number}]`, node, "special")
	end
	for number = Talents.SpecialEvery, Talents.MaxLevel, math.max(Talents.SpecialEvery, 1) do
		if not Talents.Specials[number] then
			fail(`Talents.Specials has no node for level {number}`)
		end
	end

	-- Run rewards (P2-5, #106).
	for _, name in { "GoldPerMinute", "XpPerMinute", "MaterialDropsPerMinute", "MinMaterialDrops" } do
		local value = (RunRewards :: any)[name]
		if type(value) ~= "number" or value < 0 then
			fail(`RunRewards.{name} must be a number, 0 or more`)
		end
	end
	for _, name in { "Gold", "Xp", "MaterialDrops" } do
		local value = (RunRewards.ClearBonus :: any)[name]
		if type(value) ~= "number" or value < 0 then
			fail(`RunRewards.ClearBonus.{name} must be a number, 0 or more`)
		end
	end
	for id, chapter in Chapters do
		if type(chapter.RewardScale) ~= "number" or chapter.RewardScale <= 0 then
			fail(`Chapter {id}: RewardScale must be a number above 0`)
		end
		local reward = chapter.FirstClearReward
		if reward and not Gear.Items[reward.Item] then
			fail(`Chapter {id}: FirstClearReward has unknown gear item "{reward.Item}"`)
		elseif reward and not rarityIds[reward.Rarity] then
			fail(`Chapter {id}: FirstClearReward has unknown rarity "{reward.Rarity}"`)
		end
	end

	return problems
end

return ConfigCheck
