--!strict
-- Fires the player's starter, gadgets and recipe weapons on cooldowns; applies ingredient stats. Server decides all damage (PRD §8.4).
--
-- Every weapon has a Shape in config (see Shared/WeaponTypes): Arc, Aura, Orbit, Projectile,
-- Pulse, Lob or Bounce.
-- There is one attack function per shape below, so new weapons are config-only (PRD §8.5).
--
-- Each frame, every owned weapon counts down its cooldown. At 0 it attacks: the server
-- finds the enemies it hits and damages them, then tells the client to draw the effect
-- (WeaponFx). The client never decides what was hit.
--
-- Owned weapon levels are also copied onto the player as attributes ("Weapon_<id>" = level),
-- so the client can draw always-on effects (orbiting forks) and the HUD can show icons (#21).
--
-- Aimed weapons (the starter and its recipe, `Aimed = true` in config) swing toward the
-- player's aim instead of the way the chef faces (PRD §2.2, #60). The client sends its aim on
-- the unreliable AimDirection remote; it's validated and rate-limited here, and only the
-- latest one is kept. The server still decides timing, reach and every hit.
--
-- Every hit is also recorded and sent to the client in small batches (HitFx), so it can
-- flash the enemy and float a damage number (#43). Visual only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossPowers = require(ReplicatedStorage.Config.BossPowers)
local EnemyService = require(script.Parent.EnemyService)
local Gadgets = require(ReplicatedStorage.Config.Gadgets)
local Recipes = require(ReplicatedStorage.Config.Recipes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)
local Starters = require(ReplicatedStorage.Config.Starters)
local StatsService = require(script.Parent.StatsService)
local WeaponTypes = require(ReplicatedStorage.Shared.WeaponTypes)

type WeaponLevel = WeaponTypes.WeaponLevel

local WeaponService = {}

-- Weapon id -> current level (1 to 5). The run starts with the starter at Lv 1.
local levels: { [string]: number } = {}
-- Weapon id -> seconds until it can attack again.
local cooldowns: { [string]: number } = {}

-- Burning enemies (Pepper Shaker). Enemy id -> burn state.
type Burn = { dps: number, timeLeft: number, tickTimer: number, weaponId: string }
local burns: { [number]: Burn } = {}

-- Orbit weapons: weapon id -> (enemy id -> time it can be hit again).
local orbitHitTimes: { [string]: { [number]: number } } = {}

-- Shots in flight (Toaster). The client draws its own copy of each one.
type Shot = {
	id: number,
	weaponId: string,
	position: Vector3,
	direction: Vector3,
	speed: number,
	traveled: number,
	maxDistance: number,
	damage: number,
}
local shots: { Shot } = {}
local lastShotId = 0

local kills = 0 -- enemies defeated this run (shown on the HUD)
-- Damage each weapon has actually dealt this run (overkill not counted), for the run report.
local damageByWeapon: { [string]: number } = {}

local weaponFx: RemoteEvent

-- The player's latest aim (flat unit vector), or nil until they aim in this run.
local aim: Vector3? = nil
local aimWindowStart = 0 -- start of the current one-second window for the rate limit
local aimMessagesInWindow = 0
local hitFx: RemoteEvent

-- Hit feedback (#43). Hits are collected here and sent together every HIT_FX_INTERVAL
-- seconds, instead of one message per hit, to keep network traffic low with a big swarm.
-- Past MAX_HIT_FX hits in one batch the rest are not shown (the damage still counts).
local HIT_FX_INTERVAL = 0.1
local MAX_HIT_FX = 30
-- One hit as the client sees it. Kind is "Hit", "Crit" or "Burn".
type HitFx = { part: BasePart, position: Vector3, amount: number, kind: string }
local pendingHits: { HitFx } = {}
local hitFxTimer = 0

-- The run's one player (PRD §8.1), or nil before they join.
local function getRunPlayer(): Player?
	return Players:GetPlayers()[1]
end

-- The chef's root part, or nil while there is no living chef.
local function getChef(): BasePart?
	local player = getRunPlayer()
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- A weapon's config entry, from Starters, Gadgets or Recipes.
local function getWeaponConfig(weaponId: string): (WeaponTypes.Shape?, { WeaponLevel }?)
	local config: any = Starters[weaponId] or Gadgets[weaponId] or Recipes[weaponId] or BossPowers[weaponId]
	if not config then
		return nil, nil
	end
	return config.Shape, config.Levels
end

-- Tell the client to draw an effect. Visual only.
local function sendFx(weaponId: string, ...: any)
	local player = getRunPlayer()
	if player then
		weaponFx:FireClient(player, weaponId, ...)
	end
end

-- Final damage for one hit: base damage + Hot Sauce bonus, and a crit roll (Salt, plus
-- the weapon's own CritBonus if it has one, e.g. Sushi Master Blade).
-- Rolled separately for every enemy hit, so a big swing can mix crits and normal hits.
-- Also returns whether it was a crit (crits show a bigger damage number).
local function rollDamage(baseDamage: number, critBonus: number?): (number, boolean)
	local damage = baseDamage * (1 + StatsService.getStat("Damage"))
	local isCrit = math.random() < StatsService.getStat("CritChance") + (critBonus or 0)
	if isCrit then
		damage *= RunRules.CritDamageMultiplier
	end
	return damage, isCrit
end

-- Damage one enemy and remember the hit for the client's hit feedback.
-- Every weapon hit goes through here. `kind` is "Hit", "Crit" or "Burn".
local function dealDamage(enemyId: number, amount: number, kind: string, weaponId: string)
	-- Read the part, position and HP before the damage: a killing hit parks the part.
	local part = EnemyService.getEnemyPart(enemyId)
	local position = EnemyService.getEnemyPosition(enemyId)
	local hpBefore = EnemyService.getEnemyHp(enemyId)
	amount *= 1 + EnemyService.getDamageTakenBonus(enemyId) -- frozen by Deep Freeze (#128)
	EnemyService.damage(enemyId, amount)
	if hpBefore then
		damageByWeapon[weaponId] = (damageByWeapon[weaponId] or 0) + math.min(amount, hpBefore)
	end
	if part and position and #pendingHits < MAX_HIT_FX then
		table.insert(pendingHits, { part = part, position = position, amount = amount, kind = kind })
	end
end

-- Damage one enemy with a crit roll.
local function dealRolledDamage(enemyId: number, baseDamage: number, critBonus: number?, weaponId: string)
	local damage, isCrit = rollDamage(baseDamage, critBonus)
	dealDamage(enemyId, damage, if isCrit then "Crit" else "Hit", weaponId)
end

-- Send the collected hits every HIT_FX_INTERVAL seconds.
local function flushHitFx(deltaTime: number)
	hitFxTimer -= deltaTime
	if hitFxTimer > 0 or #pendingHits == 0 then
		return
	end
	hitFxTimer = HIT_FX_INTERVAL
	local player = getRunPlayer()
	if player then
		hitFx:FireClient(player, pendingHits)
	end
	pendingHits = {}
end

-- Coffee (#127): every weapon's Cooldown is multiplied by this (Coffee's Cooldown stat is
-- negative: Lv 5 = -0.25, so x0.75). Starters, gadgets, recipes and boss powers alike; for an
-- Orbit it's the per-enemy re-hit time. Burns and slows aren't shortened.
local MIN_COOLDOWN_SCALE = 0.2
local function cooldownScale(): number
	return math.max(1 + StatsService.getStat("Cooldown"), MIN_COOLDOWN_SCALE)
end

-- Hit one enemy with a weapon: damage now, plus a burn if the weapon has one.
local function hit(enemyId: number, stats: WeaponLevel, weaponId: string)
	dealRolledDamage(enemyId, stats.Damage, stats.CritBonus, weaponId)
	if stats.BurnDps and stats.BurnSeconds and EnemyService.getEnemyPosition(enemyId) then
		local burn = burns[enemyId]
		if burn then
			-- Already burning: keep the stronger burn and restart the timer.
			if stats.BurnDps > burn.dps then
				burn.dps = stats.BurnDps
				burn.weaponId = weaponId
			end
			burn.timeLeft = stats.BurnSeconds
		else
			burns[enemyId] = {
				dps = stats.BurnDps,
				timeLeft = stats.BurnSeconds,
				tickTimer = RunRules.BurnTickSeconds,
				weaponId = weaponId,
			}
		end
	end
end

-- Flat distance (X and Z only) between two points, matching EnemyService.
local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Weapon reach is measured to an enemy's EDGE, not its center, so big enemies (the boss)
-- can be hit from outside touching distance (PRD §3.3). Half the widest enemy's width,
-- so the center-based EnemyService search can be widened just enough. Set in init.
local maxEnemyHalfWidth = 0

-- An enemy's config, or nil if it is dead.
local function enemyConfig(enemyId: number): any
	local enemyType = EnemyService.getEnemyType(enemyId)
	return enemyType and EnemyService.getConfigForType(enemyType)
end

-- Centre to front face (0 if it is dead): reach is measured to this (EnemyService.getHalfDepth).
local function enemyHalfDepth(enemyId: number): number
	local config = enemyConfig(enemyId)
	return if config then EnemyService.getHalfDepth(config) else 0
end

-- Centre to side (0 if it is dead): how far it sticks out sideways (EnemyService.getHalfWidth).
local function enemyHalfWidth(enemyId: number): number
	local config = enemyConfig(enemyId)
	return if config then EnemyService.getHalfWidth(config) else 0
end

-- How far `point` is from an enemy's edge (flat). Negative = inside the enemy.
local function distanceToEdge(enemyId: number, enemyPosition: Vector3, point: Vector3): number
	return flatDistance(enemyPosition, point) - enemyHalfDepth(enemyId)
end

-- Every enemy whose edge is within `reach` studs of `origin`.
local function getEnemiesInReach(origin: Vector3, reach: number): { number }
	local found = {}
	for _, enemyId in EnemyService.getEnemiesInRadius(origin, reach + maxEnemyHalfWidth) do
		local position = EnemyService.getEnemyPosition(enemyId)
		if position and distanceToEdge(enemyId, position, origin) <= reach then
			table.insert(found, enemyId)
		end
	end
	return found
end

-- How far past its Range an AimAtNearest weapon looks for a target, so it turns toward an
-- enemy that is about to step into reach instead of spraying at nothing.
local NEAREST_SEARCH_EXTRA = 4

-- Which way a weapon attacks:
--   * Aimed weapons (the starter): the player's aim, once they've aimed.
--   * AimAtNearest weapons (Pepper Shaker): the nearest enemy, if one is close.
--   * Otherwise the way the chef faces, flattened so looking up or down doesn't matter.
local function getAttackDirection(weaponId: string, root: BasePart, range: number): Vector3
	local config: any = Starters[weaponId] or Gadgets[weaponId] or Recipes[weaponId]
	if config and config.Aimed and aim then
		return aim
	end
	if config and config.AimAtNearest then
		local nearestDirection: Vector3? = nil
		local nearestDistance = math.huge
		for _, enemyId in getEnemiesInReach(root.Position, range + NEAREST_SEARCH_EXTRA) do
			local position = EnemyService.getEnemyPosition(enemyId)
			if position then
				local offset = Vector3.new(position.X - root.Position.X, 0, position.Z - root.Position.Z)
				local distance = offset.Magnitude
				if distance > 0.01 and distance < nearestDistance then
					nearestDistance = distance
					nearestDirection = offset.Unit
				end
			end
		end
		if nearestDirection then
			return nearestDirection
		end
	end
	local look = root.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

-- ARC: hit every enemy inside a slice of circle in front of the chef.
-- An Arc swing that is still sweeping (RunRules.SlashSeconds). Enemies that step into the arc
-- while the blade is drawn are hit too, once each, so what looks slashed is slashed.
type Swing = {
	weaponId: string,
	stats: WeaponLevel,
	facing: Vector3, -- fixed when the swing starts; the arc moves with the chef like the drawing
	timeLeft: number,
	alreadyHit: { [number]: boolean },
}
local swings: { Swing } = {}

-- Hit every enemy whose body is inside this swing's arc around `origin` that it hasn't hit yet.
local function checkSwing(swing: Swing, origin: Vector3)
	local stats = swing.stats
	local halfArc = math.rad((stats.ArcDegrees or 90) / 2)
	for _, enemyId in getEnemiesInReach(origin, stats.Range) do
		local position = EnemyService.getEnemyPosition(enemyId)
		if position and not swing.alreadyHit[enemyId] then
			local offset = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
			local distance = offset.Magnitude
			-- Inside the swing if ANY part of its body is: the angle to its centre may be past the
			-- edge of the arc by as much as its half width covers at that distance. (Checking only
			-- the centre missed enemies the drawn blade visibly passed over.)
			-- An enemy overlapping the chef counts as hit whatever its direction.
			local overlapping = distance <= enemyHalfDepth(enemyId)
			local angle = math.acos(math.clamp(swing.facing:Dot(offset / math.max(distance, 0.01)), -1, 1))
			local bodyAngle = math.asin(math.min(enemyHalfWidth(enemyId) / math.max(distance, 0.01), 1))
			if overlapping or angle <= halfArc + bodyAngle then
				swing.alreadyHit[enemyId] = true
				hit(enemyId, stats, swing.weaponId)
			end
		end
	end
end

local function attackArc(weaponId: string, stats: WeaponLevel, root: BasePart)
	-- The aim (starter), the nearest enemy (Pepper Shaker), or the way the chef faces.
	local facing = getAttackDirection(weaponId, root, stats.Range)
	local swing: Swing = {
		weaponId = weaponId,
		stats = stats,
		facing = facing,
		timeLeft = RunRules.SlashSeconds,
		alreadyHit = {},
	}
	checkSwing(swing, root.Position) -- everything already in the arc is hit straight away
	table.insert(swings, swing)
	sendFx(weaponId, facing, stats.Range, stats.ArcDegrees or 90)
end

-- Every frame: keep live swings hitting enemies that walk into them, until the sweep ends.
local function updateSwings(deltaTime: number, root: BasePart)
	-- Walk backwards so removing a finished swing doesn't skip the next one.
	for i = #swings, 1, -1 do
		local swing = swings[i]
		swing.timeLeft -= deltaTime
		if swing.timeLeft <= 0 then
			table.remove(swings, i)
		else
			checkSwing(swing, root.Position)
		end
	end
end

-- AURA: hit every enemy in a circle around the chef.
local function attackAura(weaponId: string, stats: WeaponLevel, root: BasePart)
	for _, enemyId in getEnemiesInReach(root.Position, stats.Range) do
		hit(enemyId, stats, weaponId)
	end
	sendFx(weaponId, stats.Range)
end

-- The enemies within `range` of `origin`, nearest edge first.
type Target = { id: number, position: Vector3, distance: number }
local function getNearestTargets(origin: Vector3, range: number): { Target }
	local targets: { Target } = {}
	for _, enemyId in getEnemiesInReach(origin, range) do
		local position = EnemyService.getEnemyPosition(enemyId)
		if position then
			table.insert(
				targets,
				{ id = enemyId, position = position, distance = distanceToEdge(enemyId, position, origin) }
			)
		end
	end
	table.sort(targets, function(a, b)
		return a.distance < b.distance
	end)
	return targets
end

-- PROJECTILE: fire one shot at each of the nearest `Count` enemies in range.
local function attackProjectile(weaponId: string, stats: WeaponLevel, root: BasePart)
	local origin = root.Position
	local targets = getNearestTargets(origin, stats.Range)
	for i = 1, math.min(stats.Count or 1, #targets) do
		local toTarget = targets[i].position - origin
		if toTarget.Magnitude > 0.01 then
			lastShotId += 1
			local shot: Shot = {
				id = lastShotId,
				weaponId = weaponId,
				position = origin,
				direction = toTarget.Unit,
				speed = stats.Speed or 40,
				traveled = 0,
				maxDistance = stats.Range,
				damage = stats.Damage,
			}
			table.insert(shots, shot)
			sendFx(weaponId, "Launch", shot.id, origin, shot.direction, shot.speed, shot.maxDistance)
		end
	end
end

-- Move every shot; a shot hits the first enemy it comes close to, or ends at max distance.
local function updateShots(deltaTime: number)
	-- Walk backwards so removing a shot doesn't skip the next one.
	for i = #shots, 1, -1 do
		local shot = shots[i]
		local step = shot.speed * deltaTime
		shot.position += shot.direction * step
		shot.traveled += step

		local targets = getEnemiesInReach(shot.position, RunRules.ProjectileHitRadius)
		local target = targets[1]
		if target then
			dealRolledDamage(target, shot.damage, nil, shot.weaponId)
		end
		if target or shot.traveled >= shot.maxDistance then
			table.remove(shots, i)
			sendFx(shot.weaponId, "End", shot.id)
		end
	end
end

-- LOB (Egg Grenade, #129): eggs in the air. Each lands where it was aimed and splashes.
type Egg = {
	weaponId: string,
	stats: WeaponLevel,
	target: Vector3, -- where it lands (flat position of the enemy when thrown)
	timeLeft: number,
	damage: number,
	radius: number,
	cluster: boolean, -- true = a full egg that pops mini-eggs (Breakfast Bomb); false = a mini-egg
}
local eggs: { Egg } = {}

local function throwEgg(egg: Egg, from: Vector3)
	table.insert(eggs, egg)
	sendFx(egg.weaponId, "Lob", from, egg.target, egg.timeLeft, egg.radius)
end

-- Lob one egg at each of the nearest `Count` enemies in range.
local function attackLob(weaponId: string, stats: WeaponLevel, root: BasePart)
	local origin = root.Position
	local targets = getNearestTargets(origin, stats.Range)
	for i = 1, math.min(stats.Count or 1, #targets) do
		throwEgg({
			weaponId = weaponId,
			stats = stats,
			target = targets[i].position,
			timeLeft = RunRules.LobFlightSeconds,
			damage = stats.Damage,
			radius = stats.Radius or 4,
			cluster = stats.Cluster ~= nil,
		}, origin)
	end
end

-- Every frame: land the eggs whose time is up. A landing egg hits every enemy whose edge is
-- within its radius (crits and Hot Sauce as usual, no burn); a full Breakfast Bomb egg then
-- throws its mini-eggs out from where it landed.
local function updateEggs(deltaTime: number)
	for i = #eggs, 1, -1 do
		local egg = eggs[i]
		egg.timeLeft -= deltaTime
		if egg.timeLeft <= 0 then
			table.remove(eggs, i)
			local splash: WeaponLevel =
				{ Damage = egg.damage, Cooldown = 0, Range = 0, CritBonus = egg.stats.CritBonus }
			for _, enemyId in getEnemiesInReach(egg.target, egg.radius) do
				hit(enemyId, splash, egg.weaponId)
			end
			local cluster = egg.stats.Cluster
			if egg.cluster and cluster then
				for k = 0, cluster.Count - 1 do
					local angle = k * 2 * math.pi / cluster.Count
					local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * cluster.Distance
					throwEgg({
						weaponId = egg.weaponId,
						stats = egg.stats,
						target = egg.target + offset,
						timeLeft = RunRules.LobClusterSeconds,
						damage = cluster.Damage,
						radius = cluster.Radius,
						cluster = false,
					}, egg.target)
				end
			end
		end
	end
end

-- BOUNCE (Pizza Cutter, #130): discs in flight. A disc flies at its target enemy (following
-- it), hits it, then flies on to the nearest enemy nobody in its throw has hit yet within
-- BounceRange, until it runs out of bounces or enemies. The client follows the same target.
type Disc = {
	id: number,
	weaponId: string,
	stats: WeaponLevel,
	position: Vector3,
	target: number, -- enemy id it's flying at
	bouncesLeft: number,
	alreadyHit: { [number]: boolean }, -- shared by every disc of one throw
	age: number,
}
local discs: { Disc } = {}
local lastDiscId = 0
local DISC_MAX_SECONDS = 6 -- a disc that somehow never arrives is dropped after this long

-- The nearest enemy whose edge is within BounceRange of the disc that its throw hasn't hit.
local function nextDiscTarget(disc: Disc): number?
	local best, bestDistance = nil, math.huge
	for _, enemyId in getEnemiesInReach(disc.position, disc.stats.BounceRange or 0) do
		local position = EnemyService.getEnemyPosition(enemyId)
		if position and not disc.alreadyHit[enemyId] then
			local distance = distanceToEdge(enemyId, position, disc.position)
			if distance < bestDistance then
				best, bestDistance = enemyId, distance
			end
		end
	end
	return best
end

-- Tell the client where a disc is and which enemy (part) it's flying at now.
local function sendDiscLeg(disc: Disc)
	sendFx(disc.weaponId, "Disc", disc.id, disc.position, EnemyService.getEnemyPart(disc.target), disc.stats.Speed)
end

local function endDisc(index: number)
	local disc = table.remove(discs, index)
	if disc then
		sendFx(disc.weaponId, "End", disc.id)
	end
end

-- Throw `Count` discs at the nearest different enemies in range.
local function attackBounce(weaponId: string, stats: WeaponLevel, root: BasePart)
	local targets = getNearestTargets(root.Position, stats.Range)
	local alreadyHit = {}
	for i = 1, math.min(stats.Count or 1, #targets) do
		lastDiscId += 1
		local disc: Disc = {
			id = lastDiscId,
			weaponId = weaponId,
			stats = stats,
			position = root.Position,
			target = targets[i].id,
			bouncesLeft = stats.Bounces or 0,
			alreadyHit = alreadyHit,
			age = 0,
		}
		table.insert(discs, disc)
		sendDiscLeg(disc)
	end
end

local function updateDiscs(deltaTime: number)
	for i = #discs, 1, -1 do
		local disc = discs[i]
		disc.age += deltaTime
		local targetPosition = EnemyService.getEnemyPosition(disc.target)
		if disc.alreadyHit[disc.target] or not targetPosition then
			-- Its target died, or another disc of the same throw got there first: pick another
			-- (this doesn't use up a bounce).
			local nextTarget = nextDiscTarget(disc)
			if not nextTarget or disc.age > DISC_MAX_SECONDS then
				endDisc(i)
				continue
			end
			disc.target = nextTarget
			sendDiscLeg(disc)
			targetPosition = EnemyService.getEnemyPosition(nextTarget)
		end
		if not targetPosition then
			endDisc(i)
			continue
		end
		local toTarget = Vector3.new(targetPosition.X - disc.position.X, 0, targetPosition.Z - disc.position.Z)
		local step = (disc.stats.Speed or 40) * deltaTime
		if toTarget.Magnitude > step then
			disc.position += toTarget.Unit * step
		else
			disc.position = Vector3.new(targetPosition.X, disc.position.Y, targetPosition.Z)
		end
		if distanceToEdge(disc.target, targetPosition, disc.position) <= RunRules.ProjectileHitRadius then
			disc.alreadyHit[disc.target] = true
			hit(disc.target, disc.stats, disc.weaponId)
			local nextTarget = if disc.bouncesLeft > 0 then nextDiscTarget(disc) else nil
			if nextTarget then
				disc.bouncesLeft -= 1
				disc.target = nextTarget
				sendDiscLeg(disc)
			else
				endDisc(i)
			end
		elseif disc.age > DISC_MAX_SECONDS then
			endDisc(i)
		end
	end
end

-- ORBIT: `Count` objects circle the chef. Their angle comes from the shared server clock,
-- so the client can draw them in the same spots without any messages (see WeaponFxController).
local function updateOrbit(weaponId: string, stats: WeaponLevel, root: BasePart)
	local count = stats.Count or 1
	local now = workspace:GetServerTimeNow()
	local hitTimes = orbitHitTimes[weaponId]
	if not hitTimes then
		hitTimes = {}
		orbitHitTimes[weaponId] = hitTimes
	end

	-- Only enemies near the circle can be touched, so check those.
	local nearby = getEnemiesInReach(root.Position, stats.Range + RunRules.OrbitHitRadius)
	for i = 0, count - 1 do
		local angle = math.rad(now * (stats.Speed or 180) + i * 360 / count)
		local forkPosition = root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * stats.Range
		for _, enemyId in nearby do
			local position = EnemyService.getEnemyPosition(enemyId)
			local readyAt = hitTimes[enemyId] or 0
			if
				position
				and now >= readyAt
				and distanceToEdge(enemyId, position, forkPosition) <= RunRules.OrbitHitRadius
			then
				hit(enemyId, stats, weaponId)
				hitTimes[enemyId] = now + stats.Cooldown * cooldownScale() -- one fork hit per enemy per Cooldown
			end
		end
	end

	-- Forget enemies that can be hit again (also drops dead ones), so the table stays small.
	for enemyId, readyAt in hitTimes do
		if now >= readyAt then
			hitTimes[enemyId] = nil
		end
	end
end

-- Burn damage ticks.
local function updateBurns(deltaTime: number)
	for enemyId, burn in burns do
		if not EnemyService.getEnemyPosition(enemyId) then
			burns[enemyId] = nil -- enemy died
			continue
		end
		burn.timeLeft -= deltaTime
		burn.tickTimer -= deltaTime
		if burn.tickTimer <= 0 then
			burn.tickTimer += RunRules.BurnTickSeconds
			-- Burns get Hot Sauce but can't crit.
			local damage = burn.dps * RunRules.BurnTickSeconds * (1 + StatsService.getStat("Damage"))
			dealDamage(enemyId, damage, "Burn", burn.weaponId)
		end
		if burn.timeLeft <= 0 then
			burns[enemyId] = nil
		end
	end
end

-- PULL (PullStrength weapons; none in Phase 1 since Smoothie Vortex was removed, #83):
-- every frame, drag enemies within Range toward the chef.
local function updatePull(stats: WeaponLevel, root: BasePart, deltaTime: number)
	local studs = (stats.PullStrength or 0) * deltaTime
	for _, enemyId in getEnemiesInReach(root.Position, stats.Range) do
		EnemyService.pull(enemyId, root.Position, studs)
	end
end

-- PULSE (Microwave Pulse, a boss power): a ring that grows from where it was fired.
type Pulse = {
	weaponId: string,
	origin: Vector3, -- where the chef stood when it fired; the ring doesn't follow them
	radius: number, -- how far the ring has grown so far
	stats: WeaponLevel,
	alreadyHit: { [number]: boolean }, -- each enemy is hit at most once per pulse
}
local pulses: { Pulse } = {}

local function attackPulse(weaponId: string, stats: WeaponLevel, root: BasePart)
	table.insert(pulses, { weaponId = weaponId, origin = root.Position, radius = 0, stats = stats, alreadyHit = {} })
	sendFx(weaponId, root.Position, stats.Range, stats.Speed or 30)
end

-- Every frame: grow each ring; every enemy whose edge it reaches is hit once and knocked back.
local function updatePulses(deltaTime: number)
	-- Walk backwards so removing a finished pulse doesn't skip the next one.
	for i = #pulses, 1, -1 do
		local pulse = pulses[i]
		local stats = pulse.stats
		pulse.radius = math.min(pulse.radius + (stats.Speed or 30) * deltaTime, stats.Range)
		for _, enemyId in getEnemiesInReach(pulse.origin, pulse.radius) do
			if not pulse.alreadyHit[enemyId] then
				pulse.alreadyHit[enemyId] = true
				hit(enemyId, stats, pulse.weaponId)
				EnemyService.push(enemyId, pulse.origin, stats.Knockback or 0)
			end
		end
		if pulse.radius >= stats.Range then
			table.remove(pulses, i)
		end
	end
end

-- Shapes that attack on a cooldown. (Orbit is always on, so it's handled separately.)
local ATTACKS: { [string]: (string, WeaponLevel, BasePart) -> () } = {
	Arc = attackArc,
	Aura = attackAura,
	Projectile = attackProjectile,
	Pulse = attackPulse,
	Lob = attackLob,
	Bounce = attackBounce,
}

local function update(deltaTime: number)
	if RunManager.isPaused() then
		return -- "Order Up!" is on screen: cooldowns, shots and burns all freeze
	end
	updateShots(deltaTime)
	updateEggs(deltaTime)
	updateDiscs(deltaTime)
	updatePulses(deltaTime)
	updateBurns(deltaTime)
	flushHitFx(deltaTime)

	local root = getChef()
	if not root then
		return -- no living chef: weapons wait
	end
	updateSwings(deltaTime, root)
	for weaponId, level in levels do
		local shape, weaponLevels = getWeaponConfig(weaponId)
		local stats = weaponLevels and weaponLevels[level]
		if not (shape and stats) then
			continue -- not playable yet (no numbers in config)
		end
		if stats.PullStrength then
			updatePull(stats, root, deltaTime) -- always on, as well as its normal attack
		end
		if shape == "Orbit" then
			updateOrbit(weaponId, stats, root) -- always on, no cooldown to wait for
			continue
		end
		cooldowns[weaponId] = (cooldowns[weaponId] or 0) - deltaTime
		if cooldowns[weaponId] <= 0 then
			ATTACKS[shape](weaponId, stats, root)
			cooldowns[weaponId] = stats.Cooldown * cooldownScale()
		end
	end
end

-- Copy owned weapon levels onto the player as "Weapon_<id>" attributes (nil = not owned).
local function syncAttributes()
	local player = getRunPlayer()
	if not player then
		return
	end
	for id in Starters do
		player:SetAttribute(`Weapon_{id}`, levels[id])
	end
	for id in Gadgets do
		player:SetAttribute(`Weapon_{id}`, levels[id])
	end
	for id in Recipes do
		player:SetAttribute(`Weapon_{id}`, levels[id])
	end
	for id in BossPowers do
		player:SetAttribute(`Weapon_{id}`, levels[id])
	end
end

-- Set a weapon's level (UpgradeService calls this when a card is taken).
function WeaponService.setWeaponLevel(weaponId: string, level: number)
	levels[weaponId] = level
	syncAttributes()
end

-- Swap one weapon for another in the same slot (a recipe replacing its weapon, PRD §2.5).
-- The new weapon starts at Lv 1 and attacks straight away.
function WeaponService.replaceWeapon(oldId: string, newId: string)
	levels[oldId] = nil
	cooldowns[oldId] = nil
	orbitHitTimes[oldId] = nil
	levels[newId] = 1
	syncAttributes()
end

-- Every owned weapon id -> level. A copy, so changing it changes nothing here.
function WeaponService.getOwnedWeapons(): { [string]: number }
	return table.clone(levels)
end

-- Forget all weapons and give back the starter at Lv 1 (start of a new run).
function WeaponService.reset()
	table.clear(levels)
	table.clear(cooldowns)
	table.clear(burns)
	table.clear(orbitHitTimes)
	for _, shot in shots do
		sendFx(shot.weaponId, "End", shot.id)
	end
	table.clear(shots)
	table.clear(eggs)
	for _, disc in discs do
		sendFx(disc.weaponId, "End", disc.id)
	end
	table.clear(discs)
	table.clear(pulses)
	table.clear(swings)
	table.clear(pendingHits)
	table.clear(damageByWeapon)
	aim = nil -- a new run: the knife uses facing until the player aims again
	levels[RunRules.Starter] = 1
	kills = 0
	local player = getRunPlayer()
	if player then
		player:SetAttribute("Kills", 0)
	end
	syncAttributes()
end

-- Damage each weapon has dealt this run (weapon id -> damage), for the run report.
function WeaponService.getDamageByWeapon(): { [string]: number }
	return table.clone(damageByWeapon)
end

-- The player's latest validated aim direction, or nil before they aim (for tests).
function WeaponService.getAim(): Vector3?
	return aim
end

-- Current level of a weapon, or nil if the player doesn't own it.
function WeaponService.getWeaponLevel(weaponId: string): number?
	return levels[weaponId]
end

function WeaponService:init()
	maxEnemyHalfWidth = EnemyService.getMaxEnemyWidth() / 2
	table.clear(levels)
	levels[RunRules.Starter] = 1
end

function WeaponService:start()
	weaponFx = Remotes.get("WeaponFx")
	hitFx = Remotes.get("HitFx")
	syncAttributes()
	Players.PlayerAdded:Connect(syncAttributes)
	RunService.Heartbeat:Connect(update)

	-- AimDirection(x, z): only from the run's player, at most AimMessagesPerSecond a second,
	-- and only a real flat direction (numbers, not NaN or infinite, not zero length).
	-- Anything else is ignored and the previous aim stays.
	Remotes.getUnreliable("AimDirection").OnServerEvent:Connect(function(player: Player, x: unknown, z: unknown)
		if player ~= getRunPlayer() then
			return
		end
		local now = os.clock()
		if now - aimWindowStart >= 1 then
			aimWindowStart = now
			aimMessagesInWindow = 0
		end
		aimMessagesInWindow += 1
		if aimMessagesInWindow > RunRules.AimMessagesPerSecond then
			return -- too many this second
		end
		if type(x) ~= "number" or type(z) ~= "number" then
			return
		end
		local direction = Vector3.new(x, 0, z)
		local length = direction.Magnitude
		-- NaN is the only value not equal to itself; huge values make the length infinite.
		if length ~= length or length == math.huge or length < 0.01 then
			return
		end
		aim = direction / length
	end)

	-- No jumping (PRD §2.2): it does nothing in this game, and on phones the right thumb aims.
	local function noJump(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.UseJumpPower = false
			humanoid.JumpHeight = 0
			humanoid.JumpPower = 0
		end
	end
	local function watchPlayer(player: Player)
		if player.Character then
			task.spawn(noJump, player.Character)
		end
		player.CharacterAdded:Connect(noJump)
	end
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	-- Kill count for the HUD, as the player's "Kills" attribute. Counted here because this
	-- service already listens to EnemyService (RunManager can't: EnemyService requires it).
	EnemyService.onEnemyKilled(function()
		kills += 1
		local player = getRunPlayer()
		if player then
			player:SetAttribute("Kills", kills)
		end
	end)
end

return WeaponService
