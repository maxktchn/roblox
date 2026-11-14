--!strict
-- Mobile aim stick (PRD §2.2, §7.4, #62): a thumb-sized joystick fixed in the bottom-right
-- corner. Dragging it aims the starter weapon (AimController.setAimFromStick); letting go
-- recentres the knob and keeps the last aim. Roblox's movement stick stays on the left.
-- Only shown on touch devices, while touch is the input being used.
--
-- Also hides Roblox's touch jump button: there's no jumping (PRD §2.2) and the right thumb
-- is for aiming now.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local AimController = require(script.Parent.AimController)

local AimStickController = {}

local player = Players.LocalPlayer

local BASE_SIZE = 140 -- pixels; big enough for a thumb
local KNOB_SIZE = 60
local MARGIN = 24 -- from the screen's bottom-right corner (inside the safe area)

local gui: ScreenGui
local base: Frame
local knob: Frame
local activeTouch: InputObject? = nil -- the touch dragging the stick, if any

local function circle(frame: GuiObject)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = frame
end

local function buildStick()
	gui = Instance.new("ScreenGui")
	gui.Name = "AimStick"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Enabled = false

	base = Instance.new("Frame")
	base.Name = "Base"
	base.AnchorPoint = Vector2.new(1, 1)
	base.Position = UDim2.new(1, -MARGIN, 1, -MARGIN)
	base.Size = UDim2.fromOffset(BASE_SIZE, BASE_SIZE)
	base.BackgroundColor3 = Color3.new(1, 1, 1)
	base.BackgroundTransparency = 0.75
	base.Active = true -- touches here aim; they don't also move the chef
	circle(base)
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.new(1, 1, 1)
	ring.Transparency = 0.4
	ring.Thickness = 2
	ring.Parent = base
	base.Parent = gui

	knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BackgroundTransparency = 0.3
	circle(knob)
	knob.Parent = base
end

-- Move the knob toward a screen position (clamped to the base) and aim that way.
local function dragTo(screenPosition: Vector2)
	local centre = base.AbsolutePosition + base.AbsoluteSize / 2
	local offset = screenPosition - centre
	local maxDistance = BASE_SIZE / 2
	if offset.Magnitude > maxDistance then
		offset = offset.Unit * maxDistance
	end
	knob.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
	AimController.setAimFromStick(offset)
end

local function release()
	activeTouch = nil
	knob.Position = UDim2.fromScale(0.5, 0.5) -- the aim stays where it was
end

-- Show the stick only on touch devices, while touch is the input in use.
local function updateVisible()
	gui.Enabled = UserInputService.TouchEnabled and UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

-- Hide Roblox's touch jump button whenever it appears.
local function hideJumpButton()
	local touchGui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") then
		jump.Visible = false
		jump:GetPropertyChangedSignal("Visible"):Connect(function()
			if jump.Visible then
				jump.Visible = false
			end
		end)
	end
end

function AimStickController:init()
	buildStick()
end

function AimStickController:start()
	gui.Parent = player:WaitForChild("PlayerGui")

	base.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not activeTouch then
			activeTouch = input
			dragTo(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	UserInputService.TouchMoved:Connect(function(touch)
		if touch == activeTouch then
			dragTo(Vector2.new(touch.Position.X, touch.Position.Y))
		end
	end)
	UserInputService.TouchEnded:Connect(function(touch)
		if touch == activeTouch then
			release()
		end
	end)

	updateVisible()
	UserInputService.LastInputTypeChanged:Connect(updateVisible)

	-- Roblox builds its touch controls a little after the character spawns.
	player.CharacterAdded:Connect(function()
		task.delay(1, hideJumpButton)
	end)
	task.delay(1, hideJumpButton)
end

return AimStickController
