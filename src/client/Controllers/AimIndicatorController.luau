--!strict
-- Aim indicator (PRD §2.2, #62): a thin orange curved line (an arc, like a "U" opening toward
-- the player) a short fixed distance in front of the chef, at about the height the starter's
-- slash is drawn (so the two line up), centred on the direction they're aiming. It doesn't
-- depend on any weapon's shape or reach, so it works for every aimed weapon, now and later.
-- It follows the local aim (AimController) every frame, so it feels instant even though the
-- server uses the aim a moment later. Before the player has aimed it sits the way the chef
-- faces, matching the server.
-- Shown only while the player owns an aimed weapon (otherwise aiming does nothing).
-- Hidden while the "Order Up!" cards are open, after the run ends, and with no chef.
--
-- How it's drawn: a flat, invisible panel lies around the chef, turned to face the aim. On its
-- top face a SurfaceGui draws a circle outline (a round Frame with a UIStroke) and crops it so
-- only the front slice shows. UI drawing is smooth and isn't lit, so the curve has no seams and
-- stays exactly orange. (Arcs built from 3D pieces showed dark lines where pieces met.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AimController = require(script.Parent.AimController)
local Recipes = require(ReplicatedStorage.Config.Recipes)
local Starters = require(ReplicatedStorage.Config.Starters)

local AimIndicatorController = {}

local player = Players.LocalPlayer

local RADIUS = 4 -- studs from the chef's centre to the arc
local ARC_DEGREES = 50 -- how wide the arc is
local THICKNESS = 0.3 -- studs
local COLOR = Color3.fromRGB(255, 140, 40) -- orange: easy to see on the white floor
local TRANSPARENCY = 0.15 -- fairly solid, so the orange stays strong on the white floor
-- Studs below the chef's root. The knife's slash is drawn at the root's height, so this keeps
-- the arc just under it, lined up with the swing instead of down on the floor.
local HEIGHT_BELOW_ROOT = 0.5
local PIXELS_PER_STUD = 60 -- drawing resolution: higher = crisper edges

local panel: Part
local gui: SurfaceGui

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

local function buildArc()
	-- The panel is a square around the chef, big enough for the whole circle plus its stroke.
	local size = 2 * (RADIUS + THICKNESS)
	panel = Instance.new("Part")
	panel.Name = "AimIndicator"
	panel.Size = Vector3.new(size, 0.05, size)
	panel.Anchored = true
	panel.CanCollide = false
	panel.CanQuery = false
	panel.CanTouch = false
	panel.CastShadow = false
	panel.Transparency = 1

	gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0 -- the same orange whatever the lighting
	gui.Enabled = false
	gui.Parent = panel

	local px = PIXELS_PER_STUD
	-- Crop: keep only the strip of the panel in front of where the arc's ends are, so just a
	-- 50° slice of the circle shows. The top of the drawing is turned toward the aim (update).
	local cutFromTop = size / 2 - RADIUS * math.cos(math.rad(ARC_DEGREES) / 2)
	local crop = Instance.new("Frame")
	crop.Name = "Crop"
	crop.BackgroundTransparency = 1
	crop.ClipsDescendants = true
	crop.Position = UDim2.fromOffset(0, 0)
	crop.Size = UDim2.fromOffset(size * px, cutFromTop * px)
	crop.Parent = gui

	-- The full circle (only its top slice is inside the crop). The stroke is centred on the
	-- circle's edge, so the circle's diameter is the arc's diameter.
	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.BackgroundTransparency = 1
	circle.Position = UDim2.fromOffset((size / 2 - RADIUS) * px, (size / 2 - RADIUS) * px)
	circle.Size = UDim2.fromOffset(2 * RADIUS * px, 2 * RADIUS * px)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = circle
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR
	stroke.Transparency = TRANSPARENCY
	stroke.Thickness = THICKNESS * px
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = circle
	circle.Parent = crop

	panel.Parent = workspace
end

local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local orderUp = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("OrderUp")
	local cardsOpen = orderUp ~= nil and orderUp:IsA("ScreenGui") and orderUp.Enabled
	local runState = player:GetAttribute("RunState")
	local playing = runState == "Playing" -- not in the lobby, not after the run
	if not (root and root:IsA("BasePart") and playing and ownsAimedWeapon()) or cardsOpen then
		gui.Enabled = false
		return
	end

	-- Same direction the server uses: the aim, or the chef's facing before the first aim.
	local look = root.CFrame.LookVector
	local direction: Vector3 = AimController.getAim() or Vector3.new(look.X, 0, look.Z).Unit
	local centre = root.Position - Vector3.new(0, HEIGHT_BELOW_ROOT, 0)
	-- The top edge of a Top-face SurfaceGui points along the panel's -X axis, so turn the panel
	-- until -X is the aim: that puts the drawing's top, where the arc is, toward the aim.
	panel.CFrame = CFrame.fromMatrix(centre, -direction, Vector3.yAxis)
	gui.Enabled = true
end

function AimIndicatorController:init()
	buildArc()
end

function AimIndicatorController:start()
	RunService.RenderStepped:Connect(update)
end

return AimIndicatorController
