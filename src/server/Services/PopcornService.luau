--!strict
-- The Microwave Monster's homing popcorn (#92, PRD §3.5). BossService decides when to fire;
-- this service owns the kernels after that.
--
-- A kernel is a normal enemy in EnemyService (PopcornKernel in Enemies.luau), so every weapon
-- can shoot it down. It chases the chef and does no contact damage. Whenever it dies it POPS:
--   * shot down by a weapon (it drops its tips, like any kill)
--   * touching the chef (removed without a kill: no tips)
--   * after its time is up (Fight.PopcornSeconds; removed without a kill)
-- A pop is a warning ring that grows for Fight.PopWarning seconds where the kernel was, then a
-- blast that hurts the chef (Fight.PopDamage) if they are within Fight.PopRadius.
-- Kill it far away and you're safe; let it reach you and you're not.
--
-- Everything stands still while the run is paused ("Order Up!").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bosses = require(ReplicatedStorage.Config.Bosses)
local EnemyService = require(script.Parent.EnemyService)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)

local PopcornService = {}

local CHEF_RADIUS = RunRules.ChefRadius
local HIT_FLASH_SECONDS = 0.15 -- how long the blast's red flash stays up (visual only)
-- Strong orange: pale colours vanish on the white and light-blue kitchen floor (phones!).
local WARNING_COLOR = Color3.fromRGB(255, 120, 0)
local HIT_COLOR = Color3.fromRGB(255, 40, 30)
local AREA_TRANSPARENCY = 0.7 -- the faint disc showing the whole blast area from the start
local FILL_TRANSPARENCY = 0.25 -- the solid disc growing inside it

type Kernel = { timeLeft: number, fight: Bosses.BossFight }
type Pop = { position: Vector3, timeLeft: number, fight: Bosses.BossFight, area: Part, ring: Part }

local kernels: { [number]: Kernel } = {} -- enemy id -> kernel
local pops: { Pop } = {}
local popFolder: Folder

local function getChefPosition(): Vector3?
	local player = Players:GetPlayers()[1]
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- The floor's height (Workspace.Map's ArenaCenter, issue #5).
local function getFloorY(): number
	local map = workspace:FindFirstChild("Map")
	local center = map and map:GetAttribute("ArenaCenter")
	return if typeof(center) == "Vector3" then center.Y else 0
end

-- Draw a disc flat on the floor, `radius` studs wide, `height` studs above the floor.
local function placeRing(ring: Part, position: Vector3, radius: number, color: Color3, height: number?)
	local diameter = math.max(radius * 2, 0.1)
	-- A cylinder's length runs along X, so tip it on its side to lie flat on the floor.
	ring.Size = Vector3.new(0.3, diameter, diameter)
	ring.CFrame = CFrame.new(position.X, getFloorY() + (height or 0.3), position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = color
end

local function makeDisc(name: string, transparency: number): Part
	local disc = Instance.new("Part")
	disc.Name = name
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Material = Enum.Material.Neon
	disc.Transparency = transparency
	return disc
end

-- A kernel died: start its pop where it was. The faint area disc shows the whole blast at
-- once (where to run); the solid disc grows inside it until the blast.
local function startPop(position: Vector3, fight: Bosses.BossFight)
	local area = makeDisc("PopcornPopArea", AREA_TRANSPARENCY)
	placeRing(area, position, fight.PopRadius, WARNING_COLOR, 0.2)
	area.Parent = popFolder
	local ring = makeDisc("PopcornPop", FILL_TRANSPARENCY)
	placeRing(ring, position, 0, WARNING_COLOR)
	ring.Parent = popFolder
	table.insert(pops, { position = position, timeLeft = fight.PopWarning, fight = fight, area = area, ring = ring })
end

-- Remove a kernel that popped on the chef or ran out of time (no kill, no tips), then pop it.
local function popKernel(enemyId: number, kernel: Kernel)
	local position = EnemyService.getEnemyPosition(enemyId)
	kernels[enemyId] = nil
	EnemyService.remove(enemyId)
	if position then
		startPop(position, kernel.fight)
	end
end

-- Fire one kernel at `position` for this boss fight. Returns its enemy id (nil if it failed).
function PopcornService.fire(position: Vector3, fight: Bosses.BossFight): number?
	local enemyId = EnemyService.spawnUnscaled(fight.PopcornEnemy, position)
	if enemyId then
		kernels[enemyId] = { timeLeft = fight.PopcornSeconds, fight = fight }
	end
	return enemyId
end

-- How many kernels are flying and how many pops are still warning (tests, the playtest bot).
function PopcornService.getCounts(): (number, number)
	local kernelCount = 0
	for _ in kernels do
		kernelCount += 1
	end
	return kernelCount, #pops
end

-- Take away every kernel and every pop without hurting anyone (the fight ended or the run restarts).
function PopcornService.reset()
	for enemyId in kernels do
		EnemyService.remove(enemyId)
	end
	table.clear(kernels)
	table.clear(pops)
	popFolder:ClearAllChildren()
end

local function update(deltaTime: number)
	if RunManager.isPaused() or RunManager.isRunOver() then
		return
	end
	local chefPosition = getChefPosition()

	-- Kernels: pop on touching the chef, or when their time is up.
	for enemyId, kernel in kernels do
		local position = EnemyService.getEnemyPosition(enemyId)
		if not position then
			kernels[enemyId] = nil -- gone some other way (onEnemyKilled has already popped it)
			continue
		end
		kernel.timeLeft -= deltaTime
		local touching = false
		local config = EnemyService.getConfigForType(kernel.fight.PopcornEnemy)
		if chefPosition and config then
			local reach = CHEF_RADIUS + EnemyService.getHalfDepth(config) + RunRules.ContactReach
			touching = flatDistance(position, chefPosition) <= reach
		end
		if touching or kernel.timeLeft <= 0 then
			popKernel(enemyId, kernel)
		end
	end

	-- Pops: the ring grows during the warning, then the blast hits.
	for i = #pops, 1, -1 do
		local pop = pops[i]
		pop.timeLeft -= deltaTime
		local fight = pop.fight
		if pop.timeLeft > 0 then
			local progress = 1 - pop.timeLeft / fight.PopWarning
			placeRing(pop.ring, pop.position, fight.PopRadius * progress, WARNING_COLOR)
		else
			table.remove(pops, i)
			pop.area:Destroy()
			placeRing(pop.ring, pop.position, fight.PopRadius, HIT_COLOR)
			local ring = pop.ring
			task.delay(HIT_FLASH_SECONDS, function()
				ring:Destroy() -- a short red flash, purely visual
			end)
			if chefPosition and flatDistance(chefPosition, pop.position) <= fight.PopRadius + CHEF_RADIUS then
				RunManager.damagePlayer(fight.PopDamage, "Popcorn")
			end
		end
	end
end

function PopcornService:init()
	popFolder = Instance.new("Folder")
	popFolder.Name = "PopcornPops"
	popFolder.Parent = workspace
end

function PopcornService:start()
	-- Shot down: it pops where it died (and drops its tips through PickupService, like any kill).
	EnemyService.onEnemyKilled(function(enemyId, _enemyType, position)
		local kernel = kernels[enemyId]
		if kernel then
			kernels[enemyId] = nil
			startPop(position, kernel.fight)
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return PopcornService
