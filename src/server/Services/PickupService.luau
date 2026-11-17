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
-- Pies (#82, PRD §2.6): bigger enemies sometimes drop a pie (Enemies.luau PieDropChance).
-- Pies don't fly to the chef: the player walks over one to eat it and heal. While the chef is
-- at full HP a pie stays on the floor, so it can be saved for later.
--
-- Lunchboxes (#120, PRD §2.6): every elite drops one. Walk over it (no timeout) for
-- RunRules.EliteLunchboxUpgrades free "Order Up!" picks (UpgradeService.grantLevelUps).
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
local PIE_COLOR = Color3.fromRGB(255, 95, 120) -- pink-red: reads as "health", unlike the gold tips
local PIE_SIZE = Vector3.new(0.5, 2.4, 2.4) -- a flat disc (cylinder length runs along X)

local tips: { Tip } = {} -- oldest first
local spareParts: { BasePart } = {}
local tipFolder: Folder
local random = Random.new()

type Pie = { position: Vector3, part: BasePart }
local pies: { Pie } = {}
local sparePieParts: { BasePart } = {}
local piesEaten = 0 -- this run, for the run report

-- Lunchboxes (#120): a red box with a white handle that bobs and turns.
type Lunchbox = { position: Vector3, model: Model, age: number }
local lunchboxes: { Lunchbox } = {}
local lunchboxesOpened = 0 -- this run, for the run report
local LUNCHBOX_COLOR = Color3.fromRGB(215, 45, 45)
local LUNCHBOX_HEIGHT = 1.6 -- studs from the floor to the box's centre
local LUNCHBOX_BOB = 0.3 -- studs up and down
local LUNCHBOX_TURN_SPEED = 1.5 -- radians per second
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

-- A pie lying flat on the floor.
local function pieCFrame(position: Vector3): CFrame
	return CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
end

local function takePiePart(): BasePart
	local part = table.remove(sparePieParts)
	if part then
		return part
	end
	local newPart = Instance.new("Part")
	newPart.Name = "Pie"
	newPart.Shape = Enum.PartType.Cylinder
	newPart.Material = Enum.Material.Neon
	newPart.Color = PIE_COLOR
	newPart.Size = PIE_SIZE
	newPart.Anchored = true
	newPart.CanCollide = false
	newPart.CanQuery = false
	newPart.CanTouch = false
	newPart.CastShadow = false
	newPart.Parent = tipFolder
	return newPart
end

-- Drop a pie at `position` (only X and Z are used). Skipped if the floor already has the most.
function PickupService.dropPie(position: Vector3)
	if #pies >= RunRules.MaxPiesOnGround then
		return
	end
	local onFloor = Vector3.new(position.X, floorY + PIE_SIZE.X / 2, position.Z)
	local part = takePiePart()
	part.CFrame = pieCFrame(onFloor)
	table.insert(pies, { position = onFloor, part = part })
end

-- How many pies the chef has eaten this run.
function PickupService.getPiesEaten(): number
	return piesEaten
end

-- Eat any pie the chef is standing on, unless HP is already full.
local function updatePies(chefPosition: Vector3)
	local hp, maxHp = RunManager.getHp()
	if hp >= maxHp then
		return
	end
	for i = #pies, 1, -1 do
		local pie = pies[i]
		local offset = Vector3.new(chefPosition.X - pie.position.X, 0, chefPosition.Z - pie.position.Z)
		if offset.Magnitude <= RunRules.PiePickupDistance then
			RunManager.healPlayer(RunRules.PieHealFraction)
			piesEaten += 1
			pie.part.CFrame = PARK_CFRAME
			table.insert(sparePieParts, pie.part)
			table.remove(pies, i)
			return -- one pie per frame, so standing on two doesn't waste the second
		end
	end
end

local function makeLunchbox(): Model
	local model = Instance.new("Model")
	model.Name = "Lunchbox"
	local function piece(name: string, size: Vector3, color: Color3, offset: Vector3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = CFrame.new(offset)
		part.Parent = model
		return part
	end
	local box = piece("Box", Vector3.new(2.2, 1.5, 1.4), LUNCHBOX_COLOR, Vector3.zero)
	piece("Handle", Vector3.new(1.2, 0.3, 0.3), Color3.new(1, 1, 1), Vector3.new(0, 1, 0))
	piece("HandleLeft", Vector3.new(0.3, 0.6, 0.3), Color3.new(1, 1, 1), Vector3.new(-0.45, 0.75, 0))
	piece("HandleRight", Vector3.new(0.3, 0.6, 0.3), Color3.new(1, 1, 1), Vector3.new(0.45, 0.75, 0))
	model.PrimaryPart = box
	return model
end

-- Drop a Lunchbox at `position` (only X and Z are used). Skipped if the floor already has the most.
function PickupService.dropLunchbox(position: Vector3)
	if #lunchboxes >= RunRules.MaxLunchboxesOnGround then
		return
	end
	local onFloor = Vector3.new(position.X, floorY + LUNCHBOX_HEIGHT, position.Z)
	local model = makeLunchbox()
	model:PivotTo(CFrame.new(onFloor))
	model.Parent = tipFolder
	table.insert(lunchboxes, { position = onFloor, model = model, age = 0 })
end

-- How many Lunchboxes the chef has opened this run.
function PickupService.getLunchboxesOpened(): number
	return lunchboxesOpened
end

-- How many Lunchboxes are on the floor right now (tests).
function PickupService.getLunchboxCount(): number
	return #lunchboxes
end

-- Bob and turn the Lunchboxes, and open any the chef walks over.
local function updateLunchboxes(deltaTime: number, chefPosition: Vector3)
	for i = #lunchboxes, 1, -1 do
		local lunchbox = lunchboxes[i]
		local offset = Vector3.new(chefPosition.X - lunchbox.position.X, 0, chefPosition.Z - lunchbox.position.Z)
		if offset.Magnitude <= RunRules.LunchboxPickupDistance then
			lunchbox.model:Destroy()
			table.remove(lunchboxes, i)
			lunchboxesOpened += 1
			UpgradeService.grantLevelUps(RunRules.EliteLunchboxUpgrades)
		else
			lunchbox.age += deltaTime
			local bob = math.sin(lunchbox.age * 3) * LUNCHBOX_BOB
			lunchbox.model:PivotTo(
				CFrame.new(lunchbox.position + Vector3.new(0, bob, 0))
					* CFrame.Angles(0, lunchbox.age * LUNCHBOX_TURN_SPEED, 0)
			)
		end
	end
end

-- How many tips are on the floor or flying right now.
function PickupService.getTipCount(): number
	return #tips
end

-- Remove every tip and pie (start of a new run). No XP is given for them.
function PickupService.reset()
	for _, tip in tips do
		tip.part.CFrame = PARK_CFRAME
		table.insert(spareParts, tip.part)
	end
	table.clear(tips)
	for _, pie in pies do
		pie.part.CFrame = PARK_CFRAME
		table.insert(sparePieParts, pie.part)
	end
	table.clear(pies)
	piesEaten = 0
	for _, lunchbox in lunchboxes do
		lunchbox.model:Destroy()
	end
	table.clear(lunchboxes)
	lunchboxesOpened = 0
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
	if not chefPosition then
		return
	end
	if #pies > 0 and not RunManager.isRunOver() then
		updatePies(chefPosition)
	end
	if #lunchboxes > 0 and not RunManager.isRunOver() then
		updateLunchboxes(deltaTime, chefPosition)
	end
	if #tips == 0 then
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
	-- Every defeated enemy drops a tip worth its config's Tips value, and maybe a pie.
	EnemyService.onEnemyKilled(function(_enemyId, enemyType, position)
		local config = EnemyService.getConfigForType(enemyType) -- bosses drop tips too
		if config then
			PickupService.dropTip(position, config.Tips)
			local pieChance = config.PieDropChance
			if pieChance and random:NextNumber() < pieChance then
				PickupService.dropPie(position)
			end
			if config.IsElite then
				PickupService.dropLunchbox(position) -- elites always drop one (#120)
			end
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return PickupService
