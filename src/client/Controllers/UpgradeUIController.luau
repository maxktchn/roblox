--!strict
-- "Order Up!" screen: 3 ticket cards, reroll button. Sends only the chosen card index (PRD §7.3, §8.4).
--
-- The server sends OfferCards(cards, rerollsLeft). We show the cards and stop the chef
-- from walking. Tapping a card (or pressing 1/2/3) sends ChooseCard(index) and hides
-- the screen. The server decides what happens; if more level-ups are waiting it simply
-- sends the next OfferCards and the screen opens again.
--
-- The whole screen is built here in code once, then reused for every offer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Card = require(ReplicatedStorage.Shared.Card)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

type Card = Card.Card

local UpgradeUIController = {}

local player = Players.LocalPlayer

local MAX_CARDS = 3

local COLORS = {
	paper = Color3.fromRGB(255, 248, 231), -- ticket paper
	ink = Color3.fromRGB(45, 35, 30), -- main text
	faded = Color3.fromRGB(120, 105, 95), -- small text
	new = Color3.fromRGB(46, 160, 67), -- "NEW" badge
	level = Color3.fromRGB(214, 84, 40), -- "Lv 1 → Lv 2" badge
	button = Color3.fromRGB(214, 84, 40),
	disabled = Color3.fromRGB(150, 140, 130),
	gold = Color3.fromRGB(230, 175, 30), -- recipe cards (PRD §7.3)
}

-- Small label at the top of each card, and the colour of its icon circle.
local KINDS: { [string]: { label: string, color: Color3 } } = {
	Starter = { label = "SIGNATURE TOOL", color = Color3.fromRGB(214, 84, 40) },
	Gadget = { label = "KITCHEN GADGET", color = Color3.fromRGB(52, 120, 200) },
	Ingredient = { label = "INGREDIENT", color = Color3.fromRGB(46, 160, 67) },
	Recipe = { label = "SECRET RECIPE", color = Color3.fromRGB(230, 175, 30) },
	Filler = { label = "ON THE HOUSE", color = Color3.fromRGB(190, 120, 200) },
}

-- The parts of one card we change for each offer.
type CardView = {
	button: TextButton,
	stroke: UIStroke,
	kind: TextLabel,
	badge: TextLabel,
	icon: Frame,
	iconLetter: TextLabel,
	name: TextLabel,
	description: TextLabel,
}

local gui: ScreenGui
local cardViews: { CardView } = {}
local rerollButton: TextButton
local chooseCard: RemoteEvent
local requestReroll: RemoteEvent

local isOpen = false
local rerollsLeft = 0

-- Helper: a text label that scales its text to fit, up to `maxSize`.
local function makeLabel(parent: Instance, name: string, maxSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = COLORS.ink
	label.TextScaled = true
	label.TextWrapped = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.Parent = label
	label.Parent = parent
	return label
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

-- Build one ticket card. Positions inside the card are fractions (0 to 1) of its size.
local function makeCard(parent: Instance, index: number): CardView
	local button = Instance.new("TextButton")
	button.Name = `Card{index}`
	button.Text = ""
	button.LayoutOrder = index
	button.Size = UDim2.fromScale(0.3, 1)
	button.BackgroundColor3 = COLORS.paper
	button.AutoButtonColor = true
	corner(button, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = COLORS.ink
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	-- Keep a tall ticket shape whatever the screen size.
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 0.7
	aspect.Parent = button
	button.Parent = parent

	local kind = makeLabel(button, "Kind", 16)
	kind.Size = UDim2.fromScale(0.9, 0.08)
	kind.Position = UDim2.fromScale(0.05, 0.04)
	kind.TextColor3 = COLORS.faded

	local badge = makeLabel(button, "Badge", 22)
	badge.Size = UDim2.fromScale(0.7, 0.09)
	badge.Position = UDim2.fromScale(0.15, 0.13)
	badge.BackgroundTransparency = 0
	badge.TextColor3 = Color3.new(1, 1, 1)
	corner(badge, 8)

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.Size = UDim2.fromScale(0.4, 0.28)
	icon.Position = UDim2.fromScale(0.3, 0.26)
	icon.BorderSizePixel = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = icon
	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = 1
	iconAspect.Parent = icon
	icon.Parent = button
	-- Placeholder until real icons exist: the item's first letter.
	local iconLetter = makeLabel(icon, "Letter", 60)
	iconLetter.Size = UDim2.fromScale(1, 1)
	iconLetter.TextColor3 = Color3.new(1, 1, 1)

	local name = makeLabel(button, "ItemName", 30)
	name.Size = UDim2.fromScale(0.9, 0.12)
	name.Position = UDim2.fromScale(0.05, 0.58)

	local description = makeLabel(button, "Description", 20)
	description.Size = UDim2.fromScale(0.86, 0.22)
	description.Position = UDim2.fromScale(0.07, 0.72)
	description.Font = Enum.Font.GothamMedium
	description.TextColor3 = COLORS.faded

	return {
		button = button,
		stroke = stroke,
		kind = kind,
		badge = badge,
		icon = icon,
		iconLetter = iconLetter,
		name = name,
		description = description,
	}
end

local function buildScreen()
	gui = Instance.new("ScreenGui")
	gui.Name = "OrderUp"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 10 -- above the HUD
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- keep clear of phone notches (PRD §7.4)

	-- Dark see-through backdrop so the cards stand out and the kitchen stays visible.
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Parent = gui

	local title = makeLabel(backdrop, "Title", 56)
	title.Text = "ORDER UP!"
	title.Size = UDim2.fromScale(0.6, 0.1)
	title.Position = UDim2.fromScale(0.2, 0.04)
	title.TextColor3 = COLORS.paper

	local row = Instance.new("Frame")
	row.Name = "Cards"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.5)
	row.Size = UDim2.fromScale(0.94, 0.62)
	row.Parent = backdrop
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.02, 0)
	layout.Parent = row

	for i = 1, MAX_CARDS do
		cardViews[i] = makeCard(row, i)
	end

	rerollButton = Instance.new("TextButton")
	rerollButton.Name = "Reroll"
	rerollButton.AnchorPoint = Vector2.new(0.5, 1)
	rerollButton.Position = UDim2.fromScale(0.5, 0.97)
	rerollButton.Size = UDim2.fromOffset(220, 56) -- big enough for a thumb (PRD §7.4)
	rerollButton.Font = Enum.Font.FredokaOne
	rerollButton.TextSize = 26
	rerollButton.TextColor3 = Color3.new(1, 1, 1)
	corner(rerollButton, 12)
	rerollButton.Parent = backdrop
end

-- Fill one card view with a card's info.
local function showCard(view: CardView, card: Card)
	local kind = KINDS[card.Kind] or KINDS.Filler
	view.kind.Text = kind.label
	view.icon.BackgroundColor3 = kind.color
	view.iconLetter.Text = string.sub(card.Name, 1, 1)
	view.name.Text = card.Name
	view.description.Text = card.Description

	-- Recipe cards get a thick gold border (PRD §7.3); every other card a thin ink one.
	local isRecipe = card.Kind == "Recipe"
	view.stroke.Color = if isRecipe then COLORS.gold else COLORS.ink
	view.stroke.Thickness = if isRecipe then 7 else 3

	if card.Kind == "Filler" then
		view.badge.Visible = false
	elseif isRecipe then
		view.badge.Visible = true
		view.badge.Text = "RECIPE"
		view.badge.BackgroundColor3 = COLORS.gold
	elseif card.FromLevel == 0 then
		view.badge.Visible = true
		view.badge.Text = "NEW"
		view.badge.BackgroundColor3 = COLORS.new
	else
		view.badge.Visible = true
		view.badge.Text = `Lv {card.FromLevel} → Lv {card.ToLevel}`
		view.badge.BackgroundColor3 = COLORS.level
	end
	view.button.Visible = true
end

-- Freeze or unfreeze the chef. Anchoring the root part on this client stops walking and
-- jumping (the client controls its own character's movement); nothing else needs to change.
local function setMovement(enabled: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = not enabled
	end
end

local function updateRerollButton()
	rerollButton.Text = `Reroll ({rerollsLeft})`
	rerollButton.Active = rerollsLeft > 0
	rerollButton.AutoButtonColor = rerollsLeft > 0
	rerollButton.BackgroundColor3 = if rerollsLeft > 0 then COLORS.button else COLORS.disabled
end

local function open(cards: { Card }, rerolls: number)
	for i, view in cardViews do
		local card = cards[i]
		if card then
			showCard(view, card)
		else
			view.button.Visible = false -- fewer than 3 cards (e.g. only a Pie)
		end
	end
	rerollsLeft = rerolls
	updateRerollButton()
	isOpen = true
	gui.Enabled = true
	setMovement(false) -- the run is paused on the server; stop the chef walking too
end

local function close()
	isOpen = false
	gui.Enabled = false
	setMovement(true)
end

-- Send the choice once, then close. Ignores taps on hidden cards and double taps.
local function pick(index: number)
	if not isOpen or not cardViews[index].button.Visible then
		return
	end
	close()
	chooseCard:FireServer(index)
end

local function reroll()
	if not isOpen or rerollsLeft <= 0 then
		return
	end
	-- Grey the button until the server sends the new cards (a fresh OfferCards).
	rerollsLeft = 0
	updateRerollButton()
	requestReroll:FireServer()
end

function UpgradeUIController:init()
	buildScreen()
	for i, view in cardViews do
		view.button.Activated:Connect(function()
			pick(i)
		end)
	end
	rerollButton.Activated:Connect(reroll)
end

function UpgradeUIController:start()
	gui.Parent = player:WaitForChild("PlayerGui")
	chooseCard = Remotes.get("ChooseCard")
	requestReroll = Remotes.get("RequestReroll")

	Remotes.get("OfferCards").OnClientEvent:Connect(open)

	-- PC shortcut: 1, 2, 3 pick a card.
	local KEYS = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3 }
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		local index = KEYS[input.KeyCode]
		if index and not gameProcessed then
			pick(index)
		end
	end)
end

return UpgradeUIController
