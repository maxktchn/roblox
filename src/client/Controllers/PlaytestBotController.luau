--!strict
-- Playtest bot (#22), client half. Dev only: does nothing unless the server set the player's
-- "BotRunning" attribute (PlaytestBotService, started from the DEV panel).
--
-- While it runs, every frame it adds up a few "pushes" and walks the chef that way:
--   * away from enemies that are too close (Meatballs and the final boss from further away)
--   * toward the nearest small enemy (or the mini-boss) when it's far and HP is fine, so
--     weapons hit something
--   * away from the walls, plus a slow circle around the arena, like a person kiting
--   * toward a pie when hurt, otherwise toward tips nearby
--   * final boss (#94): away from popcorn kernels and out of a pop's blast area, and during
--     the spinning lasers into the middle of the gap it's in, turning with the beams
-- and aims at the nearest enemy (a popcorn kernel first, to shoot it down). Cards are picked
-- by the server half.
--
-- The bot only knows what the client sees (the beam parts, the pop discs), and it notices
-- the lasers switching direction by watching them, a moment late, like a person.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AimController = require(script.Parent.AimController)
local Bosses = require(ReplicatedStorage.Config.Bosses)

local PlaytestBotController = {}

local player = Players.LocalPlayer

local SEE_DISTANCE = 30 -- enemies further than this are ignored for dodging
local KEEP_AWAY_BIG = 14 -- studs to keep from Meatballs and the final boss
local KEEP_AWAY_SMALL = 5 -- studs to keep from everything else
local CHASE_FROM = 7 -- walk toward the nearest small enemy when it's further than this
local CHASE_MIN_HP = 0.35 -- ...and HP is above this share of max
local WALL_DISTANCE = 30 -- start pushing back toward the middle this close to a wall
local PIE_BELOW_HP = 0.75 -- go for pies below this share of max HP
local TIP_DISTANCE = 40 -- go for tips this close

-- How hard each enemy type pushes the chef away (1 if not listed).
local PUSH_WEIGHT: { [string]: number } = { Meatball = 3, FruitFlies = 0.6, PopcornKernel = 4 }
local BOSS_PUSH_WEIGHT = 6
local KEEP_AWAY_KERNEL = 11 -- popcorn pops 8 studs wide: stay outside that, plus a bit
local AIM_KERNEL_WITHIN = 25 -- aim at a popcorn kernel this close instead of the nearest enemy

-- Spinning lasers (#93).
local LASER_RADIUS_MIN = 15 -- studs from the boss to circle at (outside its keep-away)
local LASER_RADIUS_MAX = 26
local LASER_WEIGHT = 5 -- how hard to head for the middle of the gap
local LASER_DANGER = 4 -- studs from a live beam where the bot really hurries
local LASER_LEAD = 0.4 -- seconds ahead the bot aims for, given how fast the beams turn
local SPIN_SMOOTHING = 0.35 -- seconds: how quickly the bot notices a change of direction
local POP_MARGIN = 2.5 -- studs past a pop's blast area to get to

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Meatballs and the final boss are dodged from far away and never chased. The mini-boss
-- (The Big Cheese, #84) is slow and only hurts by touch, so the bot chases it like a small
-- enemy and fights it in knife range: the clock holds until it's beaten, so running from
-- it forever would stall the run.
local function isBig(name: string): boolean
	local boss = Bosses[name]
	return name == "Meatball" or name == "PopcornKernel" or (boss ~= nil and boss.Fight ~= nil)
end

-- What the bot has seen of the lasers: beam 1's angle last frame and how fast they turn.
local lastBeamAngle: number? = nil
local spinRate = 0 -- radians per second (+ = toward larger angles)

local function angleOf(v: Vector3): number
	return math.atan2(v.Z, v.X)
end

-- -pi..pi
local function wrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Lasers up: a push toward the middle of the gap the chef is in, a little ahead of where
-- it's turning. Returns nil when there are no lasers.
local function laserPush(pos: Vector3, deltaTime: number): Vector3?
	local folder = workspace:FindFirstChild("BossLasers")
	local beams = folder and folder:GetChildren() or {}
	if #beams == 0 then
		lastBeamAngle = nil
		spinRate = 0
		return nil
	end
	local origin: Vector3? = nil
	local angles = {}
	local live = false
	local first: number? = nil
	for _, beam in beams do
		if beam:IsA("BasePart") then
			local direction = flat(beam.CFrame.LookVector)
			if direction.Magnitude > 0.01 then
				direction = direction.Unit
				origin = flat(beam.Position) - direction * (beam.Size.Z / 2)
				table.insert(angles, angleOf(direction))
				live = live or beam.Size.X > 1
				if beam.Name == "Laser1" then
					first = angleOf(direction)
				end
			end
		end
	end
	if not origin or #angles == 0 then
		return nil
	end

	-- How fast they turn, smoothed: a switch of direction takes a moment to notice.
	if first and lastBeamAngle and deltaTime > 0 then
		local measured = wrap(first - lastBeamAngle) / deltaTime
		local blend = math.clamp(deltaTime / SPIN_SMOOTHING, 0, 1)
		spinRate += (measured - spinRate) * blend
	end
	lastBeamAngle = first

	-- Which gap the chef is in: the nearest beam on each side.
	local fromBoss = flat(pos) - origin
	local radius = fromBoss.Magnitude
	local chefAngle = angleOf(fromBoss)
	local before, after = -math.huge, math.huge -- signed angles of the neighbouring beams
	local nearestBeam = math.huge
	for _, angle in angles do
		local offset = wrap(angle - chefAngle)
		nearestBeam = math.min(nearestBeam, math.abs(offset))
		if offset <= 0 and offset > before then
			before = offset
		elseif offset > 0 and offset < after then
			after = offset
		end
	end
	if before == -math.huge or after == math.huge then
		return nil
	end
	local middle = chefAngle + (before + after) / 2 + (if live then spinRate * LASER_LEAD else 0)
	local targetRadius = math.clamp(radius, LASER_RADIUS_MIN, LASER_RADIUS_MAX)
	local target = origin + Vector3.new(math.cos(middle), 0, math.sin(middle)) * targetRadius
	local toward = target - flat(pos)
	if toward.Magnitude < 0.5 then
		return Vector3.zero
	end
	local danger = live and nearestBeam * math.max(radius, 1) < LASER_DANGER
	return toward.Unit * (if danger then LASER_WEIGHT * 2 else LASER_WEIGHT)
end

local function step(deltaTime: number)
	if not player:GetAttribute("BotRunning") then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local pos = root.Position
	local push = Vector3.zero
	local hp = (player:GetAttribute("Hp") or 100) :: number
	local maxHp = (player:GetAttribute("MaxHp") or 100) :: number

	-- Enemies: dodge the close ones, remember the nearest (to aim) and nearest small one.
	local nearestAway: Vector3? = nil -- from that enemy to the chef
	local nearestDistance = math.huge
	local smallAway: Vector3? = nil
	local smallDistance = math.huge
	local kernelAway: Vector3? = nil -- the nearest popcorn kernel, to shoot it down
	local kernelDistance = math.huge
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		for _, enemy in enemies:GetChildren() do
			if enemy:IsA("BasePart") and enemy.Position.Y > -50 then -- pooled parts wait far below
				local away = flat(pos - enemy.Position)
				if away.Magnitude > 0.01 then
					local distance = math.max(away.Magnitude - enemy.Size.Z / 2, 0.3)
					if distance < nearestDistance then
						nearestAway, nearestDistance = away, distance
					end
					local big = isBig(enemy.Name)
					local keep = if enemy.Name == "PopcornKernel"
						then KEEP_AWAY_KERNEL
						elseif big then KEEP_AWAY_BIG
						else KEEP_AWAY_SMALL
					if enemy.Name == "PopcornKernel" and distance < kernelDistance then
						kernelAway, kernelDistance = away, distance
					end
					if distance < keep and distance < SEE_DISTANCE then
						local weight = if Bosses[enemy.Name] then BOSS_PUSH_WEIGHT else PUSH_WEIGHT[enemy.Name] or 1
						push += away.Unit * weight * 25 / (distance * distance)
					end
					if not big and distance < smallDistance then
						smallAway, smallDistance = away, distance
					end
				end
			end
		end
	end
	if smallAway and smallDistance > CHASE_FROM and hp > maxHp * CHASE_MIN_HP then
		push -= smallAway.Unit * 0.8
	end

	-- Walls: push back toward the middle near the edges, and circle the arena slowly.
	local map = workspace:FindFirstChild("Map")
	local center = (map and map:GetAttribute("ArenaCenter") or Vector3.zero) :: Vector3
	local size = (map and map:GetAttribute("ArenaSize") or Vector3.new(176, 0, 176)) :: Vector3
	local fromCenter = flat(pos - center)
	local edge = math.min(size.X / 2 - math.abs(fromCenter.X), size.Z / 2 - math.abs(fromCenter.Z))
	if fromCenter.Magnitude > 1 then
		if edge < WALL_DISTANCE then
			push -= fromCenter.Unit * (1 - math.max(edge, 0) / WALL_DISTANCE) ^ 2 * 4
		end
		push += Vector3.new(-fromCenter.Z, 0, fromCenter.X).Unit * 0.35
	end

	-- Pickups: pies when hurt, tips otherwise. Both live in the Tips folder (PickupService).
	local pickups = workspace:FindFirstChild("Tips")
	if pickups then
		local pie: Vector3?, pieDistance = nil, math.huge
		local tip: Vector3?, tipDistance = nil, math.huge
		for _, part in pickups:GetChildren() do
			if part:IsA("BasePart") and part.Position.Y > -50 then
				local toward = flat(part.Position - pos)
				local distance = toward.Magnitude
				if part.Name == "Pie" then
					if distance < pieDistance then
						pie, pieDistance = toward, distance
					end
				elseif distance < tipDistance then
					tip, tipDistance = toward, distance
				end
			end
		end
		if pie and hp < maxHp * PIE_BELOW_HP and pieDistance > 0.1 then
			push += pie.Unit * 1.5
		elseif tip and tipDistance < TIP_DISTANCE and tipDistance > 0.1 then
			push += tip.Unit * 0.4
		end
	end

	-- Final boss: get out of popcorn blast areas, and keep to the gaps between the lasers.
	local pops = workspace:FindFirstChild("PopcornPops")
	if pops then
		for _, area in pops:GetChildren() do
			if area:IsA("BasePart") and area.Name == "PopcornPopArea" then
				local away = flat(pos - area.Position)
				local radius = area.Size.Y / 2 -- a flat disc: its width is Size.Y and Size.Z
				if away.Magnitude < radius + POP_MARGIN then
					local out = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
					push += out * 8
				end
			end
		end
	end
	local lasers = laserPush(pos, deltaTime)
	if lasers then
		push += lasers
	end

	-- player:Move works with this game's controls; Humanoid:Move gets overridden each frame.
	player:Move(if push.Magnitude > 0.05 then push.Unit else Vector3.zero, false)

	-- Aim like the mobile aim stick does: screen offset (+X right, +Y down) = world X, Z.
	local aimAway = if kernelAway and kernelDistance < AIM_KERNEL_WITHIN then kernelAway else nearestAway
	if aimAway then
		AimController.setAimFromStick(Vector2.new(-aimAway.X, -aimAway.Z).Unit * 50)
	end
end

function PlaytestBotController:start()
	RunService.RenderStepped:Connect(step)
	-- When the bot stops, let go of the chef.
	player:GetAttributeChangedSignal("BotRunning"):Connect(function()
		if not player:GetAttribute("BotRunning") then
			player:Move(Vector3.zero, false)
		end
	end)
end

return PlaytestBotController
