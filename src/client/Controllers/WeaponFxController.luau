--!strict
-- Draws weapon effects. Visual only: damage was already decided on the server.
--
-- One drawing function per weapon Shape (see Shared/WeaponTypes), coloured by the
-- weapon's FxColor in config, so new weapons need no code here.
--   Arc        - a blade sweeps across the slice        (WeaponFx: facing, range, arcDegrees)
--   Aura       - a ring pulses around the chef           (WeaponFx: range)
--   Projectile - a shot flies out                        (WeaponFx: "Launch"/"End", ...)
--   Pulse      - a ring grows from where it was fired    (WeaponFx: origin, range, speed)
--   Orbit      - objects circle the chef all the time. No messages: we read the weapon's
--                level from the player's "Weapon_<id>" attribute and use the shared server
--                clock, so they appear exactly where the server checks for hits.
--
-- Effect parts are created once and reused (PRD §8.3). They live only on this client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BossPowers = require(ReplicatedStorage.Config.BossPowers)
local Gadgets = require(ReplicatedStorage.Config.Gadgets)
local Recipes = require(ReplicatedStorage.Config.Recipes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunRules = require(ReplicatedStorage.Config.RunRules)
local Starters = require(ReplicatedStorage.Config.Starters)
local WeaponTypes = require(ReplicatedStorage.Shared.WeaponTypes)

local WeaponFxController = {}

local player = Players.LocalPlayer

-- Arc: how long the blade takes to sweep across. Shared with the server, which keeps the
-- swing live (hitting enemies that enter it) for exactly this long.
local SLASH_SECONDS = RunRules.SlashSeconds
local SLASH_FADE_SECONDS = 0.1 -- then it fades out over this long
local PULSE_SECONDS = 0.3 -- Aura: how long one ring pulse lasts

local folder: Folder -- holds every effect part

type WeaponConfig = { Shape: WeaponTypes.Shape?, Levels: { WeaponTypes.WeaponLevel }?, FxColor: Color3? }

local function getConfig(weaponId: string): WeaponConfig?
	return (Starters[weaponId] or Gadgets[weaponId] or Recipes[weaponId] or BossPowers[weaponId]) :: any
end

-- Every weapon (gadget or recipe) with the Orbit shape, found once at load.
local orbitWeapons: { [string]: WeaponConfig } = {}
for id, config in Gadgets do
	if config.Shape == "Orbit" and config.Levels then
		orbitWeapons[id] = config :: any
	end
end
for id, config in Recipes do
	if config.Shape == "Orbit" and config.Levels then
		orbitWeapons[id] = config :: any
	end
end

local function getRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- A plain glowing part for effects: no physics, no shadows, hidden until used.
local function makeFxPart(name: string, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 1
	part.Parent = folder
	return part
end

-- One reusable part per weapon id (and key), made the first time it's needed.
local partsByKey: { [string]: Part } = {}
local function getPart(key: string, color: Color3): Part
	local part = partsByKey[key]
	if not part then
		part = makeFxPart(key, color)
		partsByKey[key] = part
	end
	return part
end

-- Run `step(elapsed)` every frame until it returns false. A newer animation on the same
-- key stops the older one (token check), so effects never fight over a part.
local animationTokens: { [string]: number } = {}
local function animate(key: string, step: (elapsed: number) -> boolean)
	local token = (animationTokens[key] or 0) + 1
	animationTokens[key] = token
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if animationTokens[key] ~= token or not step(os.clock() - started) then
			connection:Disconnect()
		end
	end)
end

-- ARC: a blade sweeps from the left edge of the slice to the right edge, then fades.
local function drawArc(weaponId: string, color: Color3, facing: Vector3, range: number, arcDegrees: number)
	local part = getPart(weaponId, color)
	part.Size = Vector3.new(0.4, 0.2, range)
	local halfArc = math.rad(arcDegrees / 2)
	animate(weaponId, function(elapsed)
		local root = getRoot()
		if not root or elapsed > SLASH_SECONDS + SLASH_FADE_SECONDS then
			part.Transparency = 1
			return false
		end
		local progress = math.min(elapsed / SLASH_SECONDS, 1)
		local angle = halfArc - progress * 2 * halfArc
		local fade = math.max(elapsed - SLASH_SECONDS, 0) / SLASH_FADE_SECONDS
		part.Transparency = 0.2 + 0.8 * fade
		-- Start at the chef, face along `facing`, turn by `angle`, then push the
		-- blade forward by half its length so one end sits at the chef.
		local base = CFrame.lookAt(root.Position, root.Position + facing)
		part.CFrame = base * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -range / 2)
		return true
	end)
end

-- AURA: a flat see-through disc around the chef that grows slightly and fades.
-- A weapon that pulls (PullStrength; none in Phase 1) shrinks inward instead,
-- so every pulse looks like it is sucking enemies in.
local function drawAura(weaponId: string, color: Color3, range: number)
	local config = getConfig(weaponId)
	local levels = config and config.Levels
	local pulls = levels ~= nil and levels[1].PullStrength ~= nil
	local part = getPart(weaponId, color)
	part.Shape = Enum.PartType.Cylinder
	animate(weaponId, function(elapsed)
		local root = getRoot()
		if not root or elapsed > PULSE_SECONDS then
			part.Transparency = 1
			return false
		end
		local progress = elapsed / PULSE_SECONDS
		local radius = if pulls then range * (1 - 0.6 * progress) else range * (0.85 + 0.15 * progress)
		-- A cylinder's length runs along X, so turn it on its side to lie flat.
		part.Size = Vector3.new(0.2, radius * 2, radius * 2)
		part.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		part.Transparency = 0.55 + 0.45 * progress
		return true
	end)
end

-- PROJECTILE: one flying part per shot, moved here until the server says it ended.
local shotParts: { [number]: Part } = {}
local spareShotParts: { Part } = {}

local function endShot(shotId: number)
	local part = shotParts[shotId]
	if part then
		shotParts[shotId] = nil
		part.Transparency = 1
		table.insert(spareShotParts, part)
	end
end

local function drawShot(
	color: Color3,
	shotId: number,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	maxDistance: number
)
	local part = table.remove(spareShotParts) or makeFxPart("Shot", color)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Size = Vector3.new(1.4, 0.4, 1.4) -- a slice of toast
	part.Transparency = 0
	shotParts[shotId] = part
	animate(`Shot{shotId}`, function(elapsed)
		if shotParts[shotId] ~= part then
			return false -- the server ended it (hit something)
		end
		local traveled = math.min(elapsed * speed, maxDistance)
		local spin = CFrame.Angles(0, elapsed * 12, 0)
		part.CFrame = CFrame.new(origin + direction * traveled) * spin
		if traveled >= maxDistance then
			endShot(shotId)
			return false
		end
		return true
	end)
end

-- ORBIT: every frame, place each owned orbit weapon's objects around the chef.
local function updateOrbits()
	local root = getRoot()
	local now = workspace:GetServerTimeNow()
	for weaponId, config in orbitWeapons do
		local level = player:GetAttribute(`Weapon_{weaponId}`)
		local stats = if type(level) == "number" and config.Levels then config.Levels[level] else nil
		local count = if stats and root then stats.Count or 1 else 0
		local maxCount = 8 -- more than any level uses
		for i = 0, maxCount - 1 do
			local key = `{weaponId}_{i}`
			if i < count and stats and root then
				local part = getPart(key, config.FxColor or Color3.new(1, 1, 1))
				part.Material = Enum.Material.Metal
				part.Size = Vector3.new(0.5, 0.5, 2.4) -- a fork, pointing along its path
				local angle = math.rad(now * (stats.Speed or 180) + i * 360 / count)
				local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * stats.Range
				local position = root.Position + offset
				-- Point the fork along the direction it's moving (90° ahead of its angle).
				local ahead = Vector3.new(-math.sin(angle), 0, math.cos(angle))
				part.CFrame = CFrame.lookAt(position, position + ahead)
				part.Transparency = 0
			elseif partsByKey[key] then
				partsByKey[key].Transparency = 1
			end
		end
	end
end

-- PULSE: a flat ring grows from where it was fired out to `range` at `speed`, fading as it goes.
-- It stays where it was fired (it doesn't follow the chef), matching the server's hits.
local function drawPulse(weaponId: string, color: Color3, origin: Vector3, range: number, speed: number)
	local part = getPart(weaponId, color)
	part.Shape = Enum.PartType.Cylinder
	local duration = range / speed
	animate(weaponId, function(elapsed)
		if elapsed > duration then
			part.Transparency = 1
			return false
		end
		local progress = elapsed / duration
		local radius = math.max(range * progress, 0.5)
		-- A cylinder's length runs along X, so turn it on its side to lie flat.
		part.Size = Vector3.new(0.2, radius * 2, radius * 2)
		part.CFrame = CFrame.new(origin - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		part.Transparency = 0.35 + 0.65 * progress
		return true
	end)
end

local function onWeaponFx(weaponId: string, ...: any)
	local config = getConfig(weaponId)
	if not config or not config.Shape then
		return
	end
	local color = config.FxColor or Color3.new(1, 1, 1)
	if config.Shape == "Arc" then
		drawArc(weaponId, color, ...)
	elseif config.Shape == "Aura" then
		drawAura(weaponId, color, ...)
	elseif config.Shape == "Pulse" then
		drawPulse(weaponId, color, ...)
	elseif config.Shape == "Projectile" then
		local action, shotId = ...
		if action == "Launch" then
			drawShot(color, select(2, ...))
		elseif action == "End" then
			endShot(shotId)
		end
	end
end

function WeaponFxController:init()
	folder = Instance.new("Folder")
	folder.Name = "WeaponFx"
	folder.Parent = workspace
end

function WeaponFxController:start()
	Remotes.get("WeaponFx").OnClientEvent:Connect(onWeaponFx)
	RunService.RenderStepped:Connect(updateOrbits)
end

return WeaponFxController
