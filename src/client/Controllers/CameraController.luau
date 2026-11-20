--!strict
-- Fixed angled overhead (3/4) camera; no rotate or zoom during a run (PRD §2.2).
--
-- How it works: every frame, right after Roblox's own camera code, we put the camera
-- at a fixed offset above and behind the chef, looking down at them. The camera is
-- "Scriptable", so Roblox ignores mouse/touch rotate and zoom input.
-- Because the camera never turns, "up" on the thumbstick or W is always "up the screen".
--
-- Screen shake: when the final boss enters phase 2 (its part's "BossStage" attribute becomes
-- "PhaseChange", set by BossService, #91) the camera shakes a little for a moment.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RunRules = require(ReplicatedStorage.Config.RunRules)

local CameraController = {}

local player = Players.LocalPlayer

-- Where the camera sits relative to the chef. Pitch 90 would be straight down;
-- lower pitch shows more of the side of things. Worked out once, it never changes.
local pitch = math.rad(RunRules.CameraPitchDegrees)
local OFFSET = Vector3.new(0, math.sin(pitch), math.cos(pitch)) * RunRules.CameraDistance

-- Screen shake (cosmetic only). Kept small so it reads as a hit, not motion sickness on a phone.
local SHAKE_SECONDS = 0.3
local SHAKE_STUDS = 0.6 -- biggest sideways/up-down nudge, at the start; it fades to 0
local shakeLeft = 0 -- seconds of shake still to go
local random = Random.new()

local function startShake()
	shakeLeft = SHAKE_SECONDS
end

-- A small random nudge for this frame, smaller as the shake runs out. Zero when not shaking.
local function shakeOffset(deltaTime: number): Vector3
	if shakeLeft <= 0 then
		return Vector3.zero
	end
	shakeLeft -= deltaTime
	local strength = SHAKE_STUDS * math.max(shakeLeft / SHAKE_SECONDS, 0)
	return Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1), 0) * strength
end

-- Enemy parts are pooled and reused, so watch each one once, for its whole life.
local function watchEnemyPart(part: Instance)
	part:GetAttributeChangedSignal("BossStage"):Connect(function()
		if part:GetAttribute("BossStage") == "PhaseChange" then
			startShake()
		end
	end)
end

-- The lobby's camera (P2-8 #144): nil = the run camera above; "Home" = the same overhead view
-- (LobbyController blurs it); "Gear" = in front of the chef, who sits on the left of the screen
-- so the Gear panel fits on the right.
export type LobbyView = "Home" | "Gear"
local lobbyView: LobbyView? = nil
local GEAR_VIEW_DISTANCE = 9 -- studs in front of the chef
local GEAR_VIEW_HEIGHT = 2.5 -- studs above the chef's middle
local GEAR_VIEW_SIDESTEP = 4 -- studs the camera moves right, which puts the chef left of centre

function CameraController.setLobbyView(view: LobbyView?)
	lobbyView = view
end

local function update(deltaTime: number)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (camera and root and root:IsA("BasePart")) then
		return -- no chef yet (loading or respawning): leave the camera where it is
	end

	-- Roblox's camera scripts can switch this back (e.g. on respawn), so set it every frame.
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = RunRules.CameraFieldOfView

	local target = root.Position
	if lobbyView == "Gear" then
		local eye = target + root.CFrame.LookVector * GEAR_VIEW_DISTANCE + Vector3.new(0, GEAR_VIEW_HEIGHT, 0)
		camera.CFrame = CFrame.lookAt(eye, target) * CFrame.new(GEAR_VIEW_SIDESTEP, 0, 0)
		return
	end
	-- The shake moves the camera without turning it (applied in the camera's own space).
	camera.CFrame = CFrame.lookAt(target + OFFSET, target) * CFrame.new(shakeOffset(deltaTime))
end

function CameraController:init() end

function CameraController:start()
	-- Camera priority + 1 = run just after Roblox's default camera, so ours wins.
	RunService:BindToRenderStep("KitchenCamera", Enum.RenderPriority.Camera.Value + 1, update)

	-- The server makes workspace.Enemies when it boots; wait for it without holding up start.
	task.spawn(function()
		local enemies = workspace:WaitForChild("Enemies")
		for _, part in enemies:GetChildren() do
			watchEnemyPart(part)
		end
		enemies.ChildAdded:Connect(watchEnemyPart)
	end)
end

return CameraController
