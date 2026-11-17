--!strict
-- Ranged enemy shots (#118, PRD §3.4): the Sour Lemon squirts juice. An enemy's Shot settings
-- are in Enemies.luau.
--
--   * Within Shot.Range studs of the chef, a shooter fires every Shot.Every seconds (the first
--     shot Shot.FirstDelay seconds after it gets in range, so a fresh one doesn't fire at once).
--   * Tell: it swells to Shot.Swell times its size for Shot.Windup seconds.
--   * Then a blob flies flat at Shot.Speed toward where the chef was, and stops there (it
--     doesn't keep flying). Walking sideways dodges it.
--   * A blob touching the chef does Shot.Damage (before armor; it grows over the run like the
--     shooter's contact damage) and is used up. Source "LemonJuice" in the run report.
--   * At most RunRules.MaxJuiceShots blobs in the air; past that, shooters skip a shot.
--
-- Hits are flat distance checks (PRD §8.3). Frozen while paused.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Enemies = require(ReplicatedStorage.Config.Enemies)
local EnemyService = require(script.Parent.EnemyService)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)

local JuiceService = {}

local CHEF_RADIUS = RunRules.ChefRadius
local BLOB_HEIGHT = 2 -- studs above the floor: about the chef's middle
local DAMAGE_SOURCE = "LemonJuice"

type Shooter = {
	timer: number, -- seconds until the next wind-up starts
	windup: number?, -- seconds left swelling before the shot, nil when not winding up
}
type Blob = {
	position: Vector3, -- flat
	target: Vector3, -- flat: where the chef was when it was fired
	shot: Enemies.Shot,
	damage: number,
	part: Part,
}

local shooters: { [number]: Shooter } = {} -- enemy id -> its shot timer
local blobs: { Blob } = {}
local spareParts: { Part } = {}
local folder: Folder
local floorY = 0
local hitCooldown = 0 -- seconds before a blob can hurt the chef again
local maxRange = 0 -- the longest Shot.Range of any enemy, worked out in init

local PARK_CFRAME = CFrame.new(0, -220, 0)

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function getChefPosition(): Vector3?
	local player = Players:GetPlayers()[1]
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function takePart(shot: Enemies.Shot): Part
	local part = table.remove(spareParts)
	if not part then
		local newPart = Instance.new("Part")
		newPart.Name = "JuiceBlob"
		newPart.Shape = Enum.PartType.Ball
		newPart.Material = Enum.Material.Neon
		newPart.Anchored = true
		newPart.CanCollide = false
		newPart.CanQuery = false
		newPart.CanTouch = false
		newPart.CastShadow = false
		newPart.Parent = folder
		part = newPart
	end
	local blobPart = part :: Part
	blobPart.Size = Vector3.one * shot.Size
	blobPart.Color = shot.Color
	return blobPart
end

local function removeBlob(index: number)
	local blob = blobs[index]
	blob.part.CFrame = PARK_CFRAME
	blob.part:SetAttribute("Target", nil)
	table.insert(spareParts, blob.part)
	table.remove(blobs, index)
end

-- Put a shooter's part back to its normal size (after a wind-up).
local function unswell(enemyId: number, config: Enemies.Enemy)
	local part = EnemyService.getEnemyPart(enemyId)
	if part then
		part.Size = config.Size
	end
end

local function fire(enemyId: number, config: Enemies.Enemy, shot: Enemies.Shot, chef: Vector3)
	if #blobs >= RunRules.MaxJuiceShots then
		return -- too many in the air: skip this one
	end
	local position = EnemyService.getEnemyPosition(enemyId)
	if not position then
		return
	end
	-- The shot grows over the run like the shooter's own contact damage (and x1.5 for an elite,
	-- whose Shot is already scaled).
	local contact = EnemyService.getEnemyDamage(enemyId) or config.Damage
	local damage = shot.Damage * (if config.Damage > 0 then contact / config.Damage else 1)
	local start = flat(position)
	local part = takePart(shot)
	part.CFrame = CFrame.new(start.X, floorY + BLOB_HEIGHT, start.Z)
	-- Where it's going, so the playtest bot can see it coming (like a person sees it fly).
	part:SetAttribute("Target", chef)
	table.insert(blobs, { position = start, target = chef, shot = shot, damage = damage, part = part })
end

-- How many blobs are in the air right now (tests).
function JuiceService.getBlobCount(): number
	return #blobs
end

-- Forget every shooter and blob (a new run is starting).
function JuiceService.reset()
	for i = #blobs, 1, -1 do
		removeBlob(i)
	end
	table.clear(shooters)
	hitCooldown = 0
end

local function updateShooters(deltaTime: number, chef: Vector3)
	-- Shooters in range keep their timers; anyone out of range (or dead) starts over.
	local inRange: { [number]: boolean } = {}
	for _, enemyId in EnemyService.getEnemiesInRadius(chef, maxRange) do
		local enemyType = EnemyService.getEnemyType(enemyId)
		local config = enemyType and EnemyService.getConfigForType(enemyType)
		local shot = config and config.Shot
		local position = EnemyService.getEnemyPosition(enemyId)
		if config and shot and position and (flat(position) - chef).Magnitude <= shot.Range then
			inRange[enemyId] = true
			local shooter = shooters[enemyId]
			if not shooter then
				shooter = { timer = shot.FirstDelay, windup = nil }
				shooters[enemyId] = shooter
			end
			local windup = shooter.windup
			if windup then
				windup -= deltaTime
				if windup <= 0 then
					shooter.windup = nil
					shooter.timer = shot.Every - shot.Windup
					unswell(enemyId, config)
					fire(enemyId, config, shot, chef)
				else
					shooter.windup = windup
				end
			else
				shooter.timer -= deltaTime
				if shooter.timer <= 0 then
					-- The tell: swell up, then shoot.
					shooter.windup = shot.Windup
					local part = EnemyService.getEnemyPart(enemyId)
					if part then
						part.Size = config.Size * shot.Swell
					end
				end
			end
		end
	end
	for enemyId, shooter in shooters do
		if not inRange[enemyId] then
			if shooter.windup then
				local enemyType = EnemyService.getEnemyType(enemyId)
				local config = enemyType and EnemyService.getConfigForType(enemyType)
				if config then
					unswell(enemyId, config)
				end
			end
			shooters[enemyId] = nil
		end
	end
end

local function updateBlobs(deltaTime: number, chef: Vector3?)
	hitCooldown -= deltaTime
	for i = #blobs, 1, -1 do
		local blob = blobs[i]
		local toTarget = blob.target - blob.position
		local step = blob.shot.Speed * deltaTime
		local arrived = toTarget.Magnitude <= step
		blob.position = if arrived then blob.target else blob.position + toTarget.Unit * step
		if chef and (chef - blob.position).Magnitude <= blob.shot.Size / 2 + CHEF_RADIUS and hitCooldown <= 0 then
			hitCooldown = RunRules.ChefHurtCooldown
			RunManager.damagePlayer(blob.damage, DAMAGE_SOURCE)
			removeBlob(i)
		elseif arrived then
			removeBlob(i) -- reached where the chef was: splat, gone
		else
			blob.part.CFrame = CFrame.new(blob.position.X, floorY + BLOB_HEIGHT, blob.position.Z)
		end
	end
end

local function update(deltaTime: number)
	if RunManager.isPaused() or RunManager.isRunOver() then
		return
	end
	local chefPosition = getChefPosition()
	local chef = chefPosition and flat(chefPosition)
	if chef then
		updateShooters(deltaTime, chef)
	end
	updateBlobs(deltaTime, chef)
end

function JuiceService:init()
	folder = Instance.new("Folder")
	folder.Name = "JuiceShots"
	folder.Parent = workspace

	local map = workspace:FindFirstChild("Map")
	local center = map and map:GetAttribute("ArenaCenter")
	if typeof(center) == "Vector3" then
		floorY = center.Y
	end
	for _, config in Enemies do
		if config.Shot then
			maxRange = math.max(maxRange, config.Shot.Range)
		end
	end
end

function JuiceService:start()
	RunService.Heartbeat:Connect(update)
end

return JuiceService
