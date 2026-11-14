--!strict
-- The final boss fight (PRD §3.5, issue #11): the Microwave Monster at the end of the run
-- (RunRules.RunLengthSeconds, 6:00).
--
-- When RunManager says the timeline is over (RunManager.onFinalBoss):
--   1. Every normal enemy is cleared and a ring of counters rises around the chef.
--      Nobody can leave the ring: the chef is blocked by invisible walls, enemies by EnemyService.
--   2. The boss spawns inside the ring. It is an enemy in EnemyService (with its Body from
--      Bosses.luau), so every weapon hits it and its touch hurts like any enemy's.
--   3. Every SummonEvery seconds it summons minions. Every PulseEvery seconds it sends out a
--      damage pulse: a ring grows around it for PulseWarning seconds (the warning), then hits
--      the chef if they are inside PulseRadius.
--   4. When it dies, the run is won.
-- Normal spawns stay off during the fight because the timeline has ended.
-- Everything stands still while the run is paused ("Order Up!").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Bosses = require(ReplicatedStorage.Config.Bosses)
local Chapters = require(ReplicatedStorage.Config.Chapters)
local EnemyService = require(script.Parent.EnemyService)
local RunManager = require(script.Parent.RunManager)

local BossService = {}

local CHEF_RADIUS = 1.5 -- same as EnemyService's: roughly how wide the chef is
local RING_SEGMENTS = 20 -- counters in the ring
local COUNTER_HEIGHT = 4
local COUNTER_DEPTH = 3
local RING_RISE_SECONDS = 1.2 -- how long the counters take to rise out of the floor

local COLORS = {
	cabinet = Color3.fromRGB(214, 72, 64), -- same red as the kitchen's counters
	steel = Color3.fromRGB(205, 210, 215),
	window = Color3.fromRGB(40, 40, 48),
	windowGlow = Color3.fromRGB(255, 200, 90),
	display = Color3.fromRGB(80, 230, 120),
	pulseWarning = Color3.fromRGB(255, 160, 40),
	pulseHit = Color3.fromRGB(255, 60, 40),
	hpBack = Color3.fromRGB(30, 30, 36),
	hpFill = Color3.fromRGB(220, 60, 50),
}

type ActiveFight = {
	bossId: number,
	fight: Bosses.BossFight,
	summonTimer: number, -- seconds until the next summon
	pulseTimer: number, -- seconds until the next pulse warning starts
	warningLeft: number?, -- while a pulse is warning: seconds until it hits
}

local active: ActiveFight? = nil
local pulsePart: Part
local hpFill: Frame? = nil
local random = Random.new()

-- The chef's root part, or nil while there is no chef.
local function getChefRoot(): BasePart?
	local player = Players:GetPlayers()[1]
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function flat(position: Vector3): Vector3
	return Vector3.new(position.X, 0, position.Z)
end

-- The map's floor height and playable half-size (Workspace.Map attributes, issue #5).
local function getMapBounds(): (Vector3, Vector3?)
	local map = workspace:FindFirstChild("Map")
	local center = map and map:GetAttribute("ArenaCenter")
	local size = map and map:GetAttribute("ArenaSize")
	local mapCenter = if typeof(center) == "Vector3" then center else Vector3.zero
	local halfSize = if typeof(size) == "Vector3" then size / 2 else nil
	return mapCenter, halfSize
end

-- Center the ring on the chef, but slide it so the whole ring fits inside the kitchen.
local function chooseRingCenter(chefPosition: Vector3, radius: number): Vector3
	local mapCenter, halfSize = getMapBounds()
	local x, z = chefPosition.X, chefPosition.Z
	if halfSize then
		local limitX = math.max(halfSize.X - radius - COUNTER_DEPTH, 0)
		local limitZ = math.max(halfSize.Z - radius - COUNTER_DEPTH, 0)
		x = math.clamp(x, mapCenter.X - limitX, mapCenter.X + limitX)
		z = math.clamp(z, mapCenter.Z - limitZ, mapCenter.Z + limitZ)
	end
	return Vector3.new(x, mapCenter.Y, z)
end

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- Build the ring of counters around `center`. The visible counters rise out of the floor;
-- the invisible walls are there straight away so the chef can't slip out while they rise.
local function buildRing(center: Vector3, radius: number)
	local old = workspace:FindFirstChild("BossRing")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "BossRing"

	-- Each counter is a slightly overlapping chunk of the circle.
	local length = 2 * math.pi * radius / RING_SEGMENTS + 0.6
	local floorY = center.Y
	local rise = TweenInfo.new(RING_RISE_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	for i = 0, RING_SEGMENTS - 1 do
		local angle = i / RING_SEGMENTS * 2 * math.pi
		local spot = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
		-- Facing the center: the counter's length runs along the circle.
		local facing = CFrame.lookAt(spot, Vector3.new(center.X, spot.Y, center.Z))

		local cabinetHeight = COUNTER_HEIGHT - 0.4
		local cabinetCFrame = facing + Vector3.new(0, floorY + cabinetHeight / 2 - spot.Y, 0)
		local topCFrame = facing + Vector3.new(0, floorY + COUNTER_HEIGHT - 0.2 - spot.Y, 0)
		local sunk = Vector3.new(0, -COUNTER_HEIGHT - 1, 0)

		local cabinet = makePart(
			folder,
			"Cabinet",
			Vector3.new(length, cabinetHeight, COUNTER_DEPTH),
			cabinetCFrame + sunk,
			COLORS.cabinet
		)
		local top =
			makePart(folder, "Top", Vector3.new(length, 0.4, COUNTER_DEPTH + 0.4), topCFrame + sunk, COLORS.steel)
		TweenService:Create(cabinet, rise, { CFrame = cabinetCFrame }):Play()
		TweenService:Create(top, rise, { CFrame = topCFrame }):Play()

		local wall = makePart(
			folder,
			"Wall",
			Vector3.new(length, 40, COUNTER_DEPTH),
			facing + Vector3.new(0, floorY + 20 - spot.Y, 0),
			COLORS.steel
		)
		wall.Transparency = 1
		wall.CanQuery = false -- weapons and the camera ignore it
		wall.CanTouch = false
	end

	folder.Parent = workspace
end

-- Make the boss's plain part look like a microwave, and give it an HP bar.
-- (Boss parts are pooled, so clear anything left from before first.)
local function decorateBoss(part: BasePart, bossName: string)
	for _, child in part:GetChildren() do
		if child:IsA("SurfaceGui") or child:IsA("BillboardGui") then
			child:Destroy()
		end
	end

	-- Front face (the side facing the chef): a dark window with a warm glow, and a green display.
	local face = Instance.new("SurfaceGui")
	face.Name = "MicrowaveFace"
	face.Face = Enum.NormalId.Front
	face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	face.PixelsPerStud = 40
	face.LightInfluence = 0
	face.Parent = part

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.Position = UDim2.fromScale(0.07, 0.15)
	window.Size = UDim2.fromScale(0.62, 0.7)
	window.BackgroundColor3 = COLORS.window
	window.BorderSizePixel = 0
	window.Parent = face
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.55)
	glow.Size = UDim2.fromScale(0.7, 0.5)
	glow.BackgroundColor3 = COLORS.windowGlow
	glow.BackgroundTransparency = 0.55
	glow.BorderSizePixel = 0
	glow.Parent = window

	local display = Instance.new("TextLabel")
	display.Name = "Display"
	display.Position = UDim2.fromScale(0.74, 0.15)
	display.Size = UDim2.fromScale(0.2, 0.18)
	display.BackgroundColor3 = COLORS.window
	display.BorderSizePixel = 0
	display.Font = Enum.Font.Code
	display.Text = "DING"
	display.TextScaled = true
	display.TextColor3 = COLORS.display
	display.Parent = face

	-- HP bar floating above the boss. Sized in studs, so it scales with the camera like the boss.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BossHp"
	billboard.Size = UDim2.fromScale(12, 2.2)
	billboard.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = part

	local title = Instance.new("TextLabel")
	title.Name = "Name"
	title.Size = UDim2.fromScale(1, 0.5)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.Text = bossName
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.3
	title.Parent = billboard

	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.Position = UDim2.fromScale(0, 0.58)
	back.Size = UDim2.fromScale(1, 0.38)
	back.BackgroundColor3 = COLORS.hpBack
	back.BorderSizePixel = 0
	back.Parent = billboard
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = COLORS.hpFill
	fill.BorderSizePixel = 0
	fill.Parent = back
	hpFill = fill
end

-- Hide the pulse ring under the map.
local function hidePulse()
	pulsePart.CFrame = CFrame.new(0, -200, 0)
end

-- Show the pulse ring around `center` at `radius` studs.
local function showPulse(center: Vector3, radius: number, color: Color3)
	local diameter = math.max(radius * 2, 0.1)
	-- A cylinder's length runs along X, so tip it on its side to lie flat on the floor.
	pulsePart.Size = Vector3.new(0.3, diameter, diameter)
	pulsePart.CFrame = CFrame.new(center.X, center.Y + 0.2, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	pulsePart.Color = color
end

-- End of the run: clear the kitchen, close the ring, bring out the boss.
local function startFight()
	local bossType = Chapters[RunManager.getChapter()].FinalBoss
	local boss = Bosses[bossType]
	local root = getChefRoot()
	if not (boss and boss.Body and boss.Fight and root) then
		warn(`[BossService] final boss "{bossType}" can't fight yet (needs Body and Fight); the run is won`)
		RunManager.winRun()
		return
	end
	local fight = boss.Fight

	EnemyService.clearAll()

	local center = chooseRingCenter(root.Position, fight.ArenaRadius)
	buildRing(center, fight.ArenaRadius)
	-- Enemies stay a little inside the counters (the counter's inner face is half its depth in).
	EnemyService.setBossArena(center, fight.ArenaRadius - COUNTER_DEPTH)

	-- If sliding the ring to fit the kitchen left the chef outside it, bring them in.
	if (flat(root.Position) - flat(center)).Magnitude > fight.ArenaRadius - COUNTER_DEPTH - 2 then
		local character = root.Parent :: Model
		character:PivotTo(CFrame.new(center + Vector3.new(0, 4, fight.ArenaRadius * 0.4)))
	end

	-- The boss appears on the far side of the ring from the chef.
	local away = flat(center) - flat(root.Position)
	local direction = if away.Magnitude > 1 then away.Unit else Vector3.new(0, 0, -1)
	local bossId = EnemyService.spawnBoss(bossType, center + direction * fight.ArenaRadius * 0.5)
	if not bossId then
		RunManager.winRun()
		return
	end
	local part = EnemyService.getEnemyPart(bossId)
	if part then
		decorateBoss(part, boss.Name)
	end

	active = {
		bossId = bossId,
		fight = fight,
		summonTimer = fight.SummonEvery,
		pulseTimer = fight.PulseEvery,
		warningLeft = nil,
	}
end

-- Every frame during the fight: HP bar, summons and pulses.
local function update(deltaTime: number)
	local current = active
	if not current or RunManager.isPaused() or RunManager.isRunOver() then
		return
	end
	local bossPosition = EnemyService.getEnemyPosition(current.bossId)
	if not bossPosition then
		return -- the boss just died; onEnemyKilled ends the fight
	end
	local fight = current.fight

	local hp, maxHp = EnemyService.getEnemyHp(current.bossId)
	if hpFill and hp and maxHp then
		hpFill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
	end

	-- Summon minions around the boss.
	current.summonTimer -= deltaTime
	if current.summonTimer <= 0 then
		current.summonTimer = fight.SummonEvery
		for _ = 1, fight.SummonCount do
			local angle = random:NextNumber(0, 2 * math.pi)
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(6, 9)
			EnemyService.spawn(fight.SummonEnemy, bossPosition + offset)
		end
	end

	-- Damage pulse: warn first (a growing ring), then hit.
	local floorPosition = Vector3.new(bossPosition.X, getMapBounds().Y, bossPosition.Z)
	local warningLeft = current.warningLeft
	if warningLeft then
		warningLeft -= deltaTime
		if warningLeft > 0 then
			current.warningLeft = warningLeft
			local progress = 1 - warningLeft / fight.PulseWarning
			showPulse(floorPosition, fight.PulseRadius * progress, COLORS.pulseWarning)
		else
			current.warningLeft = nil
			current.pulseTimer = fight.PulseEvery
			showPulse(floorPosition, fight.PulseRadius, COLORS.pulseHit)
			task.delay(0.15, hidePulse) -- a short red flash, purely visual
			local root = getChefRoot()
			if root and (flat(root.Position) - flat(bossPosition)).Magnitude <= fight.PulseRadius + CHEF_RADIUS then
				RunManager.damagePlayer(fight.PulseDamage, "BossPulse")
			end
		end
	else
		current.pulseTimer -= deltaTime
		if current.pulseTimer <= 0 then
			current.warningLeft = fight.PulseWarning
		end
	end
end

-- End any boss fight without a winner (a new run is starting, #50): forget the fight,
-- take down the ring and its walls, and let enemies roam the whole kitchen again.
-- The boss itself is an enemy: RestartService removes it with EnemyService.clearAll().
function BossService.reset()
	active = nil
	hpFill = nil
	hidePulse()
	EnemyService.setBossArena(nil, 0)
	local ring = workspace:FindFirstChild("BossRing")
	if ring then
		ring:Destroy()
	end
end

function BossService:init()
	pulsePart = Instance.new("Part")
	pulsePart.Name = "BossPulse"
	pulsePart.Shape = Enum.PartType.Cylinder
	pulsePart.Anchored = true
	pulsePart.CanCollide = false
	pulsePart.CanQuery = false
	pulsePart.CanTouch = false
	pulsePart.CastShadow = false
	pulsePart.Material = Enum.Material.Neon
	pulsePart.Transparency = 0.55
	pulsePart.Parent = workspace
	hidePulse()
end

function BossService:start()
	RunManager.onFinalBoss(startFight)

	-- The boss is defeated: the chapter is cleared.
	EnemyService.onEnemyKilled(function(enemyId)
		if active and enemyId == active.bossId then
			active = nil
			hpFill = nil
			hidePulse()
			RunManager.winRun()
		end
	end)

	RunService.Heartbeat:Connect(update)
end

return BossService
