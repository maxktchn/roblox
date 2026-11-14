--!strict
-- DEV panel: playtest buttons (level up, jump the clock, start the boss, give items, heal,
-- god mode, remove enemies). Only built for devs: the server marks them with the "IsDev"
-- attribute. Every button just sends DevAction(action, arg); the server checks who sent it
-- and does the work (DevCommandService), then replies with DevMessage, shown at the top.
--
-- A small "DEV" tab on the left edge opens and closes the panel. It starts closed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gadgets = require(ReplicatedStorage.Config.Gadgets)
local Ingredients = require(ReplicatedStorage.Config.Ingredients)
local Recipes = require(ReplicatedStorage.Config.Recipes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunRules = require(ReplicatedStorage.Config.RunRules)

local DevPanelController = {}

local player = Players.LocalPlayer

local COLORS = {
	panel = Color3.fromRGB(30, 26, 24),
	text = Color3.fromRGB(255, 248, 231),
	faded = Color3.fromRGB(190, 180, 165),
	button = Color3.fromRGB(70, 62, 56),
	gadget = Color3.fromRGB(52, 120, 200),
	ingredient = Color3.fromRGB(46, 160, 67),
	recipe = Color3.fromRGB(200, 150, 20),
	danger = Color3.fromRGB(190, 70, 50),
}

local devAction: RemoteEvent
local gui: ScreenGui
local panel: Frame
local list: ScrollingFrame
local status: TextLabel
local godButton: TextButton
local nextOrder = 0 -- keeps sections in the order they are added
local built = false

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function order(): number
	nextOrder += 1
	return nextOrder
end

local function makeHeader(text: string)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order()
	label.Size = UDim2.new(1, 0, 0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 15
	label.TextColor3 = COLORS.faded
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = list
end

-- A block of buttons that wraps onto as many rows as it needs.
local function makeGrid(): Frame
	local grid = Instance.new("Frame")
	grid.LayoutOrder = order()
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(84, 36) -- big enough for a thumb
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	grid.Parent = list
	return grid
end

local function makeButton(grid: Frame, text: string, color: Color3, onClick: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.LayoutOrder = order()
	button.BackgroundColor3 = color
	button.Font = Enum.Font.FredokaOne
	button.TextColor3 = COLORS.text
	button.TextScaled = true
	button.Text = text
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 16
	limit.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = button
	corner(button, 8)
	button.Activated:Connect(onClick)
	button.Parent = grid
	return button
end

local function send(action: string, arg: any?)
	devAction:FireServer(action, arg)
end

-- Ids sorted by their display name, for a stable button order.
local function sortedByName(ids: { string }, names: { [string]: any }): { string }
	local sorted = table.clone(ids)
	table.sort(sorted, function(a, b)
		return names[a].Name < names[b].Name
	end)
	return sorted
end

local function buildPanel()
	gui = Instance.new("ScreenGui")
	gui.Name = "DevPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20 -- above the "Order Up!" cards, so it works while they're open
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local tab = Instance.new("TextButton")
	tab.Name = "Tab"
	tab.AnchorPoint = Vector2.new(0, 0.5)
	tab.Position = UDim2.new(0, 8, 0.5, 0)
	tab.Size = UDim2.fromOffset(52, 40)
	tab.BackgroundColor3 = COLORS.danger
	tab.Font = Enum.Font.FredokaOne
	tab.TextSize = 18
	tab.TextColor3 = COLORS.text
	tab.Text = "DEV"
	corner(tab, 8)
	tab.Parent = gui

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 68, 0.5, 0)
	panel.Size = UDim2.new(0, 290, 0.8, 0)
	panel.BackgroundColor3 = COLORS.panel
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	corner(panel, 12)
	local maxSize = Instance.new("UISizeConstraint")
	maxSize.MaxSize = Vector2.new(290, 560)
	maxSize.Parent = panel
	panel.Parent = gui

	tab.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Position = UDim2.fromOffset(10, 6)
	status.Size = UDim2.new(1, -20, 0, 24)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamMedium
	status.TextSize = 14
	status.TextColor3 = COLORS.text
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.Text = "Dev tools"
	status.Parent = panel

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(10, 34)
	list.Size = UDim2.new(1, -14, 1, -40)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	makeHeader("RUN")
	local run = makeGrid()
	makeButton(run, "+1 Level", COLORS.button, function()
		send("LevelUp", 1)
	end)
	makeButton(run, "+5 Levels", COLORS.button, function()
		send("LevelUp", 5)
	end)
	makeButton(run, "Heal", COLORS.button, function()
		send("Heal")
	end)
	godButton = makeButton(run, "God: OFF", COLORS.button, function()
		send("God")
	end)
	makeButton(run, "Wipe enemies", COLORS.danger, function()
		send("Wipe")
	end)
	makeButton(run, "Restart run", COLORS.danger, function()
		send("Restart")
	end)

	makeHeader("JUMP TO TIME")
	local time = makeGrid()
	for _, seconds in { 60, 120, 300, 540, 590 } do
		makeButton(time, string.format("%d:%02d", seconds // 60, seconds % 60), COLORS.button, function()
			send("SetTime", seconds)
		end)
	end
	makeButton(time, "BOSS NOW", COLORS.danger, function()
		send("Boss")
	end)

	makeHeader("GIVE (+1 level each tap)")
	local give = makeGrid()
	for _, id in sortedByName(RunRules.UpgradePool.Gadgets, Gadgets) do
		makeButton(give, Gadgets[id].Name, COLORS.gadget, function()
			send("Give", id)
		end)
	end
	for _, id in sortedByName(RunRules.UpgradePool.Ingredients, Ingredients) do
		makeButton(give, Ingredients[id].Name, COLORS.ingredient, function()
			send("Give", id)
		end)
	end
	-- Only recipes with numbers in config can be played.
	local recipeIds = {}
	for id, recipe in Recipes do
		if recipe.Levels then
			table.insert(recipeIds, id)
		end
	end
	for _, id in sortedByName(recipeIds, Recipes) do
		makeButton(give, Recipes[id].Name, COLORS.recipe, function()
			send("Give", id)
		end)
	end
end

local function updateGodButton()
	godButton.Text = if player:GetAttribute("DevGod") then "God: ON" else "God: OFF"
end

-- Build and show the panel once the server says this player is a dev.
local function showIfDev()
	if built or not player:GetAttribute("IsDev") then
		return
	end
	built = true
	buildPanel()
	updateGodButton()
	player:GetAttributeChangedSignal("DevGod"):Connect(updateGodButton)
	Remotes.get("DevMessage").OnClientEvent:Connect(function(text: string)
		status.Text = text
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
end

function DevPanelController:start()
	devAction = Remotes.get("DevAction")
	showIfDev()
	player:GetAttributeChangedSignal("IsDev"):Connect(showIfDev)
end

return DevPanelController
