--!strict
-- Spawns, moves and pools enemies as data + simple parts, never Humanoids. Bulk-moves with workspace:BulkMoveTo, distance-check hits, alive cap from RunRules (PRD §8.3).
--
-- Public functions below are the agreed interface between the two tracks (issue #4).
-- Each run server has exactly one player (PRD §8.1), so no function takes a player.
--
-- How it works:
--   * Every live enemy is a record in the `alive` table (id -> record). The record is the
--     truth (HP, position); the part in Workspace is only what the player sees.
--   * Parts are never destroyed during a run. A dead enemy's part is parked under the map
--     and put back in its type's pool; the next spawn of that type reuses it.
--   * Hits are plain distance checks against the records, not physics touches.
--   * Every frame each record's position is updated by its config's Movement, then every
--     part is moved at once with a single workspace:BulkMoveTo call.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bosses = require(ReplicatedStorage.Config.Bosses)
local Enemies = require(ReplicatedStorage.Config.Enemies)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)

local EnemyService = {}

-- Every live enemy has a number id. Ids are not reused while the enemy is alive.
export type EnemyId = number

-- Called once per defeated enemy: its id, its config id (e.g. "MoldyBread") and where it died.
export type KilledCallback = (enemyId: EnemyId, enemyType: string, position: Vector3) -> ()

type EnemyRecord = {
	id: EnemyId,
	enemyType: string,
	config: Enemies.Enemy,
	part: BasePart,
	hp: number,
	maxHp: number, -- HP it spawned with (after run-time scaling)
	damage: number, -- contact damage (after run-time scaling)
	position: Vector3,
	direction: Vector3, -- flat unit vector it is moving/facing along
}

-- Where unused parts wait: far below the floor, out of sight.
local PARK_CFRAME = CFrame.new(0, -200, 0)
-- Roughly how wide the chef is, so chasing enemies stop at the chef's edge instead of inside them.
local CHEF_RADIUS = 1.5

local killedCallbacks: { KilledCallback } = {}
local alive: { [EnemyId]: EnemyRecord } = {}
local aliveCount = 0
local lastId = 0
-- Enemy type -> parked parts ready to reuse.
local pools: { [string]: { BasePart } } = {}
local enemyFolder: Folder

-- What the spawner is allowed to create, and how fast. RunManager sets this (#6).
local spawnTypes: { string } = {}
local spawnsPerSecond = 0
local spawnBudget = 0 -- fractional spawns carried over between frames

-- Playable area from Workspace.Map's attributes (set when the map was built). nil = no limits.
local arenaCenter: Vector3? = nil
local arenaHalfSize: Vector3? = nil

-- During a boss fight, every enemy is also kept inside this circle (the ring of counters, #11).
local bossArenaCenter: Vector3? = nil
local bossArenaRadius = 0

local random = Random.new()

-- Reused every frame for BulkMoveTo, so moving the swarm doesn't create new tables each frame.
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

-- Separation grid: the floor is split into square cells, and each enemy only checks the
-- enemies in its own cell and the 8 around it, instead of all 150. Cells are as wide as
-- the widest enemy (set in init), so anything close enough to overlap is always in reach.
local cellSize = 4
local grid: { [number]: { EnemyRecord } } = {}

-- The chef's position, or nil while there is no chef.
local function getChefPosition(): Vector3?
	local player = Players:GetPlayers()[1]
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function isInsideArena(position: Vector3): boolean
	if not (arenaCenter and arenaHalfSize) then
		return true
	end
	local offset = position - arenaCenter
	return math.abs(offset.X) <= arenaHalfSize.X and math.abs(offset.Z) <= arenaHalfSize.Z
end

local function clampToArena(position: Vector3): Vector3
	local result = position
	if arenaCenter and arenaHalfSize then
		local x = math.clamp(result.X, arenaCenter.X - arenaHalfSize.X, arenaCenter.X + arenaHalfSize.X)
		local z = math.clamp(result.Z, arenaCenter.Z - arenaHalfSize.Z, arenaCenter.Z + arenaHalfSize.Z)
		result = Vector3.new(x, result.Y, z)
	end
	-- Boss fight: pull anything outside the ring back onto its edge.
	if bossArenaCenter then
		local offset = Vector3.new(result.X - bossArenaCenter.X, 0, result.Z - bossArenaCenter.Z)
		if offset.Magnitude > bossArenaRadius then
			local edge = bossArenaCenter + offset.Unit * bossArenaRadius
			result = Vector3.new(edge.X, result.Y, edge.Z)
		end
	end
	return result
end

-- A random point on the spawn ring around the chef that is inside the arena.
-- Near a wall part of the ring is outside, so try a few angles before giving up and clamping.
local function pickSpawnPoint(chefPosition: Vector3): Vector3
	local point = chefPosition
	for _ = 1, 8 do
		local angle = random:NextNumber(0, 2 * math.pi)
		point = chefPosition + Vector3.new(math.cos(angle), 0, math.sin(angle)) * RunRules.EnemySpawnRadius
		if isInsideArena(point) then
			return point
		end
	end
	return clampToArena(point)
end

-- Take a parked part from the pool, or make a new one if the pool is empty.
local function takePart(enemyType: string, config: Enemies.Enemy): BasePart
	local pool = pools[enemyType]
	local part = table.remove(pool)
	if part then
		return part
	end

	local newPart = Instance.new("Part")
	newPart.Name = enemyType
	newPart.Shape = if config.Shape == "Ball" then Enum.PartType.Ball else Enum.PartType.Block
	newPart.Size = config.Size
	newPart.Color = config.Color
	newPart.Material = Enum.Material.SmoothPlastic
	newPart.Anchored = true
	-- Enemies are moved by code and hit by distance checks, so turn off all physics work.
	newPart.CanCollide = false
	newPart.CanQuery = false
	newPart.CanTouch = false
	newPart.CastShadow = false
	newPart.CFrame = PARK_CFRAME
	newPart.Parent = enemyFolder
	return newPart
end

local function fireKilled(enemyId: EnemyId, enemyType: string, position: Vector3)
	for _, callback in killedCallbacks do
		task.spawn(callback, enemyId, enemyType, position)
	end
end

-- Remove a dead enemy: forget its record, park its part, tell the listeners.
local function kill(enemy: EnemyRecord)
	alive[enemy.id] = nil
	aliveCount -= 1
	enemy.part.CFrame = PARK_CFRAME
	table.insert(pools[enemy.enemyType], enemy.part)
	fireKilled(enemy.id, enemy.enemyType, enemy.position)
end

-- The config for an enemy type: a normal enemy from Enemies.luau, or a boss's Body from
-- Bosses.luau. nil if the type is unknown. Use this instead of Enemies[...] so bosses work too.
function EnemyService.getConfigForType(enemyType: string): Enemies.Enemy?
	local boss = Bosses[enemyType]
	return Enemies[enemyType] or (boss and boss.Body)
end

-- How much tougher enemies spawning right now are: HP and damage multipliers from the run clock
-- (PRD §3.4). Compounding: (1 + growth) ^ minutes.
function EnemyService.getScaling(): (number, number)
	local minutes = RunManager.getRunSeconds() / 60
	return (1 + RunRules.EnemyHpGrowthPerMinute) ^ minutes, (1 + RunRules.EnemyDamageGrowthPerMinute) ^ minutes
end

-- Create one enemy standing on the floor at `position` (only X and Z are used).
-- `scaled` = apply run-time scaling (normal enemies and minions yes, bosses no).
local function spawnWithConfig(enemyType: string, config: Enemies.Enemy, position: Vector3, scaled: boolean): EnemyId
	local hpScale, damageScale = 1, 1
	if scaled then
		hpScale, damageScale = EnemyService.getScaling()
	end
	-- Stand on the floor (floor top is at the arena center's height, 0 by default).
	local floorY = if arenaCenter then arenaCenter.Y else 0
	local standing = Vector3.new(position.X, floorY + config.Size.Y / 2, position.Z)

	-- Start out facing the chef (or "north" if there is no chef yet).
	local direction = Vector3.new(0, 0, -1)
	local chefPosition = getChefPosition()
	if chefPosition then
		local toChef = Vector3.new(chefPosition.X - standing.X, 0, chefPosition.Z - standing.Z)
		if toChef.Magnitude > 0.01 then
			direction = toChef.Unit
		end
	end

	lastId += 1
	local enemy: EnemyRecord = {
		id = lastId,
		enemyType = enemyType,
		config = config,
		part = takePart(enemyType, config),
		hp = config.Hp * hpScale,
		maxHp = config.Hp * hpScale,
		damage = config.Damage * damageScale,
		position = standing,
		direction = direction,
	}
	enemy.part.CFrame = CFrame.lookAt(standing, standing + direction)
	alive[enemy.id] = enemy
	aliveCount += 1
	return enemy.id
end

-- Create one enemy of `enemyType` (an id from Enemies.luau) standing on the floor at `position`
-- (only X and Z are used). Returns its id, or nil if the alive cap is reached or the type is unknown.
function EnemyService.spawn(enemyType: string, position: Vector3): EnemyId?
	local config = Enemies[enemyType]
	if not config then
		warn(`[EnemyService] unknown enemy type "{enemyType}"`)
		return nil
	end
	if aliveCount >= RunRules.MaxAliveEnemies then
		return nil
	end
	return spawnWithConfig(enemyType, config, clampToArena(position), true)
end

-- Create a boss (an id from Bosses.luau that has a Body). Bosses ignore the alive cap.
-- Returns its id, or nil if the boss has no Body.
function EnemyService.spawnBoss(bossType: string, position: Vector3): EnemyId?
	local boss = Bosses[bossType]
	if not (boss and boss.Body) then
		warn(`[EnemyService] boss "{bossType}" has no Body in Bosses.luau`)
		return nil
	end
	return spawnWithConfig(bossType, boss.Body, clampToArena(position), false)
end

-- Remove every live enemy without a kill: no tips, no kill count, no callbacks.
-- Used when the final boss arrives and clears the kitchen.
function EnemyService.clearAll()
	for id, enemy in alive do
		alive[id] = nil
		enemy.part.CFrame = PARK_CFRAME
		table.insert(pools[enemy.enemyType], enemy.part)
	end
	aliveCount = 0
end

-- Keep every enemy inside a circle (the boss ring), or pass nil to lift the limit.
function EnemyService.setBossArena(center: Vector3?, radius: number)
	bossArenaCenter = center
	bossArenaRadius = radius
end

-- Choose which enemy types the spawner creates, and how many groups per second
-- (a group is GroupSize enemies, or just one for most types).
-- RunManager calls this when the timeline moves to a new phase (#6). An empty list stops spawning.
function EnemyService.setSpawning(enemyTypes: { string }, perSecond: number)
	spawnTypes = {}
	for _, enemyType in enemyTypes do
		if Enemies[enemyType] then
			table.insert(spawnTypes, enemyType)
		else
			warn(`[EnemyService] setSpawning: unknown enemy type "{enemyType}"`)
		end
	end
	spawnsPerSecond = math.max(perSecond, 0)
end

-- How many enemies are alive right now (HUD, performance testing).
function EnemyService.getAliveCount(): number
	return aliveCount
end

-- Ids of every live enemy within `radius` studs of `position`. Weapons use this to find targets.
-- Distance is measured flat (X and Z only), because the game is seen from above.
function EnemyService.getEnemiesInRadius(position: Vector3, radius: number): { EnemyId }
	local found: { EnemyId } = {}
	local radiusSquared = radius * radius
	for id, enemy in alive do
		local dx = enemy.position.X - position.X
		local dz = enemy.position.Z - position.Z
		-- Comparing squared distances skips a square root per enemy.
		if dx * dx + dz * dz <= radiusSquared then
			table.insert(found, id)
		end
	end
	return found
end

-- Where an enemy is right now, or nil if it is dead. Weapons use this for aim and arc checks.
function EnemyService.getEnemyPosition(enemyId: EnemyId): Vector3?
	local enemy = alive[enemyId]
	return enemy and enemy.position
end

-- An enemy's config id (e.g. "MoldyBread"), or nil if it is dead. ContactService uses this
-- to look up its Damage and Size.
function EnemyService.getEnemyType(enemyId: EnemyId): string?
	local enemy = alive[enemyId]
	return enemy and enemy.enemyType
end

-- An enemy's part (what the player sees), or nil if it is dead. BossService decorates the boss's part.
function EnemyService.getEnemyPart(enemyId: EnemyId): BasePart?
	local enemy = alive[enemyId]
	return enemy and enemy.part
end

-- Pull one enemy up to `studs` toward `toward` (Smoothie Vortex, #51). It stops at the
-- chef's edge rather than inside (pulls are always toward the chef) and stays inside the
-- arena. Bosses are too heavy to pull: nothing happens. The part follows on the next frame.
function EnemyService.pull(enemyId: EnemyId, toward: Vector3, studs: number)
	local enemy = alive[enemyId]
	if not enemy or Bosses[enemy.enemyType] or studs <= 0 then
		return
	end
	local offset = Vector3.new(toward.X - enemy.position.X, 0, toward.Z - enemy.position.Z)
	local distance = offset.Magnitude
	local stopDistance = CHEF_RADIUS + enemy.config.Size.X / 2
	local step = math.min(studs, distance - stopDistance)
	if step <= 0 then
		return -- already touching the chef
	end
	enemy.position = clampToArena(enemy.position + offset / distance * step)
end

-- Push one enemy `studs` directly away from `from` (Microwave Pulse knockback, #66): the mirror
-- of pull. Stays inside the arena. Bosses are too heavy to push: nothing happens. The part
-- follows on the next frame.
function EnemyService.push(enemyId: EnemyId, from: Vector3, studs: number)
	local enemy = alive[enemyId]
	if not enemy or Bosses[enemy.enemyType] or studs <= 0 then
		return
	end
	local away = Vector3.new(enemy.position.X - from.X, 0, enemy.position.Z - from.Z)
	if away.Magnitude < 0.01 then
		away = Vector3.new(math.cos(enemyId), 0, math.sin(enemyId)) -- right on the spot: pick a side
	end
	enemy.position = clampToArena(enemy.position + away.Unit * studs)
end

-- An enemy's current HP and max HP, or nil if it is dead (boss HP bar).
function EnemyService.getEnemyHp(enemyId: EnemyId): (number?, number?)
	local enemy = alive[enemyId]
	if not enemy then
		return nil, nil
	end
	return enemy.hp, enemy.maxHp
end

-- An enemy's contact damage (its config's Damage, scaled by when it spawned), or nil if it is dead.
function EnemyService.getEnemyDamage(enemyId: EnemyId): number?
	local enemy = alive[enemyId]
	return enemy and enemy.damage
end

-- The widest enemy or boss, in studs. ContactService uses it to know how far to look.
function EnemyService.getMaxEnemyWidth(): number
	local widest = 0
	for _, config in Enemies do
		widest = math.max(widest, config.Size.X)
	end
	for _, boss in Bosses do
		if boss.Body then
			widest = math.max(widest, boss.Body.Size.X)
		end
	end
	return widest
end

-- Deal damage to one enemy. Does nothing if the enemy is already dead.
-- When HP reaches 0 the enemy dies, returns to the pool and every onEnemyKilled callback runs.
function EnemyService.damage(enemyId: EnemyId, amount: number)
	local enemy = alive[enemyId]
	if not enemy or amount <= 0 then
		return
	end
	enemy.hp -= amount
	if enemy.hp <= 0 then
		kill(enemy)
	end
end

-- Run `callback` every time an enemy dies (tip drops, kill count).
function EnemyService.onEnemyKilled(callback: KilledCallback)
	table.insert(killedCallbacks, callback)
end

-- Work out where one enemy goes this frame, based on its config's Movement.
-- Updates enemy.position and enemy.direction.
local function moveEnemy(enemy: EnemyRecord, deltaTime: number, chefPosition: Vector3)
	local config = enemy.config
	local toChef = Vector3.new(chefPosition.X - enemy.position.X, 0, chefPosition.Z - enemy.position.Z)
	local distance = toChef.Magnitude
	local step = config.Speed * deltaTime

	if config.Movement == "Chase" then
		-- Face the chef every frame and walk straight at them.
		if distance > 0.01 then
			enemy.direction = toChef / distance
		end
		-- Stop at the chef's edge instead of walking inside them.
		local stopDistance = CHEF_RADIUS + config.Size.X / 2
		step = math.min(step, math.max(distance - stopDistance, 0))
	elseif config.Movement == "Charge" then
		-- Keep rolling the same way. Once it has rolled past the chef (moving away)
		-- by more than ChargeOvershootDistance, aim at the chef again.
		local movingAway = enemy.direction:Dot(toChef) < 0
		if movingAway and distance > RunRules.ChargeOvershootDistance then
			enemy.direction = toChef / distance
		end
	end

	local wanted = enemy.position + enemy.direction * step
	local allowed = clampToArena(wanted)
	-- A charger that runs into a wall aims at the chef again instead of sliding along it.
	if config.Movement == "Charge" and allowed ~= wanted and distance > 0.01 then
		enemy.direction = toChef / distance
	end
	enemy.position = allowed
end

-- One number per grid cell, so cells can be table keys. Works for cells -5000 to 5000.
local function cellKey(cellX: number, cellZ: number): number
	return (cellX + 5000) * 10000 + (cellZ + 5000)
end

-- Push overlapping enemies apart so the swarm spreads into a crowd instead of one stack.
local function separateEnemies(deltaTime: number, chefPosition: Vector3)
	-- Put every enemy into its grid cell.
	table.clear(grid)
	for _, enemy in alive do
		local key = cellKey(math.floor(enemy.position.X / cellSize), math.floor(enemy.position.Z / cellSize))
		local cell = grid[key]
		if cell then
			table.insert(cell, enemy)
		else
			grid[key] = { enemy }
		end
	end

	for _, enemy in alive do
		local cellX = math.floor(enemy.position.X / cellSize)
		local cellZ = math.floor(enemy.position.Z / cellSize)
		local push = Vector3.zero

		for dx = -1, 1 do
			for dz = -1, 1 do
				local cell = grid[cellKey(cellX + dx, cellZ + dz)]
				if cell then
					for _, other in cell do
						if other ~= enemy then
							local away =
								Vector3.new(enemy.position.X - other.position.X, 0, enemy.position.Z - other.position.Z)
							local distance = away.Magnitude
							-- Two enemies touch when their centers are closer than half of each one's width.
							local minDistance = (enemy.config.Size.X + other.config.Size.X) / 2
							if distance < minDistance then
								if distance < 0.01 then
									-- Exactly on top of each other: pick a direction from the id so they split.
									away = Vector3.new(math.cos(enemy.id), 0, math.sin(enemy.id))
									distance = 0.01
								end
								push += away / distance * (minDistance - distance)
							end
						end
					end
				end
			end
		end

		if push ~= Vector3.zero then
			push *= RunRules.EnemySeparationStrength
			-- In a dense pile the pushes from many neighbours add up. Limit the shove so an
			-- enemy is never pushed faster than its own speed (it would look like it got flung).
			local maxPush = enemy.config.Speed * deltaTime
			if push.Magnitude > maxPush then
				push = push.Unit * maxPush
			end
			enemy.position = clampToArena(enemy.position + push)
		end

		-- The crowd behind must not shove a chaser inside the chef: keep it at the chef's edge.
		-- (Chargers are allowed to roll through the chef.)
		if enemy.config.Movement == "Chase" then
			local fromChef = Vector3.new(enemy.position.X - chefPosition.X, 0, enemy.position.Z - chefPosition.Z)
			local stopDistance = CHEF_RADIUS + enemy.config.Size.X / 2
			local distance = fromChef.Magnitude
			if distance < stopDistance and distance > 0.01 then
				local edge = chefPosition + fromChef / distance * stopDistance
				enemy.position = Vector3.new(edge.X, enemy.position.Y, edge.Z)
			end
		end
	end
end

-- Move every live enemy, spread them apart, then move all their parts with one BulkMoveTo call (PRD §8.3).
local function moveEnemies(deltaTime: number, chefPosition: Vector3)
	for _, enemy in alive do
		moveEnemy(enemy, deltaTime, chefPosition)
	end
	separateEnemies(deltaTime, chefPosition)

	table.clear(moveParts)
	table.clear(moveCFrames)
	for _, enemy in alive do
		table.insert(moveParts, enemy.part)
		table.insert(moveCFrames, CFrame.lookAt(enemy.position, enemy.position + enemy.direction))
	end
	if #moveParts > 0 then
		-- FireCFrameChanged skips the extra Position/Orientation change events nobody listens to.
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Spawn one group of `enemyType` around `center`: GroupSize enemies clustered together
-- (most enemies have no GroupSize, so a group is just one enemy).
local function spawnGroup(enemyType: string, center: Vector3)
	local count = Enemies[enemyType].GroupSize or 1
	for _ = 1, count do
		local offset = Vector3.zero
		if count > 1 then
			local spread = RunRules.EnemyGroupSpread
			offset = Vector3.new(random:NextNumber(-spread, spread), 0, random:NextNumber(-spread, spread))
		end
		if not EnemyService.spawn(enemyType, clampToArena(center + offset)) then
			return -- alive cap reached
		end
	end
end

-- Spawn groups at the current rate (spawnsPerSecond counts groups, not single enemies).
local function spawnOverTime(deltaTime: number, chefPosition: Vector3)
	if #spawnTypes == 0 then
		return
	end
	spawnBudget += deltaTime * spawnsPerSecond
	while spawnBudget >= 1 do
		spawnBudget -= 1
		if aliveCount >= RunRules.MaxAliveEnemies then
			spawnBudget = 0 -- don't save up a burst while the cap is full
			break
		end
		local enemyType = spawnTypes[random:NextInteger(1, #spawnTypes)]
		spawnGroup(enemyType, pickSpawnPoint(chefPosition))
	end
end

-- Every frame: move the enemies that are alive, then spawn new ones.
local function update(deltaTime: number)
	if RunManager.isPaused() then
		return -- "Order Up!" is on screen: enemies freeze and nothing new spawns
	end
	local chefPosition = getChefPosition()
	if not chefPosition then
		return -- no chef (loading or respawning): everything waits
	end
	moveEnemies(deltaTime, chefPosition)
	spawnOverTime(deltaTime, chefPosition)
end

function EnemyService:init()
	enemyFolder = Instance.new("Folder")
	enemyFolder.Name = "Enemies"
	enemyFolder.Parent = workspace

	for enemyType in Enemies do
		pools[enemyType] = {}
	end
	for bossType, boss in Bosses do
		if boss.Body then
			pools[bossType] = {}
		end
	end
	cellSize = math.max(cellSize, EnemyService.getMaxEnemyWidth())

	-- The map stores its playable area as attributes (Workspace.Map, issue #5).
	local map = workspace:FindFirstChild("Map")
	local center = map and map:GetAttribute("ArenaCenter")
	local size = map and map:GetAttribute("ArenaSize")
	if typeof(center) == "Vector3" and typeof(size) == "Vector3" then
		arenaCenter = center
		arenaHalfSize = size / 2
	else
		warn("[EnemyService] Workspace.Map has no ArenaCenter/ArenaSize attributes; enemies can spawn anywhere")
	end
end

function EnemyService:start()
	-- RunManager owns the timeline and says what may spawn, and how fast, whenever it changes (#6).
	RunManager.onPhaseChanged(EnemyService.setSpawning)
	RunService.Heartbeat:Connect(update)
end

return EnemyService
