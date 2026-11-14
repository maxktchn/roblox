--!strict
-- Tips (XP) on the floor (PRD §2.4, §2.6). Defeated enemies drop a tip worth their
-- config's Tips value. Tips inside the pickup range fly to the chef and fill the tip bar.
--
-- Same pattern as EnemyService (PRD §8.3):
--   * Each tip is a record in a Lua table; its part is only what the player sees.
--   * Parts are pooled: a collected tip's part is parked and reused by the next drop.
--   * Pickup is a distance check every frame, not a physics touch.
--   * Flying tips are moved together with one workspace:BulkMoveTo call.
--   * At most RunRules.MaxTipsOnGround tips exist; past that, a new drop is added to the
--     oldest tip's value, so no XP is ever lost.
--
-- Server only: the server decides who collected what (PRD §8.4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EnemyService = require(script.Parent.EnemyService)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)
local StatsService = require(script.Parent.StatsService)
local UpgradeService = require(script.Parent.UpgradeService)

local PickupService = {}

type Tip = {
	value: number,
	position: Vector3,
	part: BasePart,
	flying: boolean, -- true once it has been "grabbed" by the pickup range
}

local PARK_CFRAME = CFrame.new(0, -210, 0) -- out of sight under the map
local COLLECT_DISTANCE = 1.5 -- studs: a flying tip this close to the chef is collected
local TIP_COLOR = Color3.fromRGB(245, 195, 40)

local tips: { Tip } = {} -- oldest first
local spareParts: { BasePart } = {}
local tipFolder: Folder
local floorY = 0 -- top of the floor (Workspace.Map's ArenaCenter.Y, like EnemyService)

-- Reused every frame for BulkMoveTo.
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

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

-- Bigger tips look bigger: small, medium and large coins (PRD §2.6).
local function sizeFor(value: number): Vector3
	local diameter = if value >= 5 then 2.2 elseif value >= 3 then 1.7 else 1.2
	-- A cylinder's length runs along X; a thin X makes a flat coin.
	return Vector3.new(0.3, diameter, diameter)
end

local function takePart(): BasePart
	local part = table.remove(spareParts)
	if part then
		return part
	end
	local newPart = Instance.new("Part")
	newPart.Name = "Tip"
	newPart.Shape = Enum.PartType.Cylinder
	newPart.Material = Enum.Material.Neon
	newPart.Color = TIP_COLOR
	newPart.Anchored = true
	newPart.CanCollide = false
	newPart.CanQuery = false
	newPart.CanTouch = false
	newPart.CastShadow = false
	newPart.Parent = tipFolder
	return newPart
end

-- A coin standing on its edge, so it reads as a coin from the camera above.
local function coinCFrame(position: Vector3): CFrame
	return CFrame.new(position) * CFrame.Angles(0, math.rad(45), 0)
end

-- Drop a tip worth `value` at `position` (only X and Z are used).
function PickupService.dropTip(position: Vector3, value: number)
	if value <= 0 then
		return
	end
	if #tips >= RunRules.MaxTipsOnGround then
		-- Too many on the floor: add the value to the oldest tip instead of making a new one.
		local oldest = tips[1]
		oldest.value += value
		oldest.part.Size = sizeFor(oldest.value)
		return
	end
	local size = sizeFor(value)
	local standing = Vector3.new(position.X, floorY + size.Y / 2, position.Z)
	local part = takePart()
	part.Size = size
	part.CFrame = coinCFrame(standing)
	table.insert(tips, { value = value, position = standing, part = part, flying = false })
end

-- How many tips are on the floor or flying right now.
function PickupService.getTipCount(): number
	return #tips
end

-- Remove every tip (start of a new run). No XP is given for them.
function PickupService.reset()
	for _, tip in tips do
		tip.part.CFrame = PARK_CFRAME
		table.insert(spareParts, tip.part)
	end
	table.clear(tips)
end

-- Pickup range right now: base range plus Fridge Magnet (PRD §3.3).
local function pickupRange(): number
	return RunRules.TipPickupRange * (1 + StatsService.getStat("PickupRange"))
end

local function update(deltaTime: number)
	if RunManager.isPaused() then
		return -- "Order Up!" is on screen: tips stay where they are
	end
	local chefPosition = getChefPosition()
	if not chefPosition or #tips == 0 then
		return
	end

	local range = pickupRange()
	local step = RunRules.TipFlySpeed * deltaTime
	local collected = 0
	table.clear(moveParts)
	table.clear(moveCFrames)

	-- Walk backwards so removing a collected tip doesn't skip the next one.
	for i = #tips, 1, -1 do
		local tip = tips[i]
		local toChef = Vector3.new(chefPosition.X - tip.position.X, 0, chefPosition.Z - tip.position.Z)
		local distance = toChef.Magnitude

		if not tip.flying and distance <= range then
			tip.flying = true -- once grabbed, it keeps flying even if the chef walks away
		end
		if tip.flying then
			if distance <= COLLECT_DISTANCE + step then
				-- Reached the chef: count it and send the part back to the pool.
				collected += tip.value
				tip.part.CFrame = PARK_CFRAME
				table.insert(spareParts, tip.part)
				table.remove(tips, i)
			else
				tip.position += toChef.Unit * step
				table.insert(moveParts, tip.part)
				table.insert(moveCFrames, coinCFrame(tip.position))
			end
		end
	end

	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if collected > 0 then
		UpgradeService.addTips(collected) -- one call per frame, however many tips arrived
	end
end

function PickupService:init()
	tipFolder = Instance.new("Folder")
	tipFolder.Name = "Tips"
	tipFolder.Parent = workspace

	local map = workspace:FindFirstChild("Map")
	local center = map and map:GetAttribute("ArenaCenter")
	if typeof(center) == "Vector3" then
		floorY = center.Y
	end
end

function PickupService:start()
	-- Every defeated enemy drops a tip worth its config's Tips value.
	EnemyService.onEnemyKilled(function(_enemyId, enemyType, position)
		local config = EnemyService.getConfigForType(enemyType) -- bosses drop tips too
		if config then
			PickupService.dropTip(position, config.Tips)
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return PickupService
