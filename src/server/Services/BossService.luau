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
--   4. Two HP phases (#91). Phase 1 is step 3. Below Fight.Phase2At of its HP the boss stops
--      and flashes (PhaseChangeSeconds), its HP bar turns orange, and it starts taking turns:
--        Laser turn:   runs to the middle of the ring (LaserWalkSpeed) and stands there for
--                      LaserSeconds, firing spinning lasers (#93, LaserService). No pulses
--                      and no new minions; it can still be hurt.
--        Walking turn: phase 1 again for WalkingSeconds.
--      Laser, walking, laser, walking... until it dies.
--      Homing popcorn (#92, PopcornService): in phase 1 and the walking turns, every
--      PopcornEvery seconds its door glows for PopcornWarning seconds, then a kernel flies out.
--   5. When it dies, the run is won.
--
-- The boss's part carries the attribute "BossStage" ("Phase1", "PhaseChange", "Laser" or
-- "Walking") so the client (and the playtest bot) can see what it is doing.
-- Normal spawns stay off during the fight because the timeline has ended.
-- Everything stands still while the run is paused ("Order Up!").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BossHpBar = require(script.Parent.Parent.BossHpBar)
local Bosses = require(ReplicatedStorage.Config.Bosses)
local Chapters = require(ReplicatedStorage.Config.Chapters)
local EnemyService = require(script.Parent.EnemyService)
local LaserService = require(script.Parent.LaserService)
local PopcornService = require(script.Parent.PopcornService)
local RunManager = require(script.Parent.RunManager)
local RunRules = require(ReplicatedStorage.Config.RunRules)

local BossService = {}

local CHEF_RADIUS = RunRules.ChefRadius -- how far the chef's body reaches
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
	flash = Color3.new(1, 1, 1),
	phase2Bar = Color3.fromRGB(255, 140, 30), -- HP bar in phase 2 (phase 1 uses BossHpBar's red)
	phase2Display = Color3.fromRGB(255, 90, 50),
	phase2Glow = Color3.fromRGB(255, 120, 40),
	doorGlow = Color3.fromRGB(255, 255, 230), -- the window lights up before popcorn flies out
	doorDisplay = Color3.fromRGB(255, 240, 120),
}

-- Within this many studs of the middle counts as arrived for a laser turn.
local ARRIVE_DISTANCE = 1
-- If minions keep it from reaching the middle, start the laser turn anyway after this long.
local MAX_WALK_TO_MIDDLE_SECONDS = 5
-- Phase change flash: white and back, FLASH_REPEATS + 1 times.
local FLASH_SECONDS = 0.15
local FLASH_REPEATS = 2

export type Stage = "Phase1" | "PhaseChange" | "Laser" | "Walking"

type ActiveFight = {
	bossId: number,
	fight: Bosses.BossFight,
	center: Vector3, -- middle of the ring (on the floor)
	stage: Stage,
	stageTimer: number, -- PhaseChange, Laser (once arrived) and Walking: seconds left in the stage
	arrived: boolean, -- Laser: reached the middle (the laser turn's clock has started)
	summonTimer: number, -- seconds until the next summon
	pulseTimer: number, -- seconds until the next pulse warning starts
	warningLeft: number?, -- while a pulse is warning: seconds until it hits
	popcornTimer: number, -- seconds until the door starts glowing for the next kernel
	doorLeft: number?, -- while the door glows: seconds until the kernel flies out
}

local active: ActiveFight? = nil

-- This run's fight so far, for the run report (#94). Kept after the boss dies; reset() clears it.
export type FightStats = {
	seconds: number, -- fight length so far (paused time doesn't count)
	phase2At: number?, -- seconds into the fight when phase 2 started
	laserTurns: number, -- laser turns where the lasers fired
	over: boolean, -- the boss is dead
}
local stats: FightStats? = nil
local pulsePart: Part
local hpFill: Frame? = nil
local display: TextLabel? = nil -- the microwave's little screen ("DING")
local glow: Frame? = nil -- the light in its window
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
local function decorateBoss(part: BasePart, bossName: string, color: Color3)
	part.Color = color -- a pooled part may still be mid-flash from a past fight
	local oldFace = part:FindFirstChild("MicrowaveFace")
	if oldFace then
		oldFace:Destroy()
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
	local windowGlow = Instance.new("Frame")
	windowGlow.Name = "Glow"
	windowGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	windowGlow.Position = UDim2.fromScale(0.5, 0.55)
	windowGlow.Size = UDim2.fromScale(0.7, 0.5)
	windowGlow.BackgroundColor3 = COLORS.windowGlow
	windowGlow.BackgroundTransparency = 0.55
	windowGlow.BorderSizePixel = 0
	windowGlow.Parent = window
	glow = windowGlow

	local screen = Instance.new("TextLabel")
	screen.Name = "Display"
	screen.Position = UDim2.fromScale(0.74, 0.15)
	screen.Size = UDim2.fromScale(0.2, 0.18)
	screen.BackgroundColor3 = COLORS.window
	screen.BorderSizePixel = 0
	screen.Font = Enum.Font.Code
	screen.Text = "DING"
	screen.TextScaled = true
	screen.TextColor3 = COLORS.display
	screen.Parent = face
	display = screen

	hpFill = BossHpBar.attach(part, bossName)
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
		decorateBoss(part, boss.Name, boss.Body.Color)
		part:SetAttribute("BossStage", "Phase1")
	end

	stats = { seconds = 0, phase2At = nil, laserTurns = 0, over = false }
	active = {
		bossId = bossId,
		fight = fight,
		center = center,
		stage = "Phase1",
		stageTimer = 0,
		arrived = false,
		summonTimer = fight.SummonEvery,
		pulseTimer = fight.PulseEvery,
		popcornTimer = fight.PopcornEvery,
		doorLeft = nil,
		warningLeft = nil,
	}
end

-- Move the fight to `stage` and show it on the boss's part.
local function setStage(current: ActiveFight, stage: Stage)
	current.stage = stage
	local part = EnemyService.getEnemyPart(current.bossId)
	if part then
		part:SetAttribute("BossStage", stage)
	end
end

-- The microwave's face for the current phase: DING in phase 1, HOT! in phase 2, and POP!
-- with a bright window while popcorn is about to fly out.
local function updateFace(current: ActiveFight)
	local phase2 = current.stage ~= "Phase1"
	if display then
		if current.doorLeft then
			display.Text = "POP!"
			display.TextColor3 = COLORS.doorDisplay
		else
			display.Text = if phase2 then "HOT!" else "DING"
			display.TextColor3 = if phase2 then COLORS.phase2Display else COLORS.display
		end
	end
	if glow then
		if current.doorLeft then
			glow.BackgroundColor3 = COLORS.doorGlow
			glow.BackgroundTransparency = 0
		else
			glow.BackgroundColor3 = if phase2 then COLORS.phase2Glow else COLORS.windowGlow
			glow.BackgroundTransparency = if phase2 then 0.25 else 0.55
		end
	end
end

-- Stop a pulse or popcorn that is still warning (they don't happen now). Used whenever the
-- boss stops attacking (phase change, laser turn). The countdowns just wait meanwhile (they
-- only run in updateAttacks), so walking turns shorter than PopcornEvery still get popcorn.
-- A cancelled one starts its warning again as soon as the boss attacks again.
local function cancelWarnings(current: ActiveFight)
	if current.warningLeft then
		current.warningLeft = nil
		current.pulseTimer = 0
	end
	if current.doorLeft then
		current.doorLeft = nil
		current.popcornTimer = 0
	end
	hidePulse()
	updateFace(current)
end

-- Phase 2 starts: the boss stops and flashes, its bar turns orange and its screen says HOT!
local function startPhaseChange(current: ActiveFight)
	setStage(current, "PhaseChange")
	if stats then
		stats.phase2At = stats.seconds
	end
	current.stageTimer = current.fight.PhaseChangeSeconds
	cancelWarnings(current) -- also switches the face to HOT!
	EnemyService.setMoveTarget(current.bossId, EnemyService.getEnemyPosition(current.bossId), 0)

	local part = EnemyService.getEnemyPart(current.bossId)
	if part then
		local flash =
			TweenInfo.new(FLASH_SECONDS, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, FLASH_REPEATS, true)
		TweenService:Create(part, flash, { Color = COLORS.flash }):Play()
	end
	if hpFill then
		hpFill.BackgroundColor3 = COLORS.phase2Bar
	end
end

-- Laser turn: run to the middle of the ring. Its clock starts once it gets there.
local function startLaserTurn(current: ActiveFight)
	setStage(current, "Laser")
	current.arrived = false
	current.stageTimer = MAX_WALK_TO_MIDDLE_SECONDS -- until it arrives: how long it may take
	cancelWarnings(current)
	EnemyService.setMoveTarget(current.bossId, current.center, current.fight.LaserWalkSpeed)
end

-- Walking turn: back to phase 1 behaviour for a while.
local function startWalkingTurn(current: ActiveFight)
	setStage(current, "Walking")
	current.stageTimer = current.fight.WalkingSeconds
	LaserService.turnOff()
	EnemyService.setMoveTarget(current.bossId, nil)
end

-- Fire one popcorn kernel out of the microwave's door (its front), toward the chef.
local function firePopcorn(current: ActiveFight, bossPosition: Vector3)
	local fight = current.fight
	local part = EnemyService.getEnemyPart(current.bossId)
	local bossType = EnemyService.getEnemyType(current.bossId)
	local body = bossType and EnemyService.getConfigForType(bossType)
	local kernel = EnemyService.getConfigForType(fight.PopcornEnemy)
	local front = Vector3.new(0, 0, -1)
	if part then
		local look = part.CFrame.LookVector
		front = Vector3.new(look.X, 0, look.Z)
		front = if front.Magnitude > 0.01 then front.Unit else Vector3.new(0, 0, -1)
	end
	local gap = (if body then EnemyService.getHalfDepth(body) else 3)
		+ (if kernel then EnemyService.getHalfDepth(kernel) else 1)
		+ 0.5
	PopcornService.fire(bossPosition + front * gap, fight)
end

-- Phase 1 behaviour (and the walking turn): summon minions, send out damage pulses and fire popcorn.
local function updateAttacks(current: ActiveFight, bossPosition: Vector3, deltaTime: number)
	local fight = current.fight

	-- Popcorn: the door glows (the warning), then a kernel flies out.
	local doorLeft = current.doorLeft
	if doorLeft then
		doorLeft -= deltaTime
		if doorLeft > 0 then
			current.doorLeft = doorLeft
		else
			current.doorLeft = nil
			current.popcornTimer = fight.PopcornEvery
			updateFace(current)
			firePopcorn(current, bossPosition)
		end
	else
		current.popcornTimer -= deltaTime
		if current.popcornTimer <= 0 then
			current.doorLeft = fight.PopcornWarning
			updateFace(current)
		end
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

-- Every frame during the fight: HP bar, phases and turns, summons and pulses.
local function update(deltaTime: number)
	local current = active
	if not current or RunManager.isPaused() or RunManager.isRunOver() then
		return
	end
	if stats then
		stats.seconds += deltaTime
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

	if current.stage == "Phase1" then
		if hp and maxHp and hp <= maxHp * fight.Phase2At then
			startPhaseChange(current)
			return
		end
		updateAttacks(current, bossPosition, deltaTime)
	elseif current.stage == "PhaseChange" then
		current.stageTimer -= deltaTime
		if current.stageTimer <= 0 then
			startLaserTurn(current)
		end
	elseif current.stage == "Laser" then
		current.stageTimer -= deltaTime
		if not current.arrived then
			local toMiddle = flat(current.center) - flat(bossPosition)
			-- The chef standing on the middle blocks it: it waits at their edge, and walks in
			-- once they move (its target stays the middle for the whole laser turn).
			local blocked = false
			local root = getChefRoot()
			local bossType = EnemyService.getEnemyType(current.bossId)
			local body = bossType and EnemyService.getConfigForType(bossType)
			if root and body then
				local stopDistance = CHEF_RADIUS + EnemyService.getHalfDepth(body)
				local chefToMiddle = (flat(root.Position) - flat(current.center)).Magnitude
				local bossToChef = (flat(root.Position) - flat(bossPosition)).Magnitude
				blocked = chefToMiddle < stopDistance and bossToChef <= stopDistance + ARRIVE_DISTANCE
			end
			if toMiddle.Magnitude <= ARRIVE_DISTANCE or blocked or current.stageTimer <= 0 then
				-- In the middle (or as close as the chef lets it): stand there for LaserSeconds,
				-- walking back if minions shove it, and fire the spinning lasers (#93). They reach
				-- the counters' inner face.
				current.arrived = true
				current.stageTimer = fight.LaserSeconds
				if stats then
					stats.laserTurns += 1
				end
				LaserService.turnOn(current.bossId, current.center, fight.ArenaRadius - COUNTER_DEPTH / 2, fight)
			end
		elseif current.stageTimer <= 0 then
			startWalkingTurn(current)
		end
	elseif current.stage == "Walking" then
		updateAttacks(current, bossPosition, deltaTime)
		current.stageTimer -= deltaTime
		if current.stageTimer <= 0 then
			startLaserTurn(current)
		end
	end
end

-- What the final boss is doing right now, or nil when there is no fight (tests, DEV tools).
function BossService.getStage(): Stage?
	return if active then active.stage else nil
end

-- This run's final boss fight so far (a copy), or nil if it hasn't started. For the run report.
function BossService.getFightStats(): FightStats?
	return if stats then table.clone(stats) else nil
end

-- End any boss fight without a winner (a new run is starting, #50): forget the fight,
-- take down the ring and its walls, and let enemies roam the whole kitchen again.
-- The boss itself is an enemy: RestartService removes it with EnemyService.clearAll().
function BossService.reset()
	active = nil
	stats = nil
	BossHpBar.remove(hpFill)
	hpFill = nil
	display = nil
	glow = nil
	hidePulse()
	PopcornService.reset()
	LaserService.turnOff()
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
			if stats then
				stats.over = true
			end
			active = nil
			BossHpBar.remove(hpFill)
			hpFill = nil
			display = nil
			glow = nil
			hidePulse()
			PopcornService.reset()
			LaserService.turnOff()
			RunManager.winRun()
		end
	end)

	RunService.Heartbeat:Connect(update)
end

return BossService
