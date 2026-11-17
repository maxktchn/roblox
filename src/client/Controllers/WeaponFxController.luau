--!strict
-- Draws weapon effects. Visual only: damage was already decided on the server.
--
-- One drawing function per weapon Shape (see Shared/WeaponTypes), coloured by the
-- weapon's FxColor in config, so new weapons need no code here.
--   Arc        - a blade sweeps across the slice        (WeaponFx: facing, range, arcDegrees)
--   Aura       - a ring pulses around the chef           (WeaponFx: range)
--   Projectile - a shot flies out                        (WeaponFx: "Launch"/"End", ...)
--   Pulse      - a ring grows from where it was fired    (WeaponFx: origin, range, speed)
--   Lob        - an egg arcs over, then splashes         (WeaponFx: "Lob", from, to, seconds, radius)
--   Bounce     - a spinning disc chases one enemy part   (WeaponFx: "Disc", id, from, part, speed / "End", id)
--   Trail      - flat splats on the floor that fade       (WeaponFx: "Splat", id, position, width, seconds / "End", id)
--                (Buttered Barrage's butter slicks use the same messages)
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

-- LOB: an egg flies in an arc to where it lands, then a splash disc the size of its radius
-- flashes and fades. Parts are reused.
local SPLASH_SECONDS = 0.25
local spareEggParts: { Part } = {}
local spareSplashParts: { Part } = {}
local lobCount = 0

local function drawLob(color: Color3, from: Vector3, to: Vector3, seconds: number, radius: number)
	local floorY = to.Y - 1 -- an enemy's centre is about a stud above the floor
	local start = Vector3.new(from.X, floorY + 1, from.Z)
	local landing = Vector3.new(to.X, floorY, to.Z)
	local egg = table.remove(spareEggParts) or makeFxPart("Egg", color)
	egg.Shape = Enum.PartType.Ball
	egg.Material = Enum.Material.SmoothPlastic
	egg.Color = color
	egg.Size = Vector3.new(1.1, 1.1, 1.1)
	egg.Transparency = 0
	lobCount += 1
	local key = `Lob{lobCount}`
	animate(key, function(elapsed)
		local t = math.min(elapsed / seconds, 1)
		local height = 4 * RunRules.LobHeight * t * (1 - t) -- 0 at both ends, LobHeight at the top
		egg.CFrame = CFrame.new(start:Lerp(landing, t) + Vector3.new(0, height, 0))
		if t < 1 then
			return true
		end
		egg.Transparency = 1
		table.insert(spareEggParts, egg)
		-- Land: a flat splash disc that fades out.
		local splash = table.remove(spareSplashParts) or makeFxPart("Splash", color)
		splash.Shape = Enum.PartType.Cylinder
		splash.Color = color
		splash.Size = Vector3.new(0.2, radius * 2, radius * 2)
		splash.CFrame = CFrame.new(landing + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
		animate(`{key}Splash`, function(splashElapsed)
			if splashElapsed > SPLASH_SECONDS then
				splash.Transparency = 1
				table.insert(spareSplashParts, splash)
				return false
			end
			splash.Transparency = 0.3 + 0.7 * splashElapsed / SPLASH_SECONDS
			return true
		end)
		return false
	end)
end

-- BOUNCE: one spinning disc per disc id. Each "Disc" message says where it is and which enemy
-- part it's flying at; it follows that part until the next message or "End".
type DiscFx = { part: Part, position: Vector3, target: BasePart?, speed: number, lastElapsed: number }
local discFx: { [number]: DiscFx } = {}
local spareDiscParts: { Part } = {}

local function drawDiscLeg(color: Color3, discId: number, from: Vector3, target: BasePart?, speed: number)
	local existing = discFx[discId]
	if existing then
		-- A new leg: it hit an enemy and flies on to the next one.
		existing.position = from
		existing.target = target
		existing.speed = speed
		return
	end
	local part = table.remove(spareDiscParts) or makeFxPart("Disc", color)
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Metal
	part.Color = color
	part.Size = Vector3.new(0.25, 2, 2)
	part.Transparency = 0
	local disc: DiscFx = { part = part, position = from, target = target, speed = speed, lastElapsed = 0 }
	discFx[discId] = disc
	animate(`Disc{discId}`, function(elapsed)
		if discFx[discId] ~= disc then
			return false -- ended
		end
		local deltaTime = elapsed - disc.lastElapsed
		disc.lastElapsed = elapsed
		local goal = disc.target
		if goal and goal.Position.Y > -100 then -- a dead enemy's part is parked far below
			local toGoal = Vector3.new(goal.Position.X - disc.position.X, 0, goal.Position.Z - disc.position.Z)
			local step = disc.speed * deltaTime
			disc.position += if toGoal.Magnitude > step then toGoal.Unit * step else toGoal
		end
		-- A cylinder's length runs along X: tip it up so it lies flat, then spin it round.
		disc.part.CFrame = CFrame.new(disc.position)
			* CFrame.Angles(0, elapsed * 20, 0)
			* CFrame.Angles(0, 0, math.rad(90))
		return true
	end)
end

local function endDisc(discId: number)
	local disc = discFx[discId]
	if disc then
		discFx[discId] = nil
		disc.part.Transparency = 1
		table.insert(spareDiscParts, disc.part)
	end
end

-- SPLATS (Trail weapons, butter slicks): a flat disc on the floor that fades over its last
-- half second, or straight away on "End". Parts are reused.
local SPLAT_FADE_SECONDS = 0.5
local splatParts: { [number]: Part } = {}
local spareSplatParts: { Part } = {}

local function endSplat(splatId: number)
	local part = splatParts[splatId]
	if part then
		splatParts[splatId] = nil
		part.Transparency = 1
		table.insert(spareSplatParts, part)
	end
end

local function drawSplat(color: Color3, splatId: number, position: Vector3, width: number, seconds: number)
	local part = table.remove(spareSplatParts) or makeFxPart("Splat", color)
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	part.Size = Vector3.new(0.1, width, width)
	part.CFrame = CFrame.new(position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Transparency = 0.25
	splatParts[splatId] = part
	animate(`Splat{splatId}`, function(elapsed)
		if splatParts[splatId] ~= part then
			return false -- ended early (the oldest of a full trail)
		end
		local left = seconds - elapsed
		if left <= 0 then
			endSplat(splatId)
			return false
		end
		if left < SPLAT_FADE_SECONDS then
			part.Transparency = 0.25 + 0.75 * (1 - left / SPLAT_FADE_SECONDS)
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
	elseif config.Shape == "Lob" then
		drawLob(color, select(2, ...))
	elseif config.Shape == "Trail" then
		local action, splatId = ...
		if action == "Splat" then
			drawSplat(color, select(2, ...))
		elseif action == "End" then
			endSplat(splatId)
		end
	elseif config.Shape == "Bounce" then
		local action, discId = ...
		if action == "Disc" then
			drawDiscLeg(color, select(2, ...))
		elseif action == "End" then
			endDisc(discId)
		end
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
