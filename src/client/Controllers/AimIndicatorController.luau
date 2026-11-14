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
-- The arc is PIECES short flat pieces placed along a circle around the chef. To avoid dark
-- seams where pieces meet:
--   * each piece is exactly as long as its slice of the circle, so neighbours don't overlap
--   * neighbouring pieces sit at slightly different heights (STEP_HEIGHT), so no two surfaces
--     ever share the same plane (two surfaces in one plane flicker and show as dark lines)

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
local PIECES = 12 -- more pieces = a smoother curve
local THICKNESS = 0.3 -- studs
local COLOR = Color3.fromRGB(255, 140, 40) -- orange: easy to see on the white floor
local TRANSPARENCY = 0.15 -- fairly solid, so the orange stays strong on the white floor
-- Studs below the chef's root. The knife's slash is drawn at the root's height, so this keeps
-- the arc just under it, lined up with the swing instead of down on the floor.
local HEIGHT_BELOW_ROOT = 0.5
local STEP_HEIGHT = 0.004 -- every other piece sits this much higher (too small to see)

local folder: Folder
local pieces: { Part } = {}

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
	folder = Instance.new("Folder")
	folder.Name = "AimIndicator"
	-- Each piece spans an equal slice of the arc and is exactly that slice's chord long.
	local step = math.rad(ARC_DEGREES) / PIECES
	local length = 2 * RADIUS * math.sin(step / 2)
	for i = 1, PIECES do
		local piece = Instance.new("Part")
		piece.Name = `Piece{i}`
		piece.Size = Vector3.new(length, 0.05, THICKNESS)
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.CastShadow = false
		piece.Material = Enum.Material.SmoothPlastic -- Neon would glow it toward yellow
		piece.Color = COLOR
		piece.Transparency = 1
		piece.Parent = folder
		pieces[i] = piece
	end
	folder.Parent = workspace
end

local function hide()
	for _, piece in pieces do
		piece.Transparency = 1
	end
end

local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local orderUp = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("OrderUp")
	local cardsOpen = orderUp ~= nil and orderUp:IsA("ScreenGui") and orderUp.Enabled
	local runState = player:GetAttribute("RunState")
	local playing = runState ~= "Lost" and runState ~= "Won"
	if not (root and root:IsA("BasePart") and playing and ownsAimedWeapon()) or cardsOpen then
		hide()
		return
	end

	-- Same direction the server uses: the aim, or the chef's facing before the first aim.
	local look = root.CFrame.LookVector
	local direction: Vector3 = AimController.getAim() or Vector3.new(look.X, 0, look.Z).Unit
	local centre = root.Position - Vector3.new(0, HEIGHT_BELOW_ROOT, 0)
	local halfArc = math.rad(ARC_DEGREES) / 2
	local step = math.rad(ARC_DEGREES) / PIECES

	for i, piece in pieces do
		-- The middle of this piece's slice, from one end of the arc to the other.
		local angle = -halfArc + step * (i - 0.5)
		local outward = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(direction)
		local lift = if i % 2 == 0 then STEP_HEIGHT else 0
		local position = centre + outward * RADIUS + Vector3.new(0, lift, 0)
		-- Face outward, so the piece's length (its X) runs along the curve.
		piece.CFrame = CFrame.lookAt(position, position + outward)
		piece.Transparency = TRANSPARENCY
	end
end

function AimIndicatorController:init()
	buildArc()
end

function AimIndicatorController:start()
	RunService.RenderStepped:Connect(update)
end

return AimIndicatorController
