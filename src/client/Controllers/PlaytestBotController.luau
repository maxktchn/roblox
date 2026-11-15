--!strict
-- Playtest bot (#22), client half. Dev only: does nothing unless the server set the player's
-- "BotRunning" attribute (PlaytestBotService, started from the DEV panel).
--
-- While it runs, every frame it adds up a few "pushes" and walks the chef that way:
--   * away from enemies that are too close (Meatballs and bosses from further away)
--   * toward the nearest small enemy when it's far and HP is fine, so weapons hit something
--   * away from the walls, plus a slow circle around the arena, like a person kiting
--   * toward a pie when hurt, otherwise toward tips nearby
-- and aims at the nearest enemy. Cards are picked by the server half.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AimController = require(script.Parent.AimController)
local Bosses = require(ReplicatedStorage.Config.Bosses)

local PlaytestBotController = {}

local player = Players.LocalPlayer

local SEE_DISTANCE = 30 -- enemies further than this are ignored for dodging
local KEEP_AWAY_BIG = 14 -- studs to keep from Meatballs and bosses
local KEEP_AWAY_SMALL = 5 -- studs to keep from everything else
local CHASE_FROM = 7 -- walk toward the nearest small enemy when it's further than this
local CHASE_MIN_HP = 0.35 -- ...and HP is above this share of max
local WALL_DISTANCE = 30 -- start pushing back toward the middle this close to a wall
local PIE_BELOW_HP = 0.75 -- go for pies below this share of max HP
local TIP_DISTANCE = 40 -- go for tips this close

-- How hard each enemy type pushes the chef away (1 if not listed).
local PUSH_WEIGHT: { [string]: number } = { Meatball = 3, FruitFlies = 0.6 }
local BOSS_PUSH_WEIGHT = 6

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function isBig(name: string): boolean
	return name == "Meatball" or Bosses[name] ~= nil
end

local function step()
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
					local keep = if big then KEEP_AWAY_BIG else KEEP_AWAY_SMALL
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

	-- player:Move works with this game's controls; Humanoid:Move gets overridden each frame.
	player:Move(if push.Magnitude > 0.05 then push.Unit else Vector3.zero, false)

	-- Aim like the mobile aim stick does: screen offset (+X right, +Y down) = world X, Z.
	if nearestAway then
		AimController.setAimFromStick(Vector2.new(-nearestAway.X, -nearestAway.Z).Unit * 50)
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
