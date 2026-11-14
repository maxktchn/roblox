--!strict
-- Aiming the starter weapon (PRD §2.2, #61). Works out where the player is aiming, as a flat
-- direction on the floor from the chef, and sends it to the server (AimDirection). The server
-- validates it and decides every hit (WeaponService); this only says which way.
--
--   PC:      toward the mouse cursor (a ray from the camera through the cursor onto the floor)
--   Gamepad: the right thumbstick
--   Mobile:  the aim stick (#62) calls AimController.setAimFromStick
-- Whichever input was used last does the aiming. With no input, the last aim stays.
--
-- Sending: when the aim turns more than SEND_ANGLE_DEGREES, at most
-- RunRules.AimMessagesPerSecond times a second. The aim is also re-sent every RESEND_SECONDS
-- while aiming, because the unreliable remote can drop a message: if the last one were lost,
-- the server would keep an old aim.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunRules = require(ReplicatedStorage.Config.RunRules)

local AimController = {}

local player = Players.LocalPlayer

local STICK_DEAD_ZONE_PIXELS = 10 -- mobile aim stick: ignore tiny drags near the centre
local GAMEPAD_DEAD_ZONE = 0.3 -- gamepad right stick: 0 to 1
local SEND_ANGLE_DEGREES = 2 -- send when the aim has turned at least this much
local RESEND_SECONDS = 0.5 -- re-send the current aim this often, in case one was dropped

local aimRemote: UnreliableRemoteEvent
local aim: Vector3? = nil -- latest flat unit aim, or nil before the player has aimed
local usingMouse = false -- the last input was the mouse or keyboard
local lastSent: Vector3? = nil
local lastSendTime = 0
local sentCount = 0 -- messages sent so far (for tests)

local function getRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Set the aim from a flat direction. Ignores anything too short to have a direction.
local function setAim(direction: Vector3)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude > 0.001 then
		aim = flat.Unit
	end
end

-- The player's latest aim (flat unit vector), or nil before they've aimed. The aim indicator
-- (#62) draws from this, so it follows the aim instantly without waiting for the server.
function AimController.getAim(): Vector3?
	return aim
end

-- Mobile aim stick (#62): `offset` is how far the knob is from the stick's centre, in screen
-- pixels (+X right, +Y down). The camera is fixed and looks toward -Z, so screen right is
-- world +X and screen down is world +Z: the offset maps straight onto the floor.
function AimController.setAimFromStick(offset: Vector2)
	if offset.Magnitude < STICK_DEAD_ZONE_PIXELS then
		return
	end
	usingMouse = false
	setAim(Vector3.new(offset.X, 0, offset.Y))
end

-- Aim at where a ray (e.g. from the camera through the mouse) meets the floor under the chef.
-- Leaves the aim unchanged if the ray never reaches that floor height or there is no chef.
function AimController.aimAtRay(origin: Vector3, direction: Vector3)
	local root = getRoot()
	if not root or direction.Y >= -0.001 then
		return -- no chef, or the ray points level or up: it never meets the floor
	end
	local distance = (root.Position.Y - origin.Y) / direction.Y
	if distance <= 0 or distance ~= distance then
		return -- the floor is behind the camera (or the maths went NaN)
	end
	local hit = origin + direction * distance
	setAim(hit - root.Position)
end

-- How many aim messages this client has sent (for tests).
function AimController.getSentCount(): number
	return sentCount
end

-- Send the aim if it turned enough (rate-limited), or re-send it every RESEND_SECONDS.
local function sendIfNeeded()
	local current = aim
	if not current then
		return
	end
	local now = os.clock()
	local sinceLast = now - lastSendTime
	if sinceLast < 1 / RunRules.AimMessagesPerSecond then
		return
	end
	local turned = not lastSent or math.deg(math.acos(math.clamp(current:Dot(lastSent), -1, 1))) > SEND_ANGLE_DEGREES
	if turned or sinceLast >= RESEND_SECONDS then
		aimRemote:FireServer(current.X, current.Z)
		lastSent = current
		lastSendTime = now
		sentCount += 1
	end
end

local function update()
	if usingMouse then
		local camera = workspace.CurrentCamera
		if camera then
			local mouse = UserInputService:GetMouseLocation()
			local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
			AimController.aimAtRay(ray.Origin, ray.Direction)
		end
	end
	sendIfNeeded()
end

local MOUSE_INPUTS = {
	[Enum.UserInputType.MouseMovement] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseWheel] = true,
	[Enum.UserInputType.Keyboard] = true,
}

function AimController:start()
	aimRemote = Remotes.getUnreliable("AimDirection")

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		if MOUSE_INPUTS[inputType] then
			usingMouse = true
		elseif inputType == Enum.UserInputType.Touch or string.find(inputType.Name, "Gamepad") then
			usingMouse = false
		end
	end)
	usingMouse = MOUSE_INPUTS[UserInputService:GetLastInputType()] == true

	-- Gamepad right stick.
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local stick = Vector2.new(input.Position.X, input.Position.Y)
			if stick.Magnitude > GAMEPAD_DEAD_ZONE then
				usingMouse = false
				-- Stick up is screen up, which is world -Z with the fixed camera.
				setAim(Vector3.new(stick.X, 0, -stick.Y))
			end
		end
	end)

	-- A new chef (start of a run, Play again): forget the old aim until the player aims again.
	player.CharacterAdded:Connect(function()
		aim = nil
		lastSent = nil
	end)

	RunService.RenderStepped:Connect(update)
end

return AimController
