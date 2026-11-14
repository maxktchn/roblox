--!strict
-- Fixed angled overhead (3/4) camera; no rotate or zoom during a run (PRD §2.2).
--
-- How it works: every frame, right after Roblox's own camera code, we put the camera
-- at a fixed offset above and behind the chef, looking down at them. The camera is
-- "Scriptable", so Roblox ignores mouse/touch rotate and zoom input.
-- Because the camera never turns, "up" on the thumbstick or W is always "up the screen".

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

local function update()
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
	camera.CFrame = CFrame.lookAt(target + OFFSET, target)
end

function CameraController:init() end

function CameraController:start()
	-- Camera priority + 1 = run just after Roblox's default camera, so ours wins.
	RunService:BindToRenderStep("KitchenCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
