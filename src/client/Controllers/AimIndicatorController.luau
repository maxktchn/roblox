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
-- The arc is one smooth Beam (a curved ribbon) between two attachments, so there are no
-- joins: separate overlapping pieces showed dark seams where they met.

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

local holder: Part -- invisible; moved to the chef each frame, carries the two attachments
local beam: Beam

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

-- An attachment on the arc at `angle` (radians, 0 = straight ahead), relative to the holder,
-- which faces the aim. Its X axis points along the arc (the tangent), so the Beam bends along
-- the circle. A Beam's width runs along its attachments' Y axis, so Y points outward from the
-- chef: the ribbon lies flat instead of standing on its edge.
local function arcAttachment(angle: number): Attachment
	local outward = Vector3.new(math.sin(angle), 0, -math.cos(angle))
	local position = outward * RADIUS
	local tangent = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local attachment = Instance.new("Attachment")
	attachment.CFrame = CFrame.fromMatrix(position, tangent, outward)
	attachment.Parent = holder
	return attachment
end

local function buildArc()
	holder = Instance.new("Part")
	holder.Name = "AimIndicator"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.1, 0.1, 0.1)

	local halfArc = math.rad(ARC_DEGREES) / 2
	local startAttachment = arcAttachment(-halfArc)
	local endAttachment = arcAttachment(halfArc)

	beam = Instance.new("Beam")
	beam.Attachment0 = startAttachment
	beam.Attachment1 = endAttachment
	-- A cubic curve hugs a circle when each end's handle is 4/3 * tan(arc / 4) * radius long,
	-- pointing along the arc.
	local handle = 4 / 3 * math.tan(math.rad(ARC_DEGREES) / 4) * RADIUS
	beam.CurveSize0 = handle
	beam.CurveSize1 = -handle
	beam.Segments = 24
	beam.Width0 = THICKNESS
	beam.Width1 = THICKNESS
	beam.FaceCamera = false
	beam.Color = ColorSequence.new(COLOR)
	beam.Transparency = NumberSequence.new(TRANSPARENCY)
	beam.LightInfluence = 0 -- the same orange whatever the lighting
	beam.LightEmission = 0
	beam.Enabled = false
	beam.Parent = holder

	holder.Parent = workspace
end

local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local orderUp = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("OrderUp")
	local cardsOpen = orderUp ~= nil and orderUp:IsA("ScreenGui") and orderUp.Enabled
	local runState = player:GetAttribute("RunState")
	local playing = runState ~= "Lost" and runState ~= "Won"
	if not (root and root:IsA("BasePart") and playing and ownsAimedWeapon()) or cardsOpen then
		beam.Enabled = false
		return
	end

	-- Same direction the server uses: the aim, or the chef's facing before the first aim.
	local look = root.CFrame.LookVector
	local direction: Vector3 = AimController.getAim() or Vector3.new(look.X, 0, look.Z).Unit
	local centre = root.Position - Vector3.new(0, HEIGHT_BELOW_ROOT, 0)
	holder.CFrame = CFrame.lookAt(centre, centre + direction)
	beam.Enabled = true
end

function AimIndicatorController:init()
	buildArc()
end

function AimIndicatorController:start()
	RunService.RenderStepped:Connect(update)
end

return AimIndicatorController
