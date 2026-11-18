--!strict
-- The lobby (P2-8 #143-#145, PRD §7.1, design: docs/superpowers/specs/2026-11-17-lobby-design.md).
--
-- The server's run state ("RunState" player attribute) is "Lobby" between runs: on joining and
-- after Continue on the run-over banner. While it is, this controller shows the lobby and keeps
-- the chef standing still in the kitchen (their root part is anchored here on the client, the way
-- the "Order Up!" card screen freezes them).
--
-- Tabs across the top: HOME, GEAR, TALENTS, CHAPTERS, SHOP, COOKBOOK. The lobby always opens on
-- HOME. HOME and the flat tabs sit over the kitchen, blurred. GEAR turns the camera to face the
-- chef and docks the Gear screen (GearController) on the right. Talents, Chapters and Shop say
-- "Coming soon" until their topics (#107, #108) fill them.
--
-- Reads: "RunState", "Chapter" (RunManager), "LifetimeRuns"/"LifetimeWins"/"BestWinSeconds"
-- (DataService), and the GearState remote (gold and the Utensil item, GearService).
-- Sends: RequestRestart when Play is tapped (accepted only in the lobby).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraController = require(script.Parent.CameraController)
local Chapters = require(ReplicatedStorage.Config.Chapters)
local Gear = require(ReplicatedStorage.Config.Gear)
local GearController = require(script.Parent.GearController)
local GearMath = require(ReplicatedStorage.Shared.GearMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LobbyController = {}

local player = Players.LocalPlayer

local TAB_NAMES = { "HOME", "GEAR", "TALENTS", "CHAPTERS", "SHOP", "COOKBOOK" }
-- The "Coming soon" tabs: what each will hold.
local COMING_SOON: { [string]: string } = {
	TALENTS = "Spend gold on permanent upgrades",
	CHAPTERS = "Pick which kitchen to cook in",
	SHOP = "Chests and more",
}
local TAB_BAR_HEIGHT = 48 -- big enough for a thumb (PRD §7.4)
local BLUR_SIZE = 18

local COLORS = {
	back = Color3.fromRGB(30, 26, 24),
	box = Color3.fromRGB(55, 48, 43),
	paper = Color3.fromRGB(255, 248, 231),
	faded = Color3.fromRGB(190, 180, 165),
	gold = Color3.fromRGB(240, 185, 40),
	ink = Color3.fromRGB(45, 35, 30),
	tab = Color3.fromRGB(70, 62, 56),
}

type GearState = {
	Items: { [string]: { Item: string, Rarity: string, Level: number } },
	Equipped: { [string]: string },
	Currencies: { [string]: number },
}

local gui: ScreenGui
local blur: BlurEffect
local goldLabel: TextLabel
local tabButtons: { [string]: TextButton } = {}
local pages: { [string]: Frame } = {} -- one page per tab except GEAR (that's GearController)
local itemLabel: TextLabel
local chapterLabel: TextLabel
local statsLabel: TextLabel
local playButton: TextButton
local gearState: GearState? = nil
local currentTab = "HOME"

local function inLobby(): boolean
	return player:GetAttribute("RunState") == "Lobby"
end

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

-- A centred panel over the blurred kitchen (Home, the "Coming soon" tabs, the Cookbook).
local function page(name: string, width: number, height: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(0.5, 0, 0.5, TAB_BAR_HEIGHT / 2)
	f.Size = UDim2.new(0.92, 0, 1, -TAB_BAR_HEIGHT - 40)
	f.BackgroundColor3 = COLORS.back
	f.BackgroundTransparency = 0.15
	f.Visible = false
	corner(f, 14)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(width, height)
	limit.Parent = f
	f.Parent = gui
	return f
end

-- 342 -> "5:42"
local function formatTime(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

--------------------------------------------------------------------------------
-- Home
--------------------------------------------------------------------------------

local function drawHome()
	local chapterId = player:GetAttribute("Chapter")
	local chapter = if type(chapterId) == "string" then Chapters[chapterId] else nil
	chapterLabel.Text = if chapter then `Chapter {chapter.Order}: {chapter.Name}` else ""

	local state = gearState
	local id = state and state.Equipped.Utensil
	local record = state and id and state.Items[id]
	if record then
		local index = GearMath.rarityIndex(record.Rarity)
		itemLabel.Text = `{GearMath.itemName(record.Item)} ({record.Rarity} Lv {record.Level})`
		itemLabel.TextColor3 = if index then Gear.Rarities[index].Color else COLORS.paper
	else
		itemLabel.Text = "Loading..."
		itemLabel.TextColor3 = COLORS.faded
	end

	local runs = player:GetAttribute("LifetimeRuns")
	local wins = player:GetAttribute("LifetimeWins")
	local best = player:GetAttribute("BestWinSeconds")
	if type(runs) ~= "number" then
		statsLabel.Text = ""
	elseif type(wins) == "number" and wins > 0 and type(best) == "number" and best > 0 then
		statsLabel.Text = `Runs {runs} · Wins {wins} · Best {formatTime(best)}`
	else
		statsLabel.Text = `Runs {runs} · No wins yet`
	end

	goldLabel.Text = if state then `Gold {state.Currencies.Gold or 0}` else "Gold: Loading..."
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

-- Show one tab: its page, the camera and blur it wants, and the Gear screen for GEAR.
function LobbyController.showTab(name: string)
	if not table.find(TAB_NAMES, name) then
		return
	end
	currentTab = name
	gui:SetAttribute("Tab", name) -- for tests
	for tabName, button in tabButtons do
		local selected = tabName == name
		button.BackgroundColor3 = if selected then COLORS.gold else COLORS.tab
		button.TextColor3 = if selected then COLORS.ink else COLORS.paper
	end
	for pageName, frame in pages do
		frame.Visible = pageName == name
	end
	local onGear = name == "GEAR"
	blur.Enabled = not onGear
	CameraController.setLobbyView(if onGear then "Gear" else "Home")
	if onGear then
		GearController.setDocked(true)
		GearController.open()
	else
		GearController.close()
	end
	if name == "HOME" then
		drawHome()
	end
end

-- Show or hide the whole lobby with the run state. It always opens on HOME.
local function syncLobby()
	local lobby = inLobby()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = lobby -- the chef stands still in the lobby
	end
	if lobby == gui.Enabled then
		return
	end
	gui.Enabled = lobby
	if lobby then
		playButton.Text = "PLAY"
		playButton.Active = true
		LobbyController.showTab("HOME")
	else
		blur.Enabled = false
		CameraController.setLobbyView(nil)
		GearController.close()
		GearController.setDocked(false)
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Lobby"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 14 -- under the Gear screen (15) and the DEV panel
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Enabled = false

	blur = Instance.new("BlurEffect")
	blur.Name = "LobbyBlur"
	blur.Size = BLUR_SIZE
	blur.Enabled = false
	blur.Parent = Lighting

	-- Tab bar across the top, gold on the right.
	local bar = Instance.new("Frame")
	bar.Name = "TabBar"
	bar.Position = UDim2.fromOffset(12, 8)
	bar.Size = UDim2.new(1, -24 - 150, 0, TAB_BAR_HEIGHT)
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = bar
	for order, name in TAB_NAMES do
		local b = Instance.new("TextButton")
		b.Name = `Tab_{name}`
		b.LayoutOrder = order
		b.Size = UDim2.new(1 / #TAB_NAMES, -6, 1, 0)
		b.BackgroundColor3 = COLORS.tab
		b.Font = Enum.Font.FredokaOne
		b.TextScaled = true -- the 6 tabs share the width; text shrinks on a phone
		b.TextColor3 = COLORS.paper
		b.Text = name
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 20
		limit.Parent = b
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 4)
		padding.PaddingRight = UDim.new(0, 4)
		padding.PaddingTop = UDim.new(0, 8)
		padding.PaddingBottom = UDim.new(0, 8)
		padding.Parent = b
		corner(b, 10)
		b.Activated:Connect(function()
			LobbyController.showTab(name)
		end)
		b.Parent = bar
		tabButtons[name] = b
	end
	goldLabel = label(gui, "Gold", "Gold: Loading...", 18)
	goldLabel.AnchorPoint = Vector2.new(1, 0)
	goldLabel.Position = UDim2.new(1, -12, 0, 8)
	goldLabel.Size = UDim2.fromOffset(140, TAB_BAR_HEIGHT)
	goldLabel.TextXAlignment = Enum.TextXAlignment.Right
	goldLabel.TextColor3 = COLORS.gold

	-- HOME
	local home = page("Home", 480, 320)
	pages.HOME = home
	local homeLayout = Instance.new("UIListLayout")
	homeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	homeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	homeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	homeLayout.Padding = UDim.new(0, 10)
	homeLayout.Parent = home
	chapterLabel = label(home, "Chapter", "", 30)
	chapterLabel.TextColor3 = COLORS.gold
	itemLabel = label(home, "Item", "Loading...", 20)
	statsLabel = label(home, "Stats", "", 16)
	statsLabel.Font = Enum.Font.GothamMedium
	statsLabel.TextColor3 = COLORS.faded
	for order, l in { chapterLabel, itemLabel, statsLabel } do
		l.LayoutOrder = order
		l.Size = UDim2.new(1, -24, 0, l.TextSize + 10)
	end
	playButton = Instance.new("TextButton")
	playButton.Name = "Play"
	playButton.LayoutOrder = 4
	playButton.Size = UDim2.fromOffset(240, 64)
	playButton.BackgroundColor3 = COLORS.gold
	playButton.Font = Enum.Font.FredokaOne
	playButton.TextSize = 32
	playButton.TextColor3 = COLORS.ink
	playButton.Text = "PLAY"
	corner(playButton, 14)
	playButton.Parent = home

	-- TALENTS, CHAPTERS, SHOP: "Coming soon" until their topics fill them.
	for name, line in COMING_SOON do
		local p = page(name, 420, 220)
		pages[name] = p
		local title = label(p, "Title", name, 30)
		title.Position = UDim2.fromScale(0, 0.18)
		title.Size = UDim2.new(1, 0, 0, 40)
		title.TextColor3 = COLORS.gold
		local what = label(p, "Line", line, 18)
		what.Position = UDim2.fromScale(0, 0.45)
		what.Size = UDim2.new(1, -24, 0, 30)
		what.Font = Enum.Font.GothamMedium
		local soon = label(p, "Soon", "Coming soon", 22)
		soon.Position = UDim2.fromScale(0, 0.68)
		soon.Size = UDim2.new(1, 0, 0, 30)
		soon.TextColor3 = COLORS.faded
	end

	-- COOKBOOK (#145 fills it).
	pages.COOKBOOK = page("Cookbook", 860, 520)
end

function LobbyController:init()
	build()
end

function LobbyController:start()
	local requestRestart = Remotes.get("RequestRestart")
	playButton.Activated:Connect(function()
		if not playButton.Active then
			return -- already asked: wait for the run
		end
		playButton.Active = false
		playButton.Text = "..."
		requestRestart:FireServer()
	end)

	Remotes.get("GearState").OnClientEvent:Connect(function(state: GearState)
		gearState = state
		if gui.Enabled then
			drawHome()
		end
	end)
	player.AttributeChanged:Connect(function(name: string)
		if name == "RunState" then
			syncLobby()
		elseif name == "Chapter" or name == "LifetimeRuns" or name == "LifetimeWins" or name == "BestWinSeconds" then
			if gui.Enabled then
				drawHome()
			end
		end
	end)
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		syncLobby()
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
	syncLobby()
end

return LobbyController
