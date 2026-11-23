--!strict
-- The lobby's TALENTS tab (P2-7c #163, PRD §4.5; design: docs/superpowers/specs/2026-11-20-talents-chests-design.md).
--
-- LobbyController makes the page and the tab's NEW badge, then calls build(page, badge), and
-- refresh() whenever the tab is shown. The page has:
--   * a header with the account level and an XP bar
--   * one full-width card per talent node (TalentMath): bought nodes show a ✓, specials a ★ and a
--     gold border, the next node a BUY button with its price (greyed out without the gold), later
--     nodes "🔒 Account Lv N". The list opens scrolled to the next node.
--   * a totals line adding up everything bought
-- BUY sends TalentAction("Buy"); the server checks everything and replies with
-- TalentResult(bought?, why?). A bought card pops as it turns to ✓.
-- The NEW badge shows while the next node can be bought (unlocked by level, and the gold).
--
-- Reads: "AccountLevel", "AccountXp", "AccountXpNeeded", "TalentsBought" (TalentService) and the
-- GearState remote (gold).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TalentMath = require(ReplicatedStorage.Shared.TalentMath)
local Talents = require(ReplicatedStorage.Config.Talents)

local TalentsController = {}

local player = Players.LocalPlayer

local CARD_HEIGHT = 48 -- full width, over the 44 px a thumb needs (PRD §7.4)
local CARD_GAP = 6
local COLORS = {
	paper = Color3.fromRGB(255, 248, 231),
	faded = Color3.fromRGB(150, 140, 128),
	gold = Color3.fromRGB(240, 185, 40),
	ink = Color3.fromRGB(45, 35, 30),
	card = Color3.fromRGB(55, 48, 43),
	bought = Color3.fromRGB(48, 66, 44),
	locked = Color3.fromRGB(38, 34, 31),
	tick = Color3.fromRGB(120, 200, 110),
	buy = Color3.fromRGB(230, 175, 30),
	greyed = Color3.fromRGB(95, 88, 80),
	bar = Color3.fromRGB(70, 62, 56),
	error = Color3.fromRGB(255, 120, 100),
}

type Card = {
	frame: Frame,
	stroke: UIStroke,
	scale: UIScale,
	number: TextLabel,
	text: TextLabel,
	right: TextLabel,
	buy: TextButton,
}

local cards: { Card } = {}
local list: ScrollingFrame
local levelLabel: TextLabel
local xpFill: Frame
local totalsLabel: TextLabel
local messageLabel: TextLabel
local newBadge: GuiObject? = nil
local gold = 0
local waiting = false -- a Buy was sent; ignore taps until the reply

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

local function numberAttribute(name: string): number?
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else nil
end

local function level(): number
	return numberAttribute("AccountLevel") or 1
end

local function bought(): number
	return numberAttribute("TalentsBought") or 0
end

local function makeCard(number: number): Card
	local node = TalentMath.node(number)
	assert(node, `no talent node {number}`)
	local frame = Instance.new("Frame")
	frame.Name = `Node_{number}`
	frame.LayoutOrder = number
	frame.Size = UDim2.new(1, -12, 0, CARD_HEIGHT)
	frame.BackgroundColor3 = COLORS.card
	corner(frame, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = COLORS.gold
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Enabled = node.Special
	stroke.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	local numberLabel = label(frame, "Number", "", 18)
	numberLabel.Position = UDim2.fromOffset(8, 0)
	numberLabel.Size = UDim2.new(0, 56, 1, 0)
	numberLabel.TextXAlignment = Enum.TextXAlignment.Left

	local text = label(frame, "Text", if node.Special then `★ {node.Text}` else node.Text, 17)
	text.Position = UDim2.fromOffset(64, 0)
	text.Size = UDim2.new(1, -64 - 150, 1, 0)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = if node.Special then COLORS.gold else COLORS.paper
	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MaxTextSize = 17
	textLimit.Parent = text
	text.TextScaled = true

	local right = label(frame, "State", "", 15)
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.new(1, -10, 0.5, 0)
	right.Size = UDim2.new(0, 140, 1, 0)
	right.TextXAlignment = Enum.TextXAlignment.Right
	right.Font = Enum.Font.GothamMedium

	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.new(1, -6, 0.5, 0)
	buy.Size = UDim2.new(0, 140, 1, -8)
	buy.BackgroundColor3 = COLORS.buy
	buy.Font = Enum.Font.FredokaOne
	buy.TextSize = 17
	buy.TextColor3 = COLORS.ink
	buy.Text = `BUY {node.Cost}`
	buy.Visible = false
	corner(buy, 8)
	buy.Parent = frame
	buy.Activated:Connect(function()
		if waiting or not buy.Active then
			return
		end
		waiting = true
		messageLabel.Text = ""
		Remotes.get("TalentAction"):FireServer("Buy")
	end)

	frame.Parent = list
	return {
		frame = frame,
		stroke = stroke,
		scale = scale,
		number = numberLabel,
		text = text,
		right = right,
		buy = buy,
	}
end

local function updateBadge()
	if newBadge then
		newBadge.Visible = TalentMath.canBuyNext(level(), bought(), gold)
	end
end

-- Redraw the header, every card and the totals from the attributes and the last gold.
function TalentsController.refresh()
	if not list then
		return
	end
	local accountLevel, owned = level(), bought()
	local xp, needed = numberAttribute("AccountXp"), numberAttribute("AccountXpNeeded")
	if needed and xp then
		levelLabel.Text = `Account Lv {accountLevel} · {xp} / {needed} XP`
		xpFill.Size = UDim2.fromScale(math.clamp(xp / needed, 0, 1), 1)
	else
		levelLabel.Text = `Account Lv {accountLevel} (max)`
		xpFill.Size = UDim2.fromScale(1, 1)
	end
	for number, card in cards do
		local isBought = number <= owned
		local isNext = number == owned + 1
		local unlocked = number <= accountLevel
		card.number.Text = if isBought then `✓ {number}` elseif unlocked then `{number}` else `🔒 {number}`
		card.number.TextColor3 = if isBought then COLORS.tick elseif unlocked then COLORS.paper else COLORS.faded
		card.frame.BackgroundColor3 = if isBought then COLORS.bought elseif unlocked then COLORS.card else COLORS.locked
		local canAfford = gold >= TalentMath.cost(number)
		card.buy.Visible = isNext and unlocked
		card.buy.Active = canAfford
		card.buy.AutoButtonColor = canAfford
		card.buy.BackgroundColor3 = if canAfford then COLORS.buy else COLORS.greyed
		card.right.Visible = not card.buy.Visible
		card.right.Text = if isBought
			then "✓ Bought"
			elseif unlocked then `{TalentMath.cost(number)} gold`
			else `🔒 Account Lv {number}`
		card.right.TextColor3 = if isBought then COLORS.tick else COLORS.faded
	end
	local totals = TalentMath.describe(TalentMath.totals(owned))
	totalsLabel.Text = if totals == "" then "Totals: nothing bought yet" else `Totals: {totals}`
	updateBadge()
end

-- Scroll so the next node (or the last one) sits near the top of the list.
local function scrollToNext()
	local target = math.clamp(bought() + 1, 1, Talents.MaxLevel)
	local y = (target - 1) * (CARD_HEIGHT + CARD_GAP) - CARD_HEIGHT
	task.defer(function()
		local maxY = math.max(list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y, 0)
		list.CanvasPosition = Vector2.new(0, math.clamp(y, 0, maxY))
	end)
end

-- The tab was opened: redraw and jump to the next node.
function TalentsController.show()
	TalentsController.refresh()
	scrollToNext()
end

-- A card just bought: a short pop.
local function pop(card: Card)
	card.scale.Scale = 1.06
	TweenService:Create(card.scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

-- Fill the TALENTS page. `badge` is the tab's NEW badge.
function TalentsController.build(page: Frame, badge: GuiObject)
	newBadge = badge

	levelLabel = label(page, "Level", "", 18)
	levelLabel.Position = UDim2.fromOffset(12, 8)
	levelLabel.Size = UDim2.new(1, -24, 0, 24)
	local bar = Instance.new("Frame")
	bar.Name = "XpBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 36)
	bar.Size = UDim2.new(0.8, 0, 0, 8)
	bar.BackgroundColor3 = COLORS.bar
	corner(bar, 4)
	bar.Parent = page
	xpFill = Instance.new("Frame")
	xpFill.Name = "Fill"
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = COLORS.gold
	corner(xpFill, 4)
	xpFill.Parent = bar

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(12, 52)
	list.Size = UDim2.new(1, -24, 1, -52 - 64)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = page
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, CARD_GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = list

	for number = 1, Talents.MaxLevel do
		cards[number] = makeCard(number)
	end

	totalsLabel = label(page, "Totals", "", 15)
	totalsLabel.AnchorPoint = Vector2.new(0, 1)
	totalsLabel.Position = UDim2.new(0, 12, 1, -26)
	totalsLabel.Size = UDim2.new(1, -24, 0, 34)
	totalsLabel.TextColor3 = COLORS.gold
	totalsLabel.Font = Enum.Font.GothamMedium
	totalsLabel.TextScaled = true
	local totalsLimit = Instance.new("UITextSizeConstraint")
	totalsLimit.MaxTextSize = 15
	totalsLimit.Parent = totalsLabel

	messageLabel = label(page, "Message", "", 14)
	messageLabel.AnchorPoint = Vector2.new(0, 1)
	messageLabel.Position = UDim2.new(0, 12, 1, -6)
	messageLabel.Size = UDim2.new(1, -24, 0, 20)
	messageLabel.TextColor3 = COLORS.error
	messageLabel.Font = Enum.Font.GothamMedium

	TalentsController.refresh()
end

function TalentsController:start()
	Remotes.get("GearState").OnClientEvent:Connect(function(state: { Currencies: { [string]: number } })
		gold = state.Currencies.Gold or 0
		TalentsController.refresh()
	end)
	Remotes.get("TalentResult").OnClientEvent:Connect(function(number: number?, why: string?)
		waiting = false
		if messageLabel then
			messageLabel.Text = why or ""
		end
		TalentsController.refresh()
		local card = number and cards[number]
		if card then
			pop(card)
		end
	end)
	player.AttributeChanged:Connect(function(name: string)
		if name == "AccountLevel" or name == "AccountXp" or name == "AccountXpNeeded" or name == "TalentsBought" then
			TalentsController.refresh()
		end
	end)
end

return TalentsController
