--!strict
-- Spawns, moves and pools enemies as data + simple parts, never Humanoids. Bulk-moves with workspace:BulkMoveTo, distance-check hits, alive cap from RunRules (PRD §8.3).
--
-- Public functions below are the agreed interface between the two tracks (issue #4).
-- They are stubs for now: Track A fills them in (#7), Track B can already call them.
-- Each run server has exactly one player (PRD §8.1), so no function takes a player.

local EnemyService = {}

-- Every live enemy has a number id. Ids are not reused while the enemy is alive.
export type EnemyId = number

-- Called once per defeated enemy: its id, its config id (e.g. "MoldyBread") and where it died.
export type KilledCallback = (enemyId: EnemyId, enemyType: string, position: Vector3) -> ()

local killedCallbacks: { KilledCallback } = {}

-- Ids of every live enemy within `radius` studs of `position`. Weapons use this to find targets.
function EnemyService.getEnemiesInRadius(_position: Vector3, _radius: number): { EnemyId }
	return {} -- TODO(#7)
end

-- Where an enemy is right now, or nil if it is dead. Weapons use this for aim and arc checks.
function EnemyService.getEnemyPosition(_enemyId: EnemyId): Vector3?
	return nil -- TODO(#7)
end

-- Deal damage to one enemy. Does nothing if the enemy is already dead.
-- When HP reaches 0 the enemy dies, returns to the pool and every onEnemyKilled callback runs.
function EnemyService.damage(_enemyId: EnemyId, _amount: number)
	-- TODO(#7)
end

-- Run `callback` every time an enemy dies (tip drops, kill count).
function EnemyService.onEnemyKilled(callback: KilledCallback)
	table.insert(killedCallbacks, callback)
end

-- Internal: call this from the death code so every listener hears about it.
local function _fireKilled(enemyId: EnemyId, enemyType: string, position: Vector3)
	for _, callback in killedCallbacks do
		task.spawn(callback, enemyId, enemyType, position)
	end
end

function EnemyService:init() end

function EnemyService:start() end

return EnemyService
