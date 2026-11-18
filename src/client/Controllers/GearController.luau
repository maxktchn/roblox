--!strict
-- The Gear screen (P2-4 #138, PRD §4, design: docs/superpowers/specs/2026-11-17-gear-design.md).
--
-- It lives in the lobby's Gear tab (P2-8 #144): LobbyController docks it on the right of the
-- screen (setDocked) beside the chef, and opens and closes it with the tab.
--
-- The server owns everything: this screen draws the latest GearState(state, message?) and sends
-- GearAction(action, arg) when a button is tapped. Every number shown comes from GearMath, the
-- same module the server uses, so the screen and the server always agree.
--
-- Layout: currencies along the top, the 5 equipped slots on the left, the inventory on the
-- right. Tapping an item opens its detail box (equip, level up, merge, salvage). Merge opens a
-- pick-3 list with the 3 lowest-level copies ticked. Salvaging Epic or Legendary asks first.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gear = require(ReplicatedStorage.Config.Gear)
local GearMath = require(ReplicatedStorage.Shared.GearMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local GearController = {}

local player = Players.LocalPlayer

type GearState = {
	Items: { [string]: GearMath.ItemRecord },
	Equipped: { [string]: string },
	Currencies: { [string]: number },
	CanChange: boolean,
}

local COLORS = {
	back = Color3.fromRGB(30, 26, 24),
	box = Color3.fromRGB(55, 48, 43),
	paper = Color3.fromRGB(255, 248, 231),
	faded = Color3.fromRGB(190, 180, 165),
	gold = Color3.fromRGB(240, 185, 40),
	button = Color3.fromRGB(90, 80, 72),
	go = Color3.fromRGB(70, 160, 80),
	danger = Color3.fromRGB(190, 70, 50),
	ink = Color3.fromRGB(45, 35, 30),
}

local SLOT_ORDER = { "Utensil", "Hat", "Apron", "Mitts", "Shoes" }
local BUTTON_HEIGHT = 44 -- big enough for a thumb (PRD §7.4)

local gearAction: RemoteEvent
local state: GearState? = nil
local selectedId: string? = nil -- the item whose detail box is open

local gui: ScreenGui
local currencyLabel: TextLabel
local messageLabel: TextLabel
local slotsFrame: Frame
local inventory: ScrollingFrame
local detail: Frame
local picker: Frame
local confirmBox: Frame
local mainPanel: Frame
local closeButton: TextButton
local panelLimit: UISizeConstraint

--------------------------------------------------------------------------------
-- Small building blocks
--------------------------------------------------------------------------------

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = COLORS.paper
	l.TextWrapped = true
	l.Text = text
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, color: Color3, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = color
	b.Font = Enum.Font.FredokaOne
	b.TextColor3 = COLORS.paper
	b.TextScaled = true
	b.Text = text
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 18
	limit.Parent = b
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = b
	corner(b, 8)
	b.Activated:Connect(function()
		if b.Active then
			onClick()
		end
	end)
	b.Parent = parent
	return b
end

-- Grey out a button and stop it working (or bring it back).
local function setEnabled(b: TextButton, enabled: boolean)
	b.Active = enabled
	b.AutoButtonColor = enabled
	b.BackgroundTransparency = if enabled then 0 else 0.6
	b.TextTransparency = if enabled then 0 else 0.4
end

-- A centred box over the screen (detail, picker, confirm).
local function modal(name: string, width: number, height: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(0.92, 0.92) -- shrinks on small phones; capped at width x height below
	f.BackgroundColor3 = COLORS.box
	f.ZIndex = 5
	f.Visible = false
	corner(f, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.paper
	stroke.Thickness = 2
	stroke.Parent = f
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(width, height)
	limit.Parent = f
	f.Parent = gui
	return f
end

local function rarityColor(rarity: string): Color3
	local index = GearMath.rarityIndex(rarity)
	return if index then Gear.Rarities[index].Color else COLORS.button
end

-- 0.0333 -> "+3.3%", 0.16 -> "+16%"
local function percent(fraction: number): string
	local value = math.round(fraction * 1000) / 10
	if value == math.floor(value) then
		return `+{value // 1}%`
	end
	return `+{value}%`
end

local function statWord(itemId: string): string
	return if GearMath.mainStat(itemId) == "Hp" then "HP" else "damage"
end

-- "HatPattern" -> "Hat Pattern"
local function spaced(name: string): string
	return (string.gsub(name, "(%l)(%u)", "%1 %2"))
end

local function isEquipped(id: string): boolean
	if not state then
		return false
	end
	for _, equippedId in state.Equipped do
		if equippedId == id then
			return true
		end
	end
	return false
end

-- Every copy of an item at a rarity, lowest level first.
local function copiesOf(itemId: string, rarity: string): { string }
	local ids = {}
	if not state then
		return ids
	end
	for id, record in state.Items do
		if record.Item == itemId and record.Rarity == rarity then
			table.insert(ids, id)
		end
	end
	local items = state.Items
	table.sort(ids, function(a, b)
		if items[a].Level ~= items[b].Level then
			return items[a].Level < items[b].Level
		end
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	return ids
end

local function showMessage(text: string?)
	messageLabel.Text = text or ""
end

local function send(action: string, arg: any)
	gearAction:FireServer(action, arg)
end

--------------------------------------------------------------------------------
-- Confirm box (salvaging Epic or Legendary)
--------------------------------------------------------------------------------

local confirmText: TextLabel
local confirmYes: () -> () = function() end

local function askConfirm(text: string, onYes: () -> ())
	confirmText.Text = text
	confirmYes = onYes
	confirmBox.Visible = true
end

--------------------------------------------------------------------------------
-- Pick-3 merge
--------------------------------------------------------------------------------

local pickerList: ScrollingFrame
local pickerSummary: TextLabel
local pickerConfirm: TextButton
local picked: { [string]: boolean } = {}
local pickerItem: string? = nil
local pickerRarity: string? = nil

local function pickedIds(): { string }
	local ids = {}
	for id in picked do
		table.insert(ids, id)
	end
	return ids
end

local function drawPicker()
	local current = state
	local itemId, rarity = pickerItem, pickerRarity
	if not (current and itemId and rarity) then
		picker.Visible = false
		return
	end
	for _, child in pickerList:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local copies = copiesOf(itemId, rarity)
	-- Forget picks of copies that are gone (after a refresh).
	for id in picked do
		if not current.Items[id] then
			picked[id] = nil
		end
	end
	for order, id in copies do
		local record = current.Items[id]
		local text =
			`{if picked[id] then "[x]" else "[  ]"} Lv {record.Level}{if isEquipped(id) then " (equipped)" else ""}`
		local b = button(pickerList, text, if picked[id] then COLORS.go else COLORS.button, function()
			if picked[id] then
				picked[id] = nil
			elseif #pickedIds() < Gear.MergeCopies then
				picked[id] = true
			end
			drawPicker()
		end)
		b.LayoutOrder = order
		b.Size = UDim2.new(1, -8, 0, BUTTON_HEIGHT)
	end

	-- The result and the refund, worked out with the server's own maths.
	local nextRarity = GearMath.nextRarity(rarity) or rarity
	local spentGold, spentMaterial, highest = 0, 0, 1
	local ids = pickedIds()
	for _, id in ids do
		local record = current.Items[id]
		spentGold += record.SpentGold
		spentMaterial += record.SpentMaterial
		highest = math.max(highest, record.Level)
	end
	local refundGold, refundMaterial = GearMath.refund(spentGold, spentMaterial)
	local material = GearMath.material(itemId) or ""
	local lines = {
		`{rarity} Lv {highest} {percent(GearMath.bonus(itemId, rarity, highest))} → {nextRarity} Lv 1 {percent(
			GearMath.bonus(itemId, nextRarity, 1)
		)} {statWord(itemId)}`,
	}
	local effect = (Gear.Items[itemId].Effect :: any)[nextRarity]
	if effect and effect.Text then
		table.insert(lines, `Unlocks: {effect.Text}`)
	end
	table.insert(lines, `Refund: {refundGold} gold, {refundMaterial} {spaced(material)}`)
	table.insert(lines, `Picked {#ids} of {Gear.MergeCopies}`)
	pickerSummary.Text = table.concat(lines, "\n")
	setEnabled(pickerConfirm, #ids == Gear.MergeCopies and current.CanChange)
end

local function openPicker(itemId: string, rarity: string)
	pickerItem, pickerRarity = itemId, rarity
	table.clear(picked)
	for index, id in copiesOf(itemId, rarity) do
		if index <= Gear.MergeCopies then
			picked[id] = true -- the 3 lowest-level copies, so a quick merge never eats a levelled one
		end
	end
	detail.Visible = false
	picker.Visible = true
	drawPicker()
end

--------------------------------------------------------------------------------
-- Detail box (one item)
--------------------------------------------------------------------------------

local detailTitle: TextLabel
local detailBody: TextLabel
local equipButton: TextButton
local levelButton: TextButton
local mergeButton: TextButton
local salvageButton: TextButton

local function drawDetail()
	local current = state
	local id = selectedId
	local record = current and id and current.Items[id]
	if not (current and id and record) then
		detail.Visible = false
		return
	end
	local itemId, rarity, level = record.Item, record.Rarity, record.Level
	local maxLevel = GearMath.maxLevel(rarity) or level
	detailTitle.Text = `{rarity} {GearMath.itemName(itemId)}`
	detailTitle.TextColor3 = rarityColor(rarity)

	local lines = { `Lv {level} / {maxLevel}: {percent(GearMath.bonus(itemId, rarity, level))} {statWord(itemId)}` }
	local gold, materialCost = GearMath.levelCost(level)
	local material = GearMath.material(itemId) or ""
	local atCap = level >= maxLevel
	if not atCap then
		table.insert(lines, `Next level: {percent(GearMath.bonus(itemId, rarity, level + 1))}`)
	else
		table.insert(lines, "Max level for this rarity: merge to go higher")
	end
	local effect = (Gear.Items[itemId].Effect :: any)[rarity]
	if effect and effect.Text then
		table.insert(lines, `Bonus: {effect.Text}`)
	end
	detailBody.Text = table.concat(lines, "\n")

	local canChange = current.CanChange
	equipButton.Text = if isEquipped(id) then "Equipped" else "Equip"
	setEnabled(equipButton, canChange and not isEquipped(id))

	levelButton.Text = if atCap then "Max level" else `Level up: {gold} gold, {materialCost} {spaced(material)}`
	local affordable = (current.Currencies.Gold or 0) >= gold and (current.Currencies[material] or 0) >= materialCost
	setEnabled(levelButton, canChange and not atCap and affordable)

	local copies = #copiesOf(itemId, rarity)
	mergeButton.Text = `Merge ({copies}/{Gear.MergeCopies})`
	setEnabled(mergeButton, canChange and copies >= Gear.MergeCopies and GearMath.nextRarity(rarity) ~= nil)

	local salvageGold, salvageMaterial = GearMath.salvage(record)
	salvageButton.Text = `Salvage: +{salvageGold} gold, +{salvageMaterial} {spaced(material)}`
	setEnabled(salvageButton, canChange and not isEquipped(id))
end

local function openDetail(id: string)
	selectedId = id
	picker.Visible = false
	detail.Visible = true
	drawDetail()
end

--------------------------------------------------------------------------------
-- Main screen
--------------------------------------------------------------------------------

-- One item tile (used for slots and the inventory).
local function tile(parent: Instance, id: string, record: GearMath.ItemRecord, order: number): TextButton
	local b = button(parent, "", COLORS.box, function()
		openDetail(id)
	end)
	b.Name = `Item_{id}`
	b.LayoutOrder = order
	b.TextScaled = false
	b.TextSize = 14
	b.TextWrapped = true
	b.Text = `{GearMath.itemName(record.Item)}\nLv {record.Level}{if isEquipped(id) then "  E" else ""}`
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = rarityColor(record.Rarity)
	stroke.Thickness = 3
	stroke.Parent = b
	return b
end

local function drawMain()
	local current = state
	for _, child in slotsFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in inventory:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not current then
		currencyLabel.Text = "Loading your gear..."
		return
	end

	-- Short names so the line fits a phone: "Hat 40" for Hat Patterns.
	local parts = { `Gold {current.Currencies.Gold or 0}` }
	for _, slot in SLOT_ORDER do
		local material = Gear.Slots[slot].Material
		local short = string.gsub(spaced(material), " Pattern$", "")
		table.insert(parts, `{short} {current.Currencies[material] or 0}`)
	end
	currencyLabel.Text = table.concat(parts, "  ·  ")

	for order, slot in SLOT_ORDER do
		local id = current.Equipped[slot]
		local record = id and current.Items[id]
		if id and record then
			local t = tile(slotsFrame, id, record, order)
			t.Text = `{slot}\n{GearMath.itemName(record.Item)} Lv {record.Level}`
		else
			local empty = label(slotsFrame, `{slot}\nempty`, 14)
			empty.LayoutOrder = order
			empty.TextColor3 = COLORS.faded
		end
	end

	-- Inventory: by slot, then rarity high to low, then level high to low.
	local ids = {}
	for id in current.Items do
		table.insert(ids, id)
	end
	local slotRank = {}
	for index, slot in SLOT_ORDER do
		slotRank[slot] = index
	end
	local items = current.Items
	table.sort(ids, function(a, b)
		local ra, rb = items[a], items[b]
		local sa, sb = slotRank[GearMath.slot(ra.Item) or ""] or 9, slotRank[GearMath.slot(rb.Item) or ""] or 9
		if sa ~= sb then
			return sa < sb
		end
		if ra.Item ~= rb.Item then
			return ra.Item < rb.Item
		end
		local qa, qb = GearMath.rarityIndex(ra.Rarity) or 0, GearMath.rarityIndex(rb.Rarity) or 0
		if qa ~= qb then
			return qa > qb
		end
		if ra.Level ~= rb.Level then
			return ra.Level > rb.Level
		end
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	for order, id in ids do
		tile(inventory, id, current.Items[id], order)
	end

	if not current.CanChange then
		showMessage("Change gear between runs")
	end
end

local function redraw()
	drawMain()
	if detail.Visible then
		drawDetail()
	end
	if picker.Visible then
		drawPicker()
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Gear"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15 -- above the HUD, below the DEV panel
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- later boxes draw over the main panel
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Enabled = false

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(1, -24, 1, -24)
	panel.BackgroundColor3 = COLORS.back
	corner(panel, 14)
	panelLimit = Instance.new("UISizeConstraint")
	panelLimit.MaxSize = Vector2.new(920, 560)
	panelLimit.Parent = panel
	panel.Parent = gui
	mainPanel = panel

	local title = label(panel, "GEAR", 26)
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.fromOffset(90, 34)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = COLORS.gold

	currencyLabel = label(panel, "", 14)
	currencyLabel.Position = UDim2.fromOffset(104, 6)
	currencyLabel.Size = UDim2.new(1, -104 - 56, 0, 34)
	currencyLabel.TextXAlignment = Enum.TextXAlignment.Left
	currencyLabel.Font = Enum.Font.GothamMedium
	currencyLabel.TextScaled = true -- one line, smaller on a phone
	currencyLabel.TextWrapped = false
	local currencyLimit = Instance.new("UITextSizeConstraint")
	currencyLimit.MaxTextSize = 15
	currencyLimit.Parent = currencyLabel

	local close = button(panel, "X", COLORS.danger, function()
		GearController.close()
	end)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -6, 0, 4)
	close.Size = UDim2.fromOffset(BUTTON_HEIGHT, BUTTON_HEIGHT - 4)
	closeButton = close

	-- Left: the 5 equipped slots.
	slotsFrame = Instance.new("Frame")
	slotsFrame.Name = "Slots"
	slotsFrame.Position = UDim2.fromOffset(10, 48)
	slotsFrame.Size = UDim2.new(0.32, -10, 1, -48 - 34)
	slotsFrame.BackgroundTransparency = 1
	local slotLayout = Instance.new("UIListLayout")
	slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotLayout.Padding = UDim.new(0, 6)
	slotLayout.Parent = slotsFrame
	slotsFrame.Parent = panel
	slotsFrame.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") then
			child.Size = UDim2.new(1, 0, 0.2, -5)
		end
	end)

	-- Right: the inventory.
	inventory = Instance.new("ScrollingFrame")
	inventory.Name = "Inventory"
	inventory.Position = UDim2.new(0.32, 6, 0, 48)
	inventory.Size = UDim2.new(0.68, -16, 1, -48 - 34)
	inventory.BackgroundColor3 = COLORS.box
	inventory.BorderSizePixel = 0
	inventory.ScrollBarThickness = 6
	inventory.CanvasSize = UDim2.new()
	inventory.AutomaticCanvasSize = Enum.AutomaticSize.Y
	corner(inventory, 10)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(104, 56)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = inventory
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.Parent = inventory
	inventory.Parent = panel

	messageLabel = label(panel, "", 15)
	messageLabel.AnchorPoint = Vector2.new(0, 1)
	messageLabel.Position = UDim2.new(0, 12, 1, -4)
	messageLabel.Size = UDim2.new(1, -24, 0, 26)
	messageLabel.TextColor3 = COLORS.gold
	messageLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Detail box
	detail = modal("Detail", 340, 300)
	detailTitle = label(detail, "", 22)
	detailTitle.Position = UDim2.fromOffset(12, 8)
	detailTitle.Size = UDim2.new(1, -64, 0, 30)
	detailTitle.TextXAlignment = Enum.TextXAlignment.Left
	detailTitle.ZIndex = 6
	detailBody = label(detail, "", 15)
	detailBody.Position = UDim2.fromOffset(12, 40)
	detailBody.Size = UDim2.new(1, -24, 0, 78)
	detailBody.TextXAlignment = Enum.TextXAlignment.Left
	detailBody.TextYAlignment = Enum.TextYAlignment.Top
	detailBody.Font = Enum.Font.GothamMedium
	detailBody.ZIndex = 6
	local detailClose = button(detail, "X", COLORS.danger, function()
		detail.Visible = false
	end)
	detailClose.AnchorPoint = Vector2.new(1, 0)
	detailClose.Position = UDim2.new(1, -6, 0, 6)
	detailClose.Size = UDim2.fromOffset(40, 36)
	local actions = Instance.new("Frame")
	actions.BackgroundTransparency = 1
	actions.Position = UDim2.fromOffset(12, 124)
	actions.Size = UDim2.new(1, -24, 1, -132)
	local actionLayout = Instance.new("UIListLayout")
	actionLayout.Padding = UDim.new(0, 6)
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Parent = actions
	actions.Parent = detail
	equipButton = button(actions, "Equip", COLORS.go, function()
		if selectedId then
			send("Equip", selectedId)
		end
	end)
	levelButton = button(actions, "Level up", COLORS.button, function()
		if selectedId then
			send("LevelUp", selectedId)
		end
	end)
	mergeButton = button(actions, "Merge", COLORS.button, function()
		local record = state and selectedId and state.Items[selectedId]
		if record then
			openPicker(record.Item, record.Rarity)
		end
	end)
	salvageButton = button(actions, "Salvage", COLORS.danger, function()
		local id = selectedId
		local record = state and id and state.Items[id]
		if not (id and record) then
			return
		end
		local index = GearMath.rarityIndex(record.Rarity) or 1
		if index >= 4 then -- Epic and Legendary ask first
			askConfirm(`Salvage this {record.Rarity} {GearMath.itemName(record.Item)}?`, function()
				send("Salvage", id)
			end)
		else
			send("Salvage", id)
		end
	end)
	for order, b in { equipButton, levelButton, mergeButton, salvageButton } do
		b.LayoutOrder = order
		b.Size = UDim2.new(1, 0, 0, 36)
		b.ZIndex = 6
	end

	-- Pick-3 merge
	picker = modal("Merge", 380, 330)
	local pickerTitle = label(picker, `Merge: pick {Gear.MergeCopies} copies`, 20)
	pickerTitle.Position = UDim2.fromOffset(12, 8)
	pickerTitle.Size = UDim2.new(1, -24, 0, 28)
	pickerTitle.ZIndex = 6
	pickerList = Instance.new("ScrollingFrame")
	pickerList.Position = UDim2.fromOffset(12, 40)
	pickerList.Size = UDim2.new(0.45, -12, 1, -40 - 56)
	pickerList.BackgroundTransparency = 1
	pickerList.BorderSizePixel = 0
	pickerList.ScrollBarThickness = 4
	pickerList.CanvasSize = UDim2.new()
	pickerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pickerList.ZIndex = 6
	local pickerLayout = Instance.new("UIListLayout")
	pickerLayout.Padding = UDim.new(0, 4)
	pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pickerLayout.Parent = pickerList
	pickerList.Parent = picker
	pickerSummary = label(picker, "", 14)
	pickerSummary.Position = UDim2.new(0.45, 6, 0, 40)
	pickerSummary.Size = UDim2.new(0.55, -18, 1, -40 - 56)
	pickerSummary.TextXAlignment = Enum.TextXAlignment.Left
	pickerSummary.TextYAlignment = Enum.TextYAlignment.Top
	pickerSummary.Font = Enum.Font.GothamMedium
	pickerSummary.ZIndex = 6
	pickerConfirm = button(picker, "Merge", COLORS.go, function()
		local ids = pickedIds()
		if #ids == Gear.MergeCopies then
			send("Merge", ids)
			picker.Visible = false
		end
	end)
	pickerConfirm.AnchorPoint = Vector2.new(1, 1)
	pickerConfirm.Position = UDim2.new(1, -12, 1, -8)
	pickerConfirm.Size = UDim2.new(0.5, -18, 0, BUTTON_HEIGHT)
	pickerConfirm.ZIndex = 6
	local pickerCancel = button(picker, "Cancel", COLORS.button, function()
		picker.Visible = false
	end)
	pickerCancel.AnchorPoint = Vector2.new(0, 1)
	pickerCancel.Position = UDim2.new(0, 12, 1, -8)
	pickerCancel.Size = UDim2.new(0.5, -18, 0, BUTTON_HEIGHT)
	pickerCancel.ZIndex = 6

	-- Confirm box
	confirmBox = modal("Confirm", 320, 150)
	confirmBox.ZIndex = 8
	confirmText = label(confirmBox, "", 18)
	confirmText.Position = UDim2.fromOffset(12, 12)
	confirmText.Size = UDim2.new(1, -24, 0, 60)
	confirmText.ZIndex = 9
	local yes = button(confirmBox, "Salvage", COLORS.danger, function()
		confirmBox.Visible = false
		confirmYes()
	end)
	yes.AnchorPoint = Vector2.new(1, 1)
	yes.Position = UDim2.new(1, -12, 1, -10)
	yes.Size = UDim2.new(0.5, -18, 0, BUTTON_HEIGHT)
	yes.ZIndex = 9
	local no = button(confirmBox, "Keep it", COLORS.button, function()
		confirmBox.Visible = false
	end)
	no.AnchorPoint = Vector2.new(0, 1)
	no.Position = UDim2.new(0, 12, 1, -10)
	no.Size = UDim2.new(0.5, -18, 0, BUTTON_HEIGHT)
	no.ZIndex = 9
end

-- Open the Gear screen.
function GearController.open()
	showMessage(nil)
	detail.Visible = false
	picker.Visible = false
	confirmBox.Visible = false
	gui.Enabled = true
	drawMain()
end

function GearController.close()
	gui.Enabled = false
end

-- How far down the lobby's tab bar reaches (pixels); a docked panel starts below it.
local DOCKED_TOP = 72

-- Docked (the lobby's Gear tab): the panel fills the right of the screen under the tab bar,
-- leaving the left for the chef, with no close button (the tabs close it). Undocked: centred,
-- with its close button.
function GearController.setDocked(docked: boolean)
	closeButton.Visible = not docked
	if docked then
		mainPanel.AnchorPoint = Vector2.new(1, 1)
		mainPanel.Position = UDim2.new(1, -12, 1, -12)
		mainPanel.Size = UDim2.new(0.64, -12, 1, -DOCKED_TOP - 12)
		panelLimit.MaxSize = Vector2.new(math.huge, math.huge)
	else
		mainPanel.AnchorPoint = Vector2.new(0.5, 0.5)
		mainPanel.Position = UDim2.fromScale(0.5, 0.5)
		mainPanel.Size = UDim2.new(1, -24, 1, -24)
		panelLimit.MaxSize = Vector2.new(920, 560)
	end
end

function GearController:init()
	build()
end

function GearController:start()
	gearAction = Remotes.get("GearAction")
	Remotes.get("GearState").OnClientEvent:Connect(function(newState: GearState, message: string?)
		state = newState
		if gui.Enabled then
			redraw()
			if message then
				showMessage(message)
			elseif newState.CanChange then
				showMessage(nil)
			end
		end
	end)
	-- A new run closes the screen (it opens again from the run-over banner).
	player:GetAttributeChangedSignal("RunState"):Connect(function()
		if player:GetAttribute("RunState") == "Playing" then
			GearController.close()
		end
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
end

return GearController
