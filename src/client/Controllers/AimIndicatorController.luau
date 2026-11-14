--!strict
-- Aim indicator (PRD §2.2, #62): a faint fan on the floor showing where the starter weapon's
-- next swing will land. Spokes spread across the weapon's arc, each as long as its reach, in
-- the weapon's colour. It follows the local aim (AimController) every frame, so it feels
-- instant even though the server uses the aim a moment later. Before the player has aimed it
-- points the way the chef faces, matching the server.
-- Hidden while the "Order Up!" cards are open, after the run ends, and with no chef.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AimController = require(script.Parent.AimController)
local Recipes = require(ReplicatedStorage.Config.Recipes)
local Starters = require(ReplicatedStorage.Config.Starters)

local AimIndicatorController = {}

local player = Players.LocalPlayer

local SPOKES = 5 -- lines across the arc
local SPOKE_WIDTH = 0.25 -- studs
local TRANSPARENCY = 0.75
local FLOOR_OFFSET = 2.9 -- studs below the chef's root: just above the floor

local folder: Folder
local spokes: { Part } = {}

-- Every aimed weapon (the starter and its recipe), found once at load.
type AimedWeapon = { id: string, config: any }
local aimedWeapons: { AimedWeapon } = {}
for id, starter in Starters do
	if starter.Aimed then
		table.insert(aimedWeapons, { id = id, config = starter })
	end
end
for id, recipe in Recipes do
	if recipe.Aimed then
		table.insert(aimedWeapons, { id = id, config = recipe })
	end
end

-- The aimed weapon the player owns right now, with its numbers at its current level.
local function getAimedWeapon(): (any, any)
	for _, weapon in aimedWeapons do
		local level = player:GetAttribute(`Weapon_{weapon.id}`)
		local levels = weapon.config.Levels
		if type(level) == "number" and levels and levels[level] then
			return weapon.config, levels[level]
		end
	end
	return nil, nil
end

local function buildSpokes()
	folder = Instance.new("Folder")
	folder.Name = "AimIndicator"
	for i = 1, SPOKES do
		local spoke = Instance.new("Part")
		spoke.Name = `Spoke{i}`
		spoke.Anchored = true
		spoke.CanCollide = false
		spoke.CanQuery = false
		spoke.CanTouch = false
		spoke.CastShadow = false
		spoke.Material = Enum.Material.Neon
		spoke.Transparency = 1
		spoke.Parent = folder
		spokes[i] = spoke
	end
	folder.Parent = workspace
end

local function hide()
	for _, spoke in spokes do
		spoke.Transparency = 1
	end
end

local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local orderUp = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("OrderUp")
	local cardsOpen = orderUp ~= nil and orderUp:IsA("ScreenGui") and orderUp.Enabled
	local playing = player:GetAttribute("RunState") ~= "Lost" and player:GetAttribute("RunState") ~= "Won"
	local config, stats = getAimedWeapon()
	if not (root and root:IsA("BasePart") and config and stats and playing) or cardsOpen then
		hide()
		return
	end

	-- Same direction the server uses: the aim, or the chef's facing before the first aim.
	local look = root.CFrame.LookVector
	local direction: Vector3 = AimController.getAim() or Vector3.new(look.X, 0, look.Z).Unit
	local range = stats.Range
	local halfArc = math.rad((stats.ArcDegrees or 90) / 2)
	local origin = root.Position - Vector3.new(0, FLOOR_OFFSET, 0)
	local color = config.FxColor or Color3.new(1, 1, 1)

	for i, spoke in spokes do
		-- Spread the spokes evenly from one edge of the arc to the other.
		local angle = -halfArc + (2 * halfArc) * (i - 1) / (SPOKES - 1)
		local spokeDirection = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(direction)
		spoke.Size = Vector3.new(SPOKE_WIDTH, 0.05, range)
		spoke.CFrame = CFrame.lookAt(origin + spokeDirection * (range / 2), origin + spokeDirection * range)
		spoke.Color = color
		spoke.Transparency = TRANSPARENCY
	end
end

function AimIndicatorController:init()
	buildSpokes()
end

function AimIndicatorController:start()
	RunService.RenderStepped:Connect(update)
end

return AimIndicatorController
