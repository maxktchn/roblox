--!strict
-- Aim indicator (PRD §2.2, #62): a small circle on the floor, a fixed distance in front of
-- the chef in the direction they're aiming. It doesn't depend on any weapon's shape or
-- reach, so it works for every aimed weapon, now and later. It follows the local aim
-- (AimController) every frame, so it feels instant even though the server uses the aim a
-- moment later. Before the player has aimed it sits the way the chef faces, matching the server.
-- Shown only while the player owns an aimed weapon (otherwise aiming does nothing).
-- Hidden while the "Order Up!" cards are open, after the run ends, and with no chef.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AimController = require(script.Parent.AimController)
local Recipes = require(ReplicatedStorage.Config.Recipes)
local Starters = require(ReplicatedStorage.Config.Starters)

local AimIndicatorController = {}

local player = Players.LocalPlayer

local DISTANCE = 8 -- studs in front of the chef
local DIAMETER = 2.2 -- studs
local COLOR = Color3.fromRGB(255, 255, 255)
local TRANSPARENCY = 0.35
local FLOOR_OFFSET = 2.9 -- studs below the chef's root: just above the floor

local marker: Part

-- Ids of every aimed weapon (the starter and its recipe), found once at load.
local aimedIds: { string } = {}
for id, starter in Starters do
	if starter.Aimed then
		table.insert(aimedIds, id)
	end
end
for id, recipe in Recipes do
	if recipe.Aimed then
		table.insert(aimedIds, id)
	end
end

local function ownsAimedWeapon(): boolean
	for _, id in aimedIds do
		if player:GetAttribute(`Weapon_{id}`) then
			return true
		end
	end
	return false
end

local function buildMarker()
	marker = Instance.new("Part")
	marker.Name = "AimIndicator"
	marker.Shape = Enum.PartType.Cylinder
	-- A cylinder's length runs along X; it's laid flat in update().
	marker.Size = Vector3.new(0.1, DIAMETER, DIAMETER)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Material = Enum.Material.Neon
	marker.Color = COLOR
	marker.Transparency = 1
	marker.Parent = workspace
end

local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local orderUp = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("OrderUp")
	local cardsOpen = orderUp ~= nil and orderUp:IsA("ScreenGui") and orderUp.Enabled
	local runState = player:GetAttribute("RunState")
	local playing = runState ~= "Lost" and runState ~= "Won"
	if not (root and root:IsA("BasePart") and playing and ownsAimedWeapon()) or cardsOpen then
		marker.Transparency = 1
		return
	end

	-- Same direction the server uses: the aim, or the chef's facing before the first aim.
	local look = root.CFrame.LookVector
	local direction: Vector3 = AimController.getAim() or Vector3.new(look.X, 0, look.Z).Unit
	local spot = root.Position + direction * DISTANCE - Vector3.new(0, FLOOR_OFFSET, 0)
	-- Turn the cylinder on its side so it lies flat on the floor.
	marker.CFrame = CFrame.new(spot) * CFrame.Angles(0, 0, math.rad(90))
	marker.Transparency = TRANSPARENCY
end

function AimIndicatorController:init()
	buildMarker()
end

function AimIndicatorController:start()
	RunService.RenderStepped:Connect(update)
end

return AimIndicatorController
