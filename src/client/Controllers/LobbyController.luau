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
-- chef and docks the Gear screen (GearController) on the right. TALENTS is the talent path
-- (TalentsController, #163) and SHOP the Basic Chest (ShopController, #164).
--
-- HOME also shows the account level and an XP bar (#161).
--
-- CHAPTERS (#152): one card per chapter by Order, with its twist line and state (ChapterMath).
-- Tapping a playable one selects it and goes back to HOME, which shows it; Play starts it. The
-- selection lasts until the server's own chapter changes (it isn't saved).
--
-- Reads: "RunState", "Chapter" (RunManager), "LifetimeRuns"/"LifetimeWins"/"BestWinSeconds"
-- (DataService), "AccountLevel"/"AccountXp"/"AccountXpNeeded" (TalentService), "Found_<recipeId>" (CookbookService), "Cleared_<chapterId>" (UnlockService),
-- "GearNew" (GearService, the GEAR tab's NEW badge; TalentsController drives the TALENTS one), and the GearState remote (gold and the
-- Utensil item, GearService).
-- Sends: RequestRestart(chapterId) when Play is tapped (accepted only in the lobby, for a chapter
-- the player can play).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraController = require(script.Parent.CameraController)
local ChapterMath = require(ReplicatedStorage.Shared.ChapterMath)
local Chapters = require(ReplicatedStorage.Config.Chapters)
local Gadgets = require(ReplicatedStorage.Config.Gadgets)
local Gear = require(ReplicatedStorage.Config.Gear)
local GearController = require(script.Parent.GearController)
local GearMath = require(ReplicatedStorage.Shared.GearMath)
local Ingredients = require(ReplicatedStorage.Config.Ingredients)
local Recipes = require(ReplicatedStorage.Config.Recipes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunRules = require(ReplicatedStorage.Config.RunRules)
local ShopController = require(script.Parent.ShopController)
local Starters = require(ReplicatedStorage.Config.Starters)
local TalentsController = require(script.Parent.TalentsController)

local LobbyController = {}

local player = Players.LocalPlayer

local TAB_NAMES = { "HOME", "GEAR", "TALENTS", "CHAPTERS", "SHOP", "COOKBOOK" }
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
	newBadge = Color3.fromRGB(220, 60, 50), -- the NEW badge (the HUD's low-HP red)
	hidden = Color3.fromRGB(20, 18, 17), -- an unfound recipe's card
	recipe = Color3.fromRGB(230, 175, 30), -- a found recipe's border (as on the Order Up! cards)
	cleared = Color3.fromRGB(120, 200, 110), -- a cleared chapter's tick
}
local CHAPTER_CARD_HEIGHT = 64 -- full width, well over the 44 px a thumb needs (PRD §7.4)

type GearState = {
	Items: { [string]: { Item: string, Rarity: string, Level: number } },
	Equipped: { [string]: string },
	Currencies: { [string]: number },
}

local gui: ScreenGui
local blur: BlurEffect
local goldLabel: TextLabel
local tabButtons: { [string]: TextButton } = {}
local newBadges: { [string]: TextLabel } = {}
local pages: { [string]: Frame } = {} -- one page per tab except GEAR (that's GearController)
local itemLabel: TextLabel
local chapterLabel: TextLabel
local statsLabel: TextLabel
local accountLabel: TextLabel
local accountFill: Frame
local playButton: TextButton
local gearState: GearState? = nil
local cookbookList: ScrollingFrame
local cookbookCount: TextLabel
local chapterList: ScrollingFrame
local selectedChapter: string? = nil -- picked on the Chapters tab; nil = the server's "Chapter"
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

-- A centred panel over the blurred kitchen (Home, Talents, Shop, Chapters, the Cookbook).
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

-- Chapters won at least once, from the "Cleared_<id>" attributes.
local function clearedChapters(): { [string]: boolean }
	local cleared = {}
	for name, value in player:GetAttributes() do
		local id = string.match(name, "^Cleared_(.+)$")
		if id and value == true then
			cleared[id] = true
		end
	end
	return cleared
end

-- The chapter Play will start: the one picked on the Chapters tab, else the server's.
local function chapterToPlay(): string?
	-- A pick that's no longer playable (a DEV unlock reset) is dropped, so Play is never refused.
	if selectedChapter and ChapterMath.isPlayable(selectedChapter, clearedChapters()) then
		return selectedChapter
	end
	local chapterId = player:GetAttribute("Chapter")
	return if type(chapterId) == "string" then chapterId else nil
end

local function drawHome()
	local chapterId = chapterToPlay()
	local chapter = if chapterId then Chapters[chapterId] else nil
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

	-- Account level and XP (#161).
	local accountLevel = player:GetAttribute("AccountLevel")
	local xp = player:GetAttribute("AccountXp")
	local needed = player:GetAttribute("AccountXpNeeded")
	if type(accountLevel) ~= "number" then
		accountLabel.Text = ""
		accountFill.Size = UDim2.fromScale(0, 1)
	elseif type(needed) == "number" and type(xp) == "number" then
		accountLabel.Text = `Account Lv {accountLevel} · {xp} / {needed} XP`
		accountFill.Size = UDim2.fromScale(math.clamp(xp / needed, 0, 1), 1)
	else
		accountLabel.Text = `Account Lv {accountLevel} (max)`
		accountFill.Size = UDim2.fromScale(1, 1)
	end
end

--------------------------------------------------------------------------------
-- Cookbook (#145)
--------------------------------------------------------------------------------

-- Recipes a run can reach: playable, made from a starter (any Utensil can start a run, #150) or a
-- pool gadget plus a pool ingredient. The others (the Meat Cleaver's...) don't show until they can
-- be made.
local function reachableRecipes(): { string }
	local ids = {}
	for id, recipe in Recipes do
		local weaponInPool = Starters[recipe.Weapon] ~= nil
			or table.find(RunRules.UpgradePool.Gadgets, recipe.Weapon) ~= nil
		local ingredientInPool = table.find(RunRules.UpgradePool.Ingredients, recipe.Ingredient) ~= nil
		if recipe.Levels and weaponInPool and ingredientInPool then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		return Recipes[a].Name < Recipes[b].Name
	end)
	return ids
end

local function weaponName(id: string): string
	local config: any = Starters[id] or Gadgets[id]
	return if config then config.Name else id
end

local function drawCookbook()
	for _, child in cookbookList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local ids = reachableRecipes()
	local found = 0
	for order, id in ids do
		local recipe = Recipes[id]
		local isFound = player:GetAttribute(`Found_{id}`) == true
		if isFound then
			found += 1
		end
		local card = Instance.new("Frame")
		card.Name = `Recipe_{id}`
		card.LayoutOrder = order
		card.BackgroundColor3 = if isFound then COLORS.box else COLORS.hidden
		corner(card, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Color = if isFound then COLORS.recipe else COLORS.tab
		stroke.Thickness = 2
		stroke.Parent = card
		local ingredient = Ingredients[recipe.Ingredient]
		local lines = if isFound
			then {
				recipe.Name,
				`{weaponName(recipe.Weapon)} + {ingredient and ingredient.Name or recipe.Ingredient}`,
				recipe.Description or "",
			}
			else { "???", `{weaponName(recipe.Weapon)} + ???`, "" }
		local title = label(card, "Name", lines[1], 18)
		title.Position = UDim2.fromOffset(8, 6)
		title.Size = UDim2.new(1, -16, 0, 24)
		title.TextColor3 = if isFound then COLORS.recipe else COLORS.faded
		local parts = label(card, "Parts", lines[2], 15)
		parts.Position = UDim2.fromOffset(8, 32)
		parts.Size = UDim2.new(1, -16, 0, 20)
		parts.Font = Enum.Font.GothamMedium
		local description = label(card, "Description", lines[3], 13)
		description.Position = UDim2.fromOffset(8, 54)
		description.Size = UDim2.new(1, -16, 0, 34)
		description.Font = Enum.Font.GothamMedium
		description.TextColor3 = COLORS.faded
		card.Parent = cookbookList
	end
	cookbookCount.Text = `Found {found} of {#ids}`
end

--------------------------------------------------------------------------------
-- Chapters (#152)
--------------------------------------------------------------------------------

local STATE_TEXT: { [string]: string } = {
	Playable = "Play",
	Cleared = "✓ Cleared",
	ComingSoon = "🔒 Coming soon",
}

local drawChapters: () -> ()

local function chapterCard(id: string, cleared: { [string]: boolean }, playing: string?)
	local chapter = Chapters[id]
	local state = ChapterMath.state(id, cleared)
	local playable = state == "Playable" or state == "Cleared"
	local selected = playable and id == playing

	local card = Instance.new("TextButton")
	card.Name = `Chapter_{id}`
	card.LayoutOrder = chapter.Order
	card.Size = UDim2.new(1, -8, 0, CHAPTER_CARD_HEIGHT)
	card.BackgroundColor3 = if playable then COLORS.box else COLORS.hidden
	card.AutoButtonColor = playable
	card.Text = ""
	card:SetAttribute("State", state) -- for tests
	card:SetAttribute("Selected", selected)
	corner(card, 10)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = if selected then COLORS.gold else COLORS.tab
	stroke.Thickness = if selected then 3 else 2
	stroke.Parent = card

	local textColor = if playable then COLORS.paper else COLORS.faded
	local number = label(card, "Number", tostring(chapter.Order), 30)
	number.Position = UDim2.fromOffset(6, 0)
	number.Size = UDim2.new(0, 44, 1, 0)
	number.TextColor3 = if playable then COLORS.gold else COLORS.faded

	local stateText = if state == "Locked"
		then `🔒 Clear Chapter {chapter.Order - 1} first`
		else STATE_TEXT[state :: string]
	if selected then
		stateText ..= " · Selected"
	end
	local stateLabel = label(card, "State", stateText, 16)
	stateLabel.AnchorPoint = Vector2.new(1, 0)
	stateLabel.Position = UDim2.new(1, -12, 0, 0)
	stateLabel.Size = UDim2.fromScale(0.38, 1)
	stateLabel.TextXAlignment = Enum.TextXAlignment.Right
	stateLabel.TextColor3 = if state == "Cleared" then COLORS.cleared elseif selected then COLORS.gold else textColor

	local name = label(card, "Name", chapter.Name, 20)
	name.Position = UDim2.fromOffset(56, 8)
	name.Size = UDim2.new(0.62, -60, 0, 26)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextColor3 = textColor
	local twist = label(card, "Twist", chapter.Notes, 13)
	twist.Position = UDim2.fromOffset(56, 34)
	twist.Size = UDim2.new(0.62, -60, 0, 22)
	twist.TextXAlignment = Enum.TextXAlignment.Left
	twist.TextTruncate = Enum.TextTruncate.AtEnd
	twist.Font = Enum.Font.GothamMedium
	twist.TextColor3 = COLORS.faded

	if playable then
		card.Activated:Connect(function()
			selectedChapter = id
			LobbyController.showTab("HOME")
		end)
	end
	card.Parent = chapterList
end

drawChapters = function()
	for _, child in chapterList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local cleared = clearedChapters()
	local playing = chapterToPlay()
	for _, id in ChapterMath.sortedIds() do
		chapterCard(id, cleared, playing)
	end
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
	elseif name == "COOKBOOK" then
		drawCookbook()
	elseif name == "CHAPTERS" then
		drawChapters()
	elseif name == "SHOP" then
		ShopController.refresh()
	elseif name == "TALENTS" then
		TalentsController.show()
	end
end

-- Show or hide the whole lobby with the run state. It always opens on HOME.
local function syncLobby()
	local lobby = inLobby()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if lobby and root and root:IsA("BasePart") then
		-- The chef stands still in the lobby. Never unanchor here: Play respawns a fresh chef, and
		-- outside the lobby the "Order Up!" card screen may be freezing them on purpose.
		root.Anchored = true
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
		-- NEW badges: GEAR while an item is new and the Gear screen hasn't been opened since
		-- (player attribute "GearNew", GearService; opening Gear clears it, #151). TALENTS while
		-- the next node can be bought (TalentsController, #163).
		if name == "GEAR" or name == "TALENTS" then
			local badge = Instance.new("TextLabel")
			badge.Name = "NewBadge"
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, 6, 0, -6)
			badge.Size = UDim2.fromOffset(44, 20)
			badge.ZIndex = 2
			badge.BackgroundColor3 = COLORS.newBadge
			badge.Font = Enum.Font.FredokaOne
			badge.TextSize = 14
			badge.TextColor3 = Color3.new(1, 1, 1)
			badge.Text = "NEW"
			badge.Visible = false
			corner(badge, 8)
			badge.Parent = b
			newBadges[name] = badge
		end
	end
	local gearBadge = newBadges.GEAR
	gearBadge.Visible = player:GetAttribute("GearNew") == true
	player:GetAttributeChangedSignal("GearNew"):Connect(function()
		gearBadge.Visible = player:GetAttribute("GearNew") == true
	end)
	goldLabel = label(gui, "Gold", "Gold: Loading...", 18)
	goldLabel.AnchorPoint = Vector2.new(1, 0)
	goldLabel.Position = UDim2.new(1, -12, 0, 8)
	goldLabel.Size = UDim2.fromOffset(140, TAB_BAR_HEIGHT)
	goldLabel.TextXAlignment = Enum.TextXAlignment.Right
	goldLabel.TextColor3 = COLORS.gold

	-- HOME
	local home = page("Home", 480, 360)
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
	-- Account level and an XP bar (#161).
	local account = Instance.new("Frame")
	account.Name = "Account"
	account.LayoutOrder = 4
	account.Size = UDim2.new(1, -48, 0, 34)
	account.BackgroundTransparency = 1
	account.Parent = home
	accountLabel = label(account, "Level", "", 15)
	accountLabel.Size = UDim2.new(1, 0, 0, 20)
	accountLabel.Font = Enum.Font.GothamMedium
	local xpBar = Instance.new("Frame")
	xpBar.Name = "Bar"
	xpBar.AnchorPoint = Vector2.new(0.5, 1)
	xpBar.Position = UDim2.fromScale(0.5, 1)
	xpBar.Size = UDim2.new(0.8, 0, 0, 8)
	xpBar.BackgroundColor3 = COLORS.tab
	corner(xpBar, 4)
	xpBar.Parent = account
	accountFill = Instance.new("Frame")
	accountFill.Name = "Fill"
	accountFill.Size = UDim2.fromScale(0, 1)
	accountFill.BackgroundColor3 = COLORS.gold
	corner(accountFill, 4)
	accountFill.Parent = xpBar

	playButton = Instance.new("TextButton")
	playButton.Name = "Play"
	playButton.LayoutOrder = 5
	playButton.Size = UDim2.fromOffset(240, 64)
	playButton.BackgroundColor3 = COLORS.gold
	playButton.Font = Enum.Font.FredokaOne
	playButton.TextSize = 32
	playButton.TextColor3 = COLORS.ink
	playButton.Text = "PLAY"
	corner(playButton, 14)
	playButton.Parent = home

	-- TALENTS: the 30-node talent path (#163).
	local talents = page("Talents", 620, 520)
	pages.TALENTS = talents
	TalentsController.build(talents, newBadges.TALENTS)

	-- SHOP: the Basic Chest (#164).
	local shop = page("Shop", 560, 380)
	pages.SHOP = shop
	ShopController.build(shop)

	-- CHAPTERS: one full-width card per chapter.
	local chaptersPage = page("Chapters", 640, 330) -- 4 cards, no empty space below
	pages.CHAPTERS = chaptersPage
	chapterList = Instance.new("ScrollingFrame")
	chapterList.Name = "List"
	chapterList.Position = UDim2.fromOffset(12, 12)
	chapterList.Size = UDim2.new(1, -24, 1, -24)
	chapterList.BackgroundTransparency = 1
	chapterList.BorderSizePixel = 0
	chapterList.ScrollBarThickness = 6
	chapterList.CanvasSize = UDim2.new()
	chapterList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	chapterList.Parent = chaptersPage
	local chapterLayout = Instance.new("UIListLayout")
	chapterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chapterLayout.Padding = UDim.new(0, 8)
	chapterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	chapterLayout.Parent = chapterList
	local chapterPadding = Instance.new("UIPadding")
	chapterPadding.PaddingTop = UDim.new(0, 4)
	chapterPadding.PaddingBottom = UDim.new(0, 4)
	chapterPadding.Parent = chapterList

	-- COOKBOOK: one card per reachable recipe, found or not.
	local cookbook = page("Cookbook", 860, 520)
	pages.COOKBOOK = cookbook
	cookbookList = Instance.new("ScrollingFrame")
	cookbookList.Name = "List"
	cookbookList.Position = UDim2.fromOffset(12, 12)
	cookbookList.Size = UDim2.new(1, -24, 1, -56)
	cookbookList.BackgroundTransparency = 1
	cookbookList.BorderSizePixel = 0
	cookbookList.ScrollBarThickness = 6
	cookbookList.CanvasSize = UDim2.new()
	cookbookList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	cookbookList.Parent = cookbook
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(200, 94)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = cookbookList
	cookbookCount = label(cookbook, "Count", "", 18)
	cookbookCount.AnchorPoint = Vector2.new(0, 1)
	cookbookCount.Position = UDim2.new(0, 0, 1, -10)
	cookbookCount.Size = UDim2.new(1, 0, 0, 28)
	cookbookCount.TextColor3 = COLORS.gold
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
		requestRestart:FireServer(chapterToPlay())
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
		elseif name == "Chapter" then
			selectedChapter = nil -- the server's chapter changed: follow it
			if gui.Enabled then
				drawHome()
			end
		elseif string.match(name, "^Cleared_") and gui.Enabled and currentTab == "CHAPTERS" then
			drawChapters()
		elseif
			name == "LifetimeRuns"
			or name == "LifetimeWins"
			or name == "BestWinSeconds"
			or name == "AccountLevel"
			or name == "AccountXp"
			or name == "AccountXpNeeded"
		then
			if gui.Enabled then
				drawHome()
			end
		elseif string.match(name, "^Found_") and gui.Enabled and currentTab == "COOKBOOK" then
			drawCookbook()
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
