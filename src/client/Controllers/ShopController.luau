--!strict
-- The lobby's SHOP tab and the chest reveal (P2-7d #164; design:
-- docs/superpowers/specs/2026-11-20-talents-chests-design.md).
--
-- The SHOP page shows the Basic Chest (drawn from UI frames until there's art), its odds, and
-- OPEN / OPEN x10. LobbyController makes the page and calls ShopController.build(page) once, then
-- refresh() whenever the tab is shown.
--
-- Opening: the buttons send ChestAction(count). The server answers ChestResult(results, why,
-- count): a refusal shows `why` under the buttons; otherwise the reveal plays on its own screen:
-- the chest shakes (0.6 s), its lid pops, and each item card flips open (0.5 s) in its rarity
-- colour, with a sparkle for Rare and starters. Ten cards flip one after another, best last.
-- "Open again" sends the same count again (not for a DEV free roll, count 0).
--
-- Reads: the GearState remote (gold, for the buttons).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Gear = require(ReplicatedStorage.Config.Gear)
local GearMath = require(ReplicatedStorage.Shared.GearMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ShopController = {}

local player = Players.LocalPlayer
local BASIC = Gear.Chests.Basic

local COLORS = {
	paper = Color3.fromRGB(255, 248, 231),
	faded = Color3.fromRGB(190, 180, 165),
	gold = Color3.fromRGB(240, 185, 40),
	ink = Color3.fromRGB(45, 35, 30),
	box = Color3.fromRGB(55, 48, 43),
	off = Color3.fromRGB(90, 82, 76), -- a button you can't afford
	refused = Color3.fromRGB(235, 110, 95),
	wood = Color3.fromRGB(150, 95, 50),
	woodDark = Color3.fromRGB(105, 64, 34),
	band = Color3.fromRGB(80, 70, 66),
}

local SHAKE_SECONDS = 0.6
local FLIP_SECONDS = 0.5
local FLIP_GAP_SECONDS = 0.1 -- between cards when opening several
local CARD_SIZE = Vector2.new(104, 136)
local CARD_GAP = 8
local MAX_COLUMNS = 5

type ChestResult = { Item: string, Rarity: string, Starter: boolean }

local gold = 0
local waiting = false -- asked the server; buttons stay off until it answers
local openButton: TextButton
local bulkButton: TextButton
local messageLabel: TextLabel
local chestAction: RemoteEvent
local revealGui: ScreenGui
local revealToken = 0 -- a newer reveal (or closing) stops an older one

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, name: string, text: string, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = COLORS.paper
	l.TextWrapped = true
	l.Text = text
	l.Parent = parent
	return l
end

local function button(parent: Instance, name: string, text: string, width: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(width, 52) -- over the 44 px a thumb needs (PRD §7.4)
	b.BackgroundColor3 = COLORS.gold
	b.Font = Enum.Font.FredokaOne
	b.TextSize = 20
	b.TextColor3 = COLORS.ink
	b.Text = text
	corner(b, 12)
	b.Parent = parent
	return b
end

-- 5000 -> "5,000"
local function withCommas(n: number): string
	local s = tostring(math.floor(n))
	local out = s
	repeat
		local count
		out, count = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return out
end

-- "Common 75% · Fine 22% · Rare 3% · plus 1% for a starter", from the config.
local function oddsText(): string
	local parts = {}
	for _, rarity in Gear.Rarities do
		local chance = BASIC.Rarities[rarity.Id]
		if chance then
			table.insert(parts, `{rarity.Id} {math.round(chance * 1000) / 10}%`)
		end
	end
	table.insert(parts, `plus {math.round(BASIC.StarterDropChance * 1000) / 10}% for a starter`)
	return table.concat(parts, " · ")
end

-- A chest drawn from frames: a wooden body, a lid on top, iron bands and a gold latch.
-- Returns the holder (size it and place it) and the lid (it pops off in the reveal).
local function drawChest(parent: Instance, width: number): (Frame, Frame)
	local height = math.round(width * 0.8)
	local holder = Instance.new("Frame")
	holder.Name = "Chest"
	holder.Size = UDim2.fromOffset(width, height)
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0, 1)
	body.Position = UDim2.fromScale(0, 1)
	body.Size = UDim2.fromScale(1, 0.62)
	body.BackgroundColor3 = COLORS.wood
	corner(body, 6)
	local bodyStroke = Instance.new("UIStroke")
	bodyStroke.Color = COLORS.woodDark
	bodyStroke.Thickness = 3
	bodyStroke.Parent = body
	body.Parent = holder

	local lid = Instance.new("Frame")
	lid.Name = "Lid"
	lid.Position = UDim2.fromScale(0, 0.04)
	lid.Size = UDim2.fromScale(1, 0.36)
	lid.BackgroundColor3 = COLORS.woodDark
	corner(lid, 10)
	local lidStroke = Instance.new("UIStroke")
	lidStroke.Color = COLORS.band
	lidStroke.Thickness = 3
	lidStroke.Parent = lid
	lid.Parent = holder

	for _, x in { 0.18, 0.82 } do
		for _, part in { body, lid } do
			local band = Instance.new("Frame")
			band.AnchorPoint = Vector2.new(0.5, 0)
			band.Position = UDim2.fromScale(x, 0)
			band.Size = UDim2.new(0, math.max(4, math.round(width * 0.06)), 1, 0)
			band.BackgroundColor3 = COLORS.band
			band.BorderSizePixel = 0
			band.Parent = part
		end
	end

	local latch = Instance.new("Frame")
	latch.Name = "Latch"
	latch.AnchorPoint = Vector2.new(0.5, 0.5)
	latch.Position = UDim2.fromScale(0.5, 0.4) -- on the seam, over the lid's edge
	latch.Size = UDim2.fromOffset(math.round(width * 0.16), math.round(width * 0.2))
	latch.BackgroundColor3 = COLORS.gold
	corner(latch, 4)
	latch.Parent = holder -- after the lid, so it's drawn on top; it stays when the lid pops
	return holder, lid
end

-- Grey out what the player can't afford (or everything while waiting for the server).
local function updateButtons()
	if not openButton then
		return
	end
	local canOne = not waiting and gold >= BASIC.Price
	local canBulk = not waiting and gold >= BASIC.Price * BASIC.BulkCount
	openButton.BackgroundColor3 = if canOne then COLORS.gold else COLORS.off
	openButton.AutoButtonColor = canOne
	bulkButton.BackgroundColor3 = if canBulk then COLORS.gold else COLORS.off
	bulkButton.AutoButtonColor = canBulk
end

local function ask(count: number)
	if waiting or gold < BASIC.Price * count then
		if not waiting then
			messageLabel.Text = `Not enough gold: {withCommas(BASIC.Price * count)} needed`
		end
		return
	end
	waiting = true
	messageLabel.Text = ""
	updateButtons()
	chestAction:FireServer(count)
end

--------------------------------------------------------------------------------
-- The reveal
--------------------------------------------------------------------------------

-- Higher = better; starters count as the best.
local function rank(result: ChestResult): number
	return if result.Starter then 100 else (GearMath.rarityIndex(result.Rarity) or 0)
end

local function rarityColor(rarityId: string): Color3
	local index = GearMath.rarityIndex(rarityId)
	return if index then Gear.Rarities[index].Color else COLORS.paper
end

local function closeReveal()
	revealToken += 1
	revealGui.Enabled = false
	for _, child in revealGui:GetChildren() do
		child:Destroy()
	end
end

-- Little stars bursting out of a card (Rare and starters).
local function sparkle(card: Frame, color: Color3)
	for i = 1, 8 do
		local star = label(card, "Sparkle", "✦", 22)
		star.TextColor3 = color
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(0.5, 0.5)
		star.Size = UDim2.fromOffset(24, 24)
		star.ZIndex = 5
		local angle = (i / 8) * math.pi * 2
		local goal = UDim2.new(0.5, math.cos(angle) * 80, 0.5, math.sin(angle) * 80)
		local tween = TweenService:Create(
			star,
			TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = goal, TextTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Once(function()
			star:Destroy()
		end)
	end
end

-- One item card, face hidden (zero width) until flip().
local function makeCard(parent: Instance, result: ChestResult, order: number, textScale: number): (Frame, () -> ())
	local slot = Instance.new("Frame")
	slot.Name = `Card_{order}`
	slot.LayoutOrder = order
	slot.BackgroundTransparency = 1

	local color = rarityColor(result.Rarity)
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromScale(0, 1)
	face.BackgroundColor3 = COLORS.box
	face.ClipsDescendants = true
	corner(face, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = if result.Starter then COLORS.gold else color
	stroke.Thickness = 3
	stroke.Parent = face
	face.Parent = slot

	local rarity = label(face, "Rarity", result.Rarity, math.round(16 * textScale))
	rarity.Position = UDim2.fromOffset(4, math.round(10 * textScale))
	rarity.Size = UDim2.new(1, -8, 0, math.round(20 * textScale))
	rarity.TextColor3 = color
	local name = label(face, "Name", GearMath.itemName(result.Item), math.round(18 * textScale))
	name.Position = UDim2.new(0, 4, 0.3, 0)
	name.Size = UDim2.new(1, -8, 0.4, 0)
	local noteText = if result.Starter then "NEW STARTER!" else GearMath.slot(result.Item) or ""
	local note = label(face, "Note", noteText, math.round(13 * textScale))
	note.AnchorPoint = Vector2.new(0, 1)
	note.Position = UDim2.new(0, 4, 1, -math.round(8 * textScale))
	note.Size = UDim2.new(1, -8, 0, math.round(18 * textScale))
	note.Font = if result.Starter then Enum.Font.FredokaOne else Enum.Font.GothamMedium
	note.TextColor3 = if result.Starter then COLORS.gold else COLORS.faded

	local function flip()
		TweenService:Create(
			face,
			TweenInfo.new(FLIP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(1, 1) }
		):Play()
		if result.Starter or rank(result) >= (GearMath.rarityIndex("Rare") or 3) then
			sparkle(slot, if result.Starter then COLORS.gold else color)
		end
	end
	slot.Parent = parent
	return slot, flip
end

local function showReveal(results: { ChestResult }, count: number)
	closeReveal()
	local token = revealToken
	revealGui.Enabled = true

	local backdrop = Instance.new("TextButton") -- blocks taps to the lobby underneath
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.3
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Parent = revealGui

	-- 1. The chest shakes, then its lid pops off.
	local chest, lid = drawChest(revealGui, 160)
	chest.AnchorPoint = Vector2.new(0.5, 0.5)
	chest.Position = UDim2.fromScale(0.5, 0.5)
	local shakes = 6
	for i = 1, shakes do
		if token ~= revealToken then
			return
		end
		local angle = if i == shakes then 0 elseif i % 2 == 1 then 8 else -8
		TweenService:Create(chest, TweenInfo.new(SHAKE_SECONDS / shakes), { Rotation = angle }):Play()
		task.wait(SHAKE_SECONDS / shakes)
	end
	if token ~= revealToken then
		return
	end
	TweenService:Create(
		lid,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.1, -0.6), Rotation = -25, BackgroundTransparency = 1 }
	):Play()
	task.wait(0.2)
	if token ~= revealToken then
		return
	end
	chest:Destroy()

	-- 2. The cards, worst first so the best flips last.
	local sorted = table.clone(results)
	table.sort(sorted, function(a, b)
		return rank(a) < rank(b)
	end)
	local single = #sorted == 1
	local columns = math.min(#sorted, MAX_COLUMNS)
	local rows = math.ceil(#sorted / MAX_COLUMNS)
	local cell = if single then CARD_SIZE * 1.5 else CARD_SIZE
	local gridWidth = columns * cell.X + (columns - 1) * CARD_GAP
	local gridHeight = rows * cell.Y + (rows - 1) * CARD_GAP

	local panel = Instance.new("Frame")
	panel.Name = "Results"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(math.max(gridWidth, 300), gridHeight + 80)
	panel.BackgroundTransparency = 1
	panel.Parent = revealGui
	-- Shrink to fit a small phone screen.
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1024, 768)
	local scale = Instance.new("UIScale")
	scale.Scale = math.min(1, (viewport.X - 32) / panel.Size.X.Offset, (viewport.Y - 32) / panel.Size.Y.Offset)
	scale.Parent = panel

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.AnchorPoint = Vector2.new(0.5, 0)
	grid.Position = UDim2.fromScale(0.5, 0)
	grid.Size = UDim2.fromOffset(gridWidth, gridHeight)
	grid.BackgroundTransparency = 1
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	layout.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = grid

	local flips = {}
	for order, result in sorted do
		local _, flip = makeCard(grid, result, order, if single then 1.5 else 1)
		table.insert(flips, flip)
	end
	for _, flip in flips do
		if token ~= revealToken then
			return
		end
		flip()
		task.wait(if single then FLIP_SECONDS else FLIP_GAP_SECONDS)
	end
	task.wait(FLIP_SECONDS)
	if token ~= revealToken then
		return
	end

	-- 3. Open again / Close.
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.fromScale(0.5, 1)
	row.Size = UDim2.new(1, 0, 0, 56)
	row.BackgroundTransparency = 1
	row.Parent = panel
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.Padding = UDim.new(0, 12)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row
	if count > 0 then
		local again = button(row, "OpenAgain", `Open again ({withCommas(BASIC.Price * count)})`, 200)
		if gold < BASIC.Price * count then
			again.BackgroundColor3 = COLORS.off
		end
		again.Activated:Connect(function()
			if gold >= BASIC.Price * count and not waiting then
				closeReveal()
				ask(count)
			end
		end)
	end
	local close = button(row, "Close", "Close", 120)
	close.LayoutOrder = 2
	close.BackgroundColor3 = COLORS.box
	close.TextColor3 = COLORS.paper
	close.Activated:Connect(closeReveal)
end

--------------------------------------------------------------------------------
-- The SHOP page
--------------------------------------------------------------------------------

-- Fill the lobby's SHOP page (called once by LobbyController).
function ShopController.build(page: Frame)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = page

	local chest = drawChest(page, 110)
	chest.LayoutOrder = 1
	local title = label(page, "Title", "BASIC CHEST", 26)
	title.LayoutOrder = 2
	title.Size = UDim2.new(1, -24, 0, 32)
	title.TextColor3 = COLORS.gold
	local odds = label(page, "Odds", oddsText(), 15)
	odds.LayoutOrder = 3
	odds.Size = UDim2.new(1, -24, 0, 36)
	odds.Font = Enum.Font.GothamMedium

	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.LayoutOrder = 4
	row.Size = UDim2.new(1, -24, 0, 52)
	row.BackgroundTransparency = 1
	row.Parent = page
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.Padding = UDim.new(0, 12)
	rowLayout.Parent = row
	openButton = button(row, "Open", `OPEN  {withCommas(BASIC.Price)} gold`, 190)
	bulkButton =
		button(row, "OpenBulk", `OPEN x{BASIC.BulkCount}  {withCommas(BASIC.Price * BASIC.BulkCount)} gold`, 230)
	openButton.Activated:Connect(function()
		ask(1)
	end)
	bulkButton.Activated:Connect(function()
		ask(BASIC.BulkCount)
	end)

	messageLabel = label(page, "Message", "", 15)
	messageLabel.LayoutOrder = 5
	messageLabel.Size = UDim2.new(1, -24, 0, 20)
	messageLabel.TextColor3 = COLORS.refused
	local premium = label(page, "Premium", "Premium Chests: coming later", 15)
	premium.LayoutOrder = 6
	premium.Size = UDim2.new(1, -24, 0, 20)
	premium.Font = Enum.Font.GothamMedium
	premium.TextColor3 = COLORS.faded
	updateButtons()
end

-- The SHOP tab was shown.
function ShopController.refresh()
	if messageLabel then
		messageLabel.Text = ""
	end
	updateButtons()
end

function ShopController:start()
	revealGui = Instance.new("ScreenGui")
	revealGui.Name = "ChestReveal"
	revealGui.ResetOnSpawn = false
	revealGui.DisplayOrder = 16 -- over the lobby (14) and the Gear screen (15)
	revealGui.IgnoreGuiInset = true
	revealGui.Enabled = false
	revealGui.Parent = player:WaitForChild("PlayerGui")

	chestAction = Remotes.get("ChestAction")
	Remotes.get("GearState").OnClientEvent:Connect(function(state: { Currencies: { [string]: number } })
		gold = state.Currencies.Gold or 0
		updateButtons()
	end)
	Remotes.get("ChestResult").OnClientEvent:Connect(function(results: { ChestResult }?, why: string?, count: number)
		waiting = false
		updateButtons()
		if results and #results > 0 then
			task.spawn(showReveal, results, count)
		elseif why and messageLabel then
			messageLabel.Text = why
		end
	end)
end

return ShopController
