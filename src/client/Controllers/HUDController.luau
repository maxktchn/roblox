--!strict
-- In-run HUD: HP bar, tip bar + level, timer, kill count, owned items, pause (PRD §7.2).
--
-- The HUD only reads attributes the server puts on the player, and redraws when they change:
--   "Level", "Tips", "TipsNeeded"   UpgradeService (tip bar)
--   "Kills"                         WeaponService
--   "Weapon_<id>", "Ingredient_<id>" WeaponService / StatsService (owned item icons)
--   "RunSeconds"                    RunManager, run timer in whole seconds (#6)
--   "Hp", "MaxHp"                   RunManager, the chef's HP (#9)
--   "RunState"                      RunManager: "Playing", "Lost" or "Won" (shows the run-over banner)
-- If Hp/MaxHp are missing the HP bar shows the Humanoid's health instead, and the
-- timer shows "--:--" until RunSeconds exists.
-- Pause button: not in Phase 1 yet (the run already pauses during "Order Up!").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gadgets = require(ReplicatedStorage.Config.Gadgets)
local Ingredients = require(ReplicatedStorage.Config.Ingredients)
local Recipes = require(ReplicatedStorage.Config.Recipes)
local Starters = require(ReplicatedStorage.Config.Starters)

local HUDController = {}

local player = Players.LocalPlayer

local COLORS = {
	paper = Color3.fromRGB(255, 248, 231),
	ink = Color3.fromRGB(45, 35, 30),
	barBack = Color3.fromRGB(40, 32, 28),
	tips = Color3.fromRGB(240, 185, 40), -- gold tips
	hpHigh = Color3.fromRGB(70, 190, 80),
	hpLow = Color3.fromRGB(220, 60, 50),
}

-- Icon colours by item type (same idea as the Order Up! cards).
local ICON_COLORS = {
	Starter = Color3.fromRGB(214, 84, 40),
	Gadget = Color3.fromRGB(52, 120, 200),
	Recipe = Color3.fromRGB(230, 175, 30),
	Ingredient = Color3.fromRGB(46, 160, 67),
}

local ICON_SIZE = 38 -- pixels

local gui: ScreenGui
local levelLabel: TextLabel
local tipFill: Frame
local tipText: TextLabel
local timerLabel: TextLabel
local killsLabel: TextLabel
local iconRow: Frame
local hpBillboard: BillboardGui
local hpFill: Frame
local runOverPanel: Frame
local runOverTitle: TextLabel
local runOverStats: TextLabel

-- Helper: a text label in the game font.
local function makeLabel(parent: Instance, name: string, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = size
	label.TextColor3 = COLORS.paper
	label.TextStrokeTransparency = 0.4 -- dark outline so text reads on any floor
	label.Parent = parent
	return label
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function buildScreen()
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- clear of notches (PRD §7.4)

	-- Top centre: level badge + tip bar.
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundTransparency = 1
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 12)
	top.Size = UDim2.new(0.55, 0, 0, 34)
	top.Parent = gui

	local badge = Instance.new("Frame")
	badge.Name = "LevelBadge"
	badge.Size = UDim2.fromOffset(64, 34)
	badge.BackgroundColor3 = COLORS.tips
	corner(badge, UDim.new(0, 10))
	badge.Parent = top
	levelLabel = makeLabel(badge, "Level", 20)
	levelLabel.Size = UDim2.fromScale(1, 1)
	levelLabel.TextColor3 = COLORS.ink
	levelLabel.TextStrokeTransparency = 1

	local bar = Instance.new("Frame")
	bar.Name = "TipBar"
	bar.Position = UDim2.fromOffset(72, 5)
	bar.Size = UDim2.new(1, -72, 0, 24)
	bar.BackgroundColor3 = COLORS.barBack
	bar.BackgroundTransparency = 0.2
	corner(bar, UDim.new(0, 8))
	bar.Parent = top
	tipFill = Instance.new("Frame")
	tipFill.Name = "Fill"
	tipFill.BackgroundColor3 = COLORS.tips
	tipFill.Size = UDim2.fromScale(0, 1)
	corner(tipFill, UDim.new(0, 8))
	tipFill.Parent = bar
	tipText = makeLabel(bar, "Text", 16)
	tipText.Size = UDim2.fromScale(1, 1)
	tipText.ZIndex = 2

	-- Under the bar: timer in the middle, kills on the right.
	timerLabel = makeLabel(gui, "Timer", 30)
	timerLabel.AnchorPoint = Vector2.new(0.5, 0)
	timerLabel.Position = UDim2.new(0.5, 0, 0, 52)
	timerLabel.Size = UDim2.fromOffset(120, 34)

	killsLabel = makeLabel(gui, "Kills", 22)
	killsLabel.AnchorPoint = Vector2.new(1, 0)
	killsLabel.Position = UDim2.new(1, -16, 0, 14)
	killsLabel.Size = UDim2.fromOffset(160, 30)
	killsLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- Top left: one small icon per owned weapon and ingredient.
	iconRow = Instance.new("Frame")
	iconRow.Name = "Owned"
	iconRow.BackgroundTransparency = 1
	iconRow.Position = UDim2.fromOffset(16, 14)
	iconRow.Size = UDim2.fromOffset((ICON_SIZE + 6) * 4, (ICON_SIZE + 6) * 2)
	iconRow.Parent = gui
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = iconRow

	-- HP bar floating above the chef (PRD §7.2). Lives in PlayerGui, pointed at the chef.
	hpBillboard = Instance.new("BillboardGui")
	hpBillboard.Name = "ChefHp"
	hpBillboard.Size = UDim2.fromOffset(72, 10)
	hpBillboard.StudsOffset = Vector3.new(0, 3.4, 0)
	hpBillboard.AlwaysOnTop = true
	hpBillboard.ResetOnSpawn = false
	local hpBack = Instance.new("Frame")
	hpBack.Size = UDim2.fromScale(1, 1)
	hpBack.BackgroundColor3 = COLORS.barBack
	corner(hpBack, UDim.new(0, 4))
	hpBack.Parent = hpBillboard
	hpFill = Instance.new("Frame")
	hpFill.Name = "Fill"
	hpFill.Size = UDim2.fromScale(1, 1)
	hpFill.BackgroundColor3 = COLORS.hpHigh
	corner(hpFill, UDim.new(0, 4))
	hpFill.Parent = hpBack

	-- Shown in the middle of the screen when the run is over (won or lost).
	runOverPanel = Instance.new("Frame")
	runOverPanel.Name = "RunOver"
	runOverPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	runOverPanel.Position = UDim2.fromScale(0.5, 0.45)
	runOverPanel.Size = UDim2.fromOffset(420, 150)
	runOverPanel.BackgroundColor3 = COLORS.barBack
	runOverPanel.BackgroundTransparency = 0.15
	runOverPanel.Visible = false
	corner(runOverPanel, UDim.new(0, 16))
	runOverPanel.Parent = gui
	runOverTitle = makeLabel(runOverPanel, "Title", 48)
	runOverTitle.Size = UDim2.new(1, 0, 0, 70)
	runOverTitle.Position = UDim2.fromOffset(0, 14)
	runOverStats = makeLabel(runOverPanel, "Stats", 22)
	runOverStats.Size = UDim2.new(1, 0, 0, 40)
	runOverStats.Position = UDim2.fromOffset(0, 88)
end

-- The run-over banner, with how far the player got.
local function updateRunState()
	local state = player:GetAttribute("RunState")
	local over = state == "Lost" or state == "Won"
	runOverPanel.Visible = over
	if over then
		if state == "Won" then
			runOverTitle.Text = "SHIFT SURVIVED!"
			runOverTitle.TextColor3 = COLORS.tips
		else
			runOverTitle.Text = "SHIFT OVER"
			runOverTitle.TextColor3 = COLORS.hpLow
		end
		runOverStats.Text =
			`Reached Lv {player:GetAttribute("Level") or 1} · Defeated {player:GetAttribute("Kills") or 0}`
	end
end

-- Tip bar, level, kills and timer from the player's attributes.
local function updateNumbers()
	local level = player:GetAttribute("Level")
	local tips = player:GetAttribute("Tips")
	local needed = player:GetAttribute("TipsNeeded")
	levelLabel.Text = `Lv {if type(level) == "number" then level else 1}`
	if type(tips) == "number" and type(needed) == "number" and needed > 0 then
		tipFill.Size = UDim2.fromScale(math.clamp(tips / needed, 0, 1), 1)
		tipText.Text = `{tips} / {needed} tips`
	else
		tipFill.Size = UDim2.fromScale(0, 1)
		tipText.Text = ""
	end

	local kills = player:GetAttribute("Kills")
	killsLabel.Text = `Defeated {if type(kills) == "number" then kills else 0}`

	local seconds = player:GetAttribute("RunSeconds")
	if type(seconds) == "number" then
		timerLabel.Text = string.format("%d:%02d", seconds // 60, seconds % 60)
	else
		timerLabel.Text = "--:--" -- RunManager's timer isn't running yet (#6)
	end
end

-- HP: RunManager's attributes if it sets them (#9), otherwise the Humanoid's health.
local function updateHp()
	local hp = player:GetAttribute("Hp")
	local maxHp = player:GetAttribute("MaxHp")
	if type(hp) ~= "number" or type(maxHp) ~= "number" then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		hp = humanoid and humanoid.Health or 0
		maxHp = humanoid and humanoid.MaxHealth or 1
	end
	local fraction = if (maxHp :: number) > 0 then math.clamp((hp :: number) / (maxHp :: number), 0, 1) else 0
	hpFill.Size = UDim2.fromScale(fraction, 1)
	hpFill.BackgroundColor3 = COLORS.hpLow:Lerp(COLORS.hpHigh, fraction)
end

-- Which kind of item an attribute id is, its display name, and its sort group.
local function describeItem(kind: string, id: string): (string?, string, number)
	if kind == "Ingredient" then
		local ingredient = Ingredients[id]
		return if ingredient then "Ingredient" else nil, if ingredient then ingredient.Name else id, 3
	end
	if Starters[id] then
		return "Starter", Starters[id].Name, 1
	elseif Recipes[id] then
		-- A starter's recipe stays first in the row; a gadget's recipe sits with the gadgets.
		return "Recipe", Recipes[id].Name, if Starters[Recipes[id].Weapon] then 1 else 2
	elseif Gadgets[id] then
		return "Gadget", Gadgets[id].Name, 2
	end
	return nil, id, 9
end

-- Rebuild the owned item icons (only when a Weapon_/Ingredient_ attribute changes).
local function updateIcons()
	for _, child in iconRow:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local items = {}
	for name, value in player:GetAttributes() do
		local kind, id = string.match(name, "^(%a+)_(%w+)$")
		if (kind == "Weapon" or kind == "Ingredient") and id and type(value) == "number" and value > 0 then
			local itemKind, itemName, group = describeItem(kind :: string, id)
			if itemKind then
				table.insert(items, { kind = itemKind, name = itemName, level = value, group = group })
			end
		end
	end
	table.sort(items, function(a, b)
		if a.group ~= b.group then
			return a.group < b.group
		end
		return a.name < b.name
	end)

	for order, item in items do
		local icon = Instance.new("Frame")
		icon.Name = item.name
		icon.LayoutOrder = order
		icon.BackgroundColor3 = ICON_COLORS[item.kind]
		corner(icon, UDim.new(0.5, 0))
		local stroke = Instance.new("UIStroke")
		stroke.Color = COLORS.paper
		stroke.Thickness = 2
		stroke.Parent = icon
		local letter = makeLabel(icon, "Letter", 20)
		letter.Size = UDim2.fromScale(1, 1)
		letter.Text = string.sub(item.name, 1, 1)
		-- Level in the corner (recipes have no levels, so they show a star).
		local level = makeLabel(icon, "Level", 13)
		level.AnchorPoint = Vector2.new(1, 1)
		level.Position = UDim2.fromScale(1.05, 1.1)
		level.Size = UDim2.fromOffset(16, 14)
		level.Text = if item.kind == "Recipe" then "★" else tostring(item.level)
		icon.Parent = iconRow
	end
end

-- Point the HP bar at the current chef (again after each respawn).
local function attachHpBar(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and root:IsA("BasePart") then
		hpBillboard.Adornee = root
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.HealthChanged:Connect(updateHp)
	end
	updateHp()
end

function HUDController:init()
	buildScreen()
end

function HUDController:start()
	local playerGui = player:WaitForChild("PlayerGui")
	gui.Parent = playerGui
	hpBillboard.Parent = playerGui

	updateNumbers()
	updateIcons()
	updateRunState()
	player.AttributeChanged:Connect(function(name: string)
		if string.match(name, "^Weapon_") or string.match(name, "^Ingredient_") then
			updateIcons()
		elseif name == "Hp" or name == "MaxHp" then
			updateHp()
		elseif name == "RunState" then
			updateRunState()
		else
			updateNumbers()
		end
	end)

	if player.Character then
		task.spawn(attachHpBar, player.Character)
	end
	player.CharacterAdded:Connect(attachHpBar)
end

return HUDController
