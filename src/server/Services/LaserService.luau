--!strict
-- The Microwave Monster's spinning lasers (#93, PRD §3.5), during its phase-2 laser turns.
-- BossService starts them once the boss reaches the middle of the ring and stops them when the
-- laser turn ends.
--
--   * Fight.LaserCount beams, evenly spaced, from the boss out to the ring of counters.
--   * For the first Fight.LaserWarning seconds they are thin and see-through, and still: a
--     warning. They start with the chef halfway between two beams, so the warning is never
--     on top of them.
--   * Then they go live: wide, solid, and sweeping round at Fight.LaserTurnSpeed degrees per
--     second (clockwise or anticlockwise, picked at random each turn).
--   * A live beam touching the chef hits for Fight.LaserDamage, at most once every
--     Fight.LaserHitCooldown seconds. Only the chef is hurt.
--
-- Hits are flat distance checks (PRD §8.3), like everything else. Frozen while paused.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bosses = require(ReplicatedStorage.Config.Bosses)
local EnemyService = require(script.Parent.EnemyService)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)

local LaserService = {}

local CHEF_RADIUS = RunRules.ChefRadius
local BEAM_COLOR = Color3.fromRGB(255, 40, 40)
local WARNING_WIDTH = 0.4
local WARNING_TRANSPARENCY = 0.6
local LIVE_TRANSPARENCY = 0.15
local BEAM_HEIGHT = 1.2 -- studs tall (live)
local BEAM_Y = 2.5 -- studs above the floor: about the chef's waist

type Lasers = {
	bossId: number,
	center: Vector3, -- the ring's middle
	ringRadius: number, -- beams stop at this distance from the middle
	fight: Bosses.BossFight,
	angle: number, -- radians, beam 1's direction (others follow evenly)
	spin: number, -- +1 or -1
	elapsed: number, -- seconds since start
	hitCooldown: number, -- seconds until the chef can be hit again
	beams: { Part },
}

local active: Lasers? = nil
local folder: Folder
local random = Random.new()

local function getChefPosition(): Vector3?
	local player = Players:GetPlayers()[1]
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function getFloorY(): number
	local map = workspace:FindFirstChild("Map")
	local center = map and map:GetAttribute("ArenaCenter")
	return if typeof(center) == "Vector3" then center.Y else 0
end

-- How far from `origin` along flat unit `direction` until the circle (center, radius) is reached.
-- `origin` is inside the circle, so there's always an answer.
local function distanceToRing(origin: Vector3, direction: Vector3, center: Vector3, radius: number): number
	local offset = Vector3.new(origin.X - center.X, 0, origin.Z - center.Z)
	local b = offset:Dot(direction)
	local c = offset:Dot(offset) - radius * radius
	return math.max(-b + math.sqrt(math.max(b * b - c, 0)), 0)
end

-- Every beam's flat direction right now.
local function getDirections(lasers: Lasers): { Vector3 }
	local directions = {}
	for i = 0, lasers.fight.LaserCount - 1 do
		local angle = lasers.angle + i * 2 * math.pi / lasers.fight.LaserCount
		table.insert(directions, Vector3.new(math.cos(angle), 0, math.sin(angle)))
	end
	return directions
end

local function isLive(lasers: Lasers): boolean
	return lasers.elapsed >= lasers.fight.LaserWarning
end

-- Put every beam part where its beam is.
local function drawBeams(lasers: Lasers, origin: Vector3)
	local live = isLive(lasers)
	local width = if live then lasers.fight.LaserWidth else WARNING_WIDTH
	local height = if live then BEAM_HEIGHT else WARNING_WIDTH
	local y = getFloorY() + BEAM_Y
	for i, direction in getDirections(lasers) do
		local beam = lasers.beams[i]
		local length = distanceToRing(origin, direction, lasers.center, lasers.ringRadius)
		local start = Vector3.new(origin.X, y, origin.Z)
		local middle = start + direction * (length / 2)
		beam.Size = Vector3.new(width, height, math.max(length, 0.1))
		beam.CFrame = CFrame.lookAt(middle, middle + direction)
		beam.Transparency = if live then LIVE_TRANSPARENCY else WARNING_TRANSPARENCY
	end
end

-- True if any live beam touches the chef.
local function touchesChef(lasers: Lasers, origin: Vector3, chefPosition: Vector3): boolean
	local offset = Vector3.new(chefPosition.X - origin.X, 0, chefPosition.Z - origin.Z)
	local reach = lasers.fight.LaserWidth / 2 + CHEF_RADIUS
	for _, direction in getDirections(lasers) do
		local along = offset:Dot(direction)
		local length = distanceToRing(origin, direction, lasers.center, lasers.ringRadius)
		if along > 0 and along <= length + CHEF_RADIUS then
			local sideways = (offset - direction * along).Magnitude
			if sideways <= reach then
				return true
			end
		end
	end
	return false
end

-- Start the lasers from the boss (`bossId`), reaching `ringRadius` studs from `center`.
function LaserService.turnOn(bossId: number, center: Vector3, ringRadius: number, fight: Bosses.BossFight)
	LaserService.turnOff()
	local origin = EnemyService.getEnemyPosition(bossId) or center
	-- Start with the chef halfway between two beams.
	local angle = random:NextNumber(0, 2 * math.pi)
	local chefPosition = getChefPosition()
	if chefPosition then
		local toChef = Vector3.new(chefPosition.X - origin.X, 0, chefPosition.Z - origin.Z)
		if toChef.Magnitude > 0.01 then
			angle = math.atan2(toChef.Z, toChef.X) + math.pi / fight.LaserCount
		end
	end

	local beams = {}
	for i = 1, fight.LaserCount do
		local beam = Instance.new("Part")
		beam.Name = `Laser{i}`
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
		beam.Material = Enum.Material.Neon
		beam.Color = BEAM_COLOR
		beam.Parent = folder
		table.insert(beams, beam)
	end

	local lasers: Lasers = {
		bossId = bossId,
		center = center,
		ringRadius = ringRadius,
		fight = fight,
		angle = angle,
		spin = if random:NextNumber() < 0.5 then 1 else -1,
		elapsed = 0,
		hitCooldown = 0,
		beams = beams,
	}
	active = lasers
	drawBeams(lasers, origin)
end

-- Take the lasers down (the laser turn ended, the boss died, or the run restarts).
function LaserService.turnOff()
	active = nil
	folder:ClearAllChildren()
end

-- Tests and the playtest bot: whether lasers are up, whether they are live, and each beam's
-- flat direction.
function LaserService.getState(): (boolean, boolean, { Vector3 })
	local lasers = active
	if not lasers then
		return false, false, {}
	end
	return true, isLive(lasers), getDirections(lasers)
end

local function update(deltaTime: number)
	local lasers = active
	if not lasers or RunManager.isPaused() or RunManager.isRunOver() then
		return
	end
	local origin = EnemyService.getEnemyPosition(lasers.bossId)
	if not origin then
		LaserService.turnOff() -- the boss died
		return
	end

	lasers.elapsed += deltaTime
	lasers.hitCooldown -= deltaTime
	if isLive(lasers) then
		lasers.angle += lasers.spin * math.rad(lasers.fight.LaserTurnSpeed) * deltaTime
	end
	drawBeams(lasers, origin)

	if isLive(lasers) and lasers.hitCooldown <= 0 then
		local chefPosition = getChefPosition()
		if chefPosition and touchesChef(lasers, origin, chefPosition) then
			lasers.hitCooldown = lasers.fight.LaserHitCooldown
			RunManager.damagePlayer(lasers.fight.LaserDamage, "BossLaser")
		end
	end
end

function LaserService:init()
	folder = Instance.new("Folder")
	folder.Name = "BossLasers"
	folder.Parent = workspace
end

function LaserService:start()
	RunService.Heartbeat:Connect(update)
end

return LaserService
