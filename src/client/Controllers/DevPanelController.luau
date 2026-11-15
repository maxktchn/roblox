--!strict
-- DEV panel: playtest buttons (level up, jump the clock, start the boss, give items, heal,
-- god mode, remove enemies, the playtest bot). Only built for devs: the server marks them with the "IsDev"
-- attribute. Every button just sends DevAction(action, arg); the server checks who sent it
-- and does the work (DevCommandService), then replies with DevMessage, shown at the top.
--
-- A small "DEV" tab on the left edge opens and closes the panel. It starts closed.
-- When a run ends, the server's run report (RunReportService) pops up on the right.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossPowers = require(ReplicatedStorage.Config.BossPowers)
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
local reportBox: Frame
local reportText: TextLabel
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
	makeButton(run, "Unlock powers", COLORS.recipe, function()
		send("UnlockPowers")
	end)

	makeHeader("PLAYTEST BOT (plays by itself, then reports)")
	local bot = makeGrid()
	makeButton(bot, "Bot: 3 runs", COLORS.recipe, function()
		send("Bot", 3)
	end)
	makeButton(bot, "Bot: 6 runs", COLORS.recipe, function()
		send("Bot", 6)
	end)
	makeButton(bot, "Stop bot", COLORS.danger, function()
		send("Bot", 0)
	end)

	makeHeader("JUMP TO TIME")
	local time = makeGrid()
	-- Follows the run length: 1:00, 2:00, halfway, a minute before the boss, 10 s before it.
	local runLength = RunRules.RunLengthSeconds
	for _, seconds in { 60, 120, runLength // 2, runLength - 60, runLength - 10 } do
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
	-- Boss powers: given even if not unlocked yet (testing).
	for _, id in sortedByName(RunRules.UpgradePool.BossPowers, BossPowers) do
		makeButton(give, BossPowers[id].Name, COLORS.danger, function()
			send("Give", id)
		end)
	end
end

local function updateGodButton()
	godButton.Text = if player:GetAttribute("DevGod") then "God: ON" else "God: OFF"
end

-- Build and show the panel once the server says this player is a dev.
-- The end-of-run report: a box on the right with a close button. Hidden until a report arrives.
local function buildReportBox()
	reportBox = Instance.new("Frame")
	reportBox.Name = "RunReport"
	reportBox.AnchorPoint = Vector2.new(1, 0.5)
	reportBox.Position = UDim2.new(1, -8, 0.5, 0)
	reportBox.Size = UDim2.new(0, 380, 0.75, 0)
	reportBox.BackgroundColor3 = COLORS.panel
	reportBox.BackgroundTransparency = 0.1
	reportBox.Visible = false
	corner(reportBox, 12)
	local maxSize = Instance.new("UISizeConstraint")
	maxSize.MaxSize = Vector2.new(380, 480)
	maxSize.Parent = reportBox
	reportBox.Parent = gui

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(1, -60, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 18
	title.TextColor3 = COLORS.text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Run report (also in Output)"
	title.Parent = reportBox

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 6)
	close.Size = UDim2.fromOffset(36, 28)
	close.BackgroundColor3 = COLORS.danger
	close.Font = Enum.Font.FredokaOne
	close.TextSize = 18
	close.TextColor3 = COLORS.text
	close.Text = "X"
	corner(close, 6)
	close.Activated:Connect(function()
		reportBox.Visible = false
	end)
	close.Parent = reportBox

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(12, 40)
	scroll.Size = UDim2.new(1, -16, 1, -48)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = reportBox

	reportText = Instance.new("TextLabel")
	reportText.Size = UDim2.new(1, -8, 0, 0)
	reportText.AutomaticSize = Enum.AutomaticSize.Y
	reportText.BackgroundTransparency = 1
	reportText.Font = Enum.Font.GothamMedium
	reportText.TextSize = 14
	reportText.TextColor3 = COLORS.text
	reportText.TextWrapped = true
	reportText.TextXAlignment = Enum.TextXAlignment.Left
	reportText.TextYAlignment = Enum.TextYAlignment.Top
	reportText.Parent = scroll
end

local function showIfDev()
	if built or not player:GetAttribute("IsDev") then
		return
	end
	built = true
	buildPanel()
	buildReportBox()
	updateGodButton()
	player:GetAttributeChangedSignal("DevGod"):Connect(updateGodButton)
	Remotes.get("DevMessage").OnClientEvent:Connect(function(text: string)
		status.Text = text
	end)
	-- The playtest bot's progress ("Bot run 2/3: GadgetFirst") shows in the same place.
	player:GetAttributeChangedSignal("BotStatus"):Connect(function()
		status.Text = tostring(player:GetAttribute("BotStatus"))
	end)
	-- One blank line between the report's sections, so it's easier to read.
	Remotes.get("RunReport").OnClientEvent:Connect(function(text: string)
		reportText.Text = (string.gsub(text, "\n", "\n\n"))
		reportBox.Visible = true
	end)
	-- A new run hides the old report.
	player:GetAttributeChangedSignal("RunState"):Connect(function()
		if player:GetAttribute("RunState") == "Playing" then
			reportBox.Visible = false
		end
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
end

function DevPanelController:start()
	devAction = Remotes.get("DevAction")
	showIfDev()
	player:GetAttributeChangedSignal("IsDev"):Connect(showIfDev)
end

return DevPanelController
