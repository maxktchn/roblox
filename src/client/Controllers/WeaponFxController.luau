--!strict
-- Draws weapon attack effects when the server says a weapon fired (WeaponFx remote).
-- Visual only: damage was already decided on the server.
--
-- Effects reuse the same parts instead of creating new ones each attack (PRD §8.3).
-- New weapons add a function here and a line in EFFECTS.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local WeaponFxController = {}

local player = Players.LocalPlayer

local SLASH_SECONDS = 0.15 -- how long the blade takes to sweep across the arc
local FADE_SECONDS = 0.1 -- then it fades out over this long

local slashPart: Part
local slashToken = 0 -- bumped each slash so an old animation stops if a new one starts

local function getRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Chef's Knife: a thin white blade that sweeps across the arc in front of the chef.
local function slash(facing: Vector3, range: number, arcDegrees: number)
	slashToken += 1
	local myToken = slashToken
	local halfArc = math.rad(arcDegrees / 2)
	local started = os.clock()
	slashPart.Size = Vector3.new(0.4, 0.2, range)

	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local root = getRoot()
		local elapsed = os.clock() - started
		if myToken ~= slashToken or not root or elapsed > SLASH_SECONDS + FADE_SECONDS then
			if myToken == slashToken then
				slashPart.Transparency = 1
			end
			connection:Disconnect()
			return
		end

		-- Sweep from the left edge of the arc to the right edge, then hold and fade.
		local progress = math.min(elapsed / SLASH_SECONDS, 1)
		local angle = halfArc - progress * 2 * halfArc
		local fade = math.max(elapsed - SLASH_SECONDS, 0) / FADE_SECONDS
		slashPart.Transparency = 0.2 + 0.8 * fade

		-- Start at the chef, face along `facing`, turn by `angle`, then push the
		-- blade forward by half its length so one end sits at the chef.
		local base = CFrame.lookAt(root.Position, root.Position + facing)
		slashPart.CFrame = base * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -range / 2)
	end)
end

local EFFECTS: { [string]: (facing: Vector3, range: number, arcDegrees: number) -> () } = {
	ChefsKnife = slash,
}

function WeaponFxController:init()
	-- Parts that live only on this client, so other players never see or touch them.
	slashPart = Instance.new("Part")
	slashPart.Name = "KnifeSlash"
	slashPart.Anchored = true
	slashPart.CanCollide = false
	slashPart.CanQuery = false
	slashPart.CanTouch = false
	slashPart.CastShadow = false
	slashPart.Material = Enum.Material.Neon
	slashPart.Color = Color3.fromRGB(235, 245, 255)
	slashPart.Transparency = 1
	slashPart.Parent = workspace
end

function WeaponFxController:start()
	Remotes.get("WeaponFx").OnClientEvent:Connect(function(weaponId: string, ...: any)
		local effect = EFFECTS[weaponId]
		if effect then
			effect(...)
		end
	end)
end

return WeaponFxController
