--!strict
-- In-run HUD: HP bar, tip bar + level, timer, kill count, owned items, pause (PRD §7.2).
--
-- The HUD only reads attributes the server puts on the player, and redraws when they change:
--   "Level", "Tips", "TipsNeeded"   UpgradeService (tip bar)
--   "Kills"                         WeaponService
--   "Weapon_<id>", "Ingredient_<id>" WeaponService / StatsService (owned item icons)
--   "RunSeconds"                    RunManager, run timer in whole seconds (#6)
--   "MiniBoss"                      MiniBossService, the mini-boss's name during its fight (#84)
--   "Hp", "MaxHp"                   RunManager, the chef's HP (#9)
--   "RunState"                      RunManager: "Playing", "Lost" or "Won" (shows the run-over banner)
--   "JustUnlocked"                  UnlockService: a boss power this run unlocked (line on the banner)
--   "SaveStatus"                    DataService: "Off" shows the not-saving banner (P2-1, #114)
--   "ApronReady"                    GearEffectsService: the Apron's block is ready (true), used up
--                                   (false) or not equipped (nil) (P2-4, #139)
--   "Rush", "RushStage", "RushSound" RunManager: the dinner rush banner (#121), big while
--                                   "Warning", smaller while "On"; the sound plays with the warning
-- Until the lobby exists (#109), the "Test build" note (Config.Saving.TestBuild) sits here too.
-- If Hp/MaxHp are missing the HP bar shows the Humanoid's health instead, and the
-- timer shows "--:--" until RunSeconds exists.
-- Pause button: not in Phase 1 yet (the run already pauses during "Order Up!").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossPowers = require(ReplicatedStorage.Config.BossPowers)
local Gadgets = require(ReplicatedStorage.Config.Gadgets)
local Ingredients = require(ReplicatedStorage.Config.Ingredients)
local Recipes = require(ReplicatedStorage.Config.Recipes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Saving = require(ReplicatedStorage.Config.Saving)
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
	cheese = Color3.fromRGB(255, 200, 60), -- the mini-boss line (#84)
	saveOff = Color3.fromRGB(150, 30, 30), -- the not-saving banner (#114)
	rush = Color3.fromRGB(255, 140, 40), -- the dinner rush banner (#121)
	note = Color3.fromRGB(190, 190, 190), -- the small test-build note
}

-- Icon colours by item type (same idea as the Order Up! cards).
local ICON_COLORS = {
	Starter = Color3.fromRGB(214, 84, 40),
	Gadget = Color3.fromRGB(52, 120, 200),
	Recipe = Color3.fromRGB(230, 175, 30),
	Ingredient = Color3.fromRGB(46, 160, 67),
	BossPower = Color3.fromRGB(255, 140, 40),
}

local ICON_SIZE = 38 -- pixels
local ICON_COLUMNS = 4
local EDGE = 16 -- pixels between the HUD and the screen edge
-- Width kept free on each side of the top bar for the owned icons (left) and the kill count
-- (right), so on a small phone (about 640 wide) the bar shrinks instead of covering them.
local SIDE_SPACE = EDGE + (ICON_SIZE + 6) * ICON_COLUMNS + 8
local TOP_BAR_MAX_WIDTH = 520 -- on big screens the bar stops growing here

local gui: ScreenGui
-- The save notes ("Test build", "Progress isn't saving") live on their own layer, shown in every
-- state: the HUD itself hides in the lobby, where players now spend their between-run time.
local notesGui: ScreenGui
local levelLabel: TextLabel
local tipFill: Frame
local tipText: TextLabel
local timerLabel: TextLabel
local miniBossLabel: TextLabel -- "Defeat The Big Cheese!" while the mini-boss fight is on
local killsLabel: TextLabel
local rushLabel: TextLabel -- "DINNER RUSH!" (#121)
local rushSound: Sound
local lastRushStage: unknown = nil
local saveBanner: Frame -- "Progress isn't saving right now" while SaveStatus is "Off" (#114)
local shieldPill: TextLabel -- the Apron's block: bright when ready, faded while it recharges
local iconRow: Frame
local hpBillboard: BillboardGui
local hpFill: Frame
local runOverPanel: Frame
local runOverTitle: TextLabel
local runOverStats: TextLabel
local runOverUnlock: TextLabel
local continueButton: TextButton
local orderUpOpen = false -- the "Order Up!" cards are on screen

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
	-- Clear of phone notches and of Roblox's own top-bar buttons (menu, chat) (PRD §7.4).
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	-- Top centre: level badge + tip bar.
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundTransparency = 1
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 12)
	top.Size = UDim2.new(1, -2 * SIDE_SPACE, 0, 34)
	top.Parent = gui
	local topLimit = Instance.new("UISizeConstraint")
	topLimit.MaxSize = Vector2.new(TOP_BAR_MAX_WIDTH, 34)
	topLimit.Parent = top

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

	-- Under the timer, only during the mini-boss fight (the clock holds at 3:00 until it's beaten).
	miniBossLabel = makeLabel(gui, "MiniBoss", 22)
	miniBossLabel.AnchorPoint = Vector2.new(0.5, 0)
	miniBossLabel.Position = UDim2.new(0.5, 0, 0, 86)
	miniBossLabel.Size = UDim2.fromOffset(320, 28)
	miniBossLabel.TextColor3 = COLORS.cheese
	miniBossLabel.Visible = false

	-- Same place, during the dinner rush (#121; never at the same time as the mini-boss).
	rushLabel = makeLabel(gui, "Rush", 44)
	rushLabel.AnchorPoint = Vector2.new(0.5, 0)
	rushLabel.Position = UDim2.new(0.5, 0, 0, 86)
	rushLabel.Size = UDim2.fromOffset(360, 48)
	rushLabel.TextColor3 = COLORS.rush
	rushLabel.Visible = false
	rushSound = Instance.new("Sound")
	rushSound.Name = "RushSound"
	rushSound.Parent = gui

	-- Under the mini-boss line: shown only while the save couldn't load (DataService, #114).
	saveBanner = Instance.new("Frame")
	saveBanner.Name = "SaveBanner"
	saveBanner.AnchorPoint = Vector2.new(0.5, 0)
	saveBanner.Position = UDim2.new(0.5, 0, 0, 118)
	saveBanner.Size = UDim2.fromOffset(300, 28)
	saveBanner.BackgroundColor3 = COLORS.saveOff
	saveBanner.BorderSizePixel = 0
	saveBanner.Visible = false
	notesGui = Instance.new("ScreenGui")
	notesGui.Name = "SaveNotes"
	notesGui.ResetOnSpawn = false
	notesGui.DisplayOrder = 16 -- over the lobby (14) and the Gear screen (15)
	notesGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	saveBanner.Parent = notesGui
	corner(saveBanner, UDim.new(0, 8))
	local saveText = makeLabel(saveBanner, "Text", 18)
	saveText.Size = UDim2.fromScale(1, 1)
	saveText.TextColor3 = Color3.new(1, 1, 1)
	saveText.Text = "Progress isn't saving right now"

	-- Top right, under the kill count (the item icons grow down the left): an Epic or Legendary
	-- Apron's block (#139).
	shieldPill = makeLabel(gui, "Shield", 16)
	shieldPill.AnchorPoint = Vector2.new(1, 0)
	shieldPill.Position = UDim2.new(1, -EDGE, 0, 118)
	shieldPill.Size = UDim2.fromOffset(110, 26)
	shieldPill.BackgroundColor3 = COLORS.hpHigh
	shieldPill.BackgroundTransparency = 0
	shieldPill.TextColor3 = Color3.new(1, 1, 1)
	shieldPill.Text = "SHIELD"
	shieldPill.Visible = false
	corner(shieldPill, UDim.new(0, 8))

	-- Bottom-right corner, small: saves may be wiped until launch (Config.Saving.TestBuild).
	local testNote = makeLabel(notesGui, "TestBuildNote", 14)
	testNote.AnchorPoint = Vector2.new(1, 1)
	testNote.Position = UDim2.new(1, -8, 1, -8)
	testNote.Size = UDim2.fromOffset(260, 18)
	testNote.TextXAlignment = Enum.TextXAlignment.Right
	testNote.TextColor3 = COLORS.note
	testNote.Text = "Test build: progress may be reset"
	testNote.Visible = Saving.TestBuild

	killsLabel = makeLabel(gui, "Kills", 22)
	killsLabel.AnchorPoint = Vector2.new(1, 0)
	killsLabel.Position = UDim2.new(1, -EDGE, 0, 14)
	killsLabel.Size = UDim2.fromOffset(SIDE_SPACE - EDGE - 8, 30)
	killsLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- Top left: one small icon per owned weapon and ingredient.
	iconRow = Instance.new("Frame")
	iconRow.Name = "Owned"
	iconRow.BackgroundTransparency = 1
	iconRow.Position = UDim2.fromOffset(EDGE, 14)
	iconRow.Size = UDim2.fromOffset((ICON_SIZE + 6) * ICON_COLUMNS, (ICON_SIZE + 6) * 2)
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
	runOverPanel.Size = UDim2.fromOffset(420, 250)
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
	-- Shown only when this run unlocked a boss power (PRD §3.8).
	runOverUnlock = makeLabel(runOverPanel, "Unlock", 20)
	runOverUnlock.Size = UDim2.new(1, 0, 0, 28)
	runOverUnlock.Position = UDim2.fromOffset(0, 128)
	runOverUnlock.TextColor3 = COLORS.tips
	runOverUnlock.Visible = false

	-- "Continue" (P2-8 #143): back to the lobby (RestartService). Play is in the lobby now.
	continueButton = Instance.new("TextButton")
	continueButton.Name = "Continue"
	continueButton.AnchorPoint = Vector2.new(0.5, 0)
	continueButton.Position = UDim2.new(0.5, 0, 0, 172)
	continueButton.Size = UDim2.fromOffset(220, 56) -- big enough for a thumb (PRD §7.4)
	continueButton.BackgroundColor3 = COLORS.tips
	continueButton.Font = Enum.Font.FredokaOne
	continueButton.TextSize = 26
	continueButton.TextColor3 = COLORS.ink
	continueButton.Text = "Continue"
	corner(continueButton, UDim.new(0, 12))
	continueButton.Parent = runOverPanel
end

-- The run-over banner, with how far the player got.
local function updateRunState()
	local state = player:GetAttribute("RunState")
	local over = state == "Lost" or state == "Won"
	runOverPanel.Visible = over
	-- The HUD and the chef's HP bar are for runs: hidden in the lobby (P2-8 #143) and while the
	-- "Order Up!" cards are open (nothing on it changes during a pick).
	gui.Enabled = state ~= "Lobby" and not orderUpOpen
	hpBillboard.Enabled = state ~= "Lobby"
	-- Ready for the next tap whenever the banner (re)appears.
	continueButton.Text = "Continue"
	continueButton.Active = true
	if over then
		if state == "Won" then
			runOverTitle.Text = "SHIFT SURVIVED!"
			runOverTitle.TextColor3 = COLORS.tips
		else
			runOverTitle.Text = "SHIFT OVER"
			runOverTitle.TextColor3 = COLORS.hpLow
		end
		local unlockedName = player:GetAttribute("JustUnlocked")
		runOverUnlock.Visible = type(unlockedName) == "string"
		runOverUnlock.Text = `New power unlocked: {unlockedName}`
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

	-- "MiniBoss" is the mini-boss's name while its fight is on (MiniBossService).
	local miniBoss = player:GetAttribute("MiniBoss")
	miniBossLabel.Visible = type(miniBoss) == "string"
	miniBossLabel.Text = if type(miniBoss) == "string" then `Defeat {miniBoss}!` else ""

	saveBanner.Visible = player:GetAttribute("SaveStatus") == "Off"
	local apronReady = player:GetAttribute("ApronReady")
	shieldPill.Visible = apronReady ~= nil
	shieldPill.BackgroundTransparency = if apronReady then 0 else 0.7
	shieldPill.TextTransparency = if apronReady then 0 else 0.5

	-- The dinner rush (#121): big while it's warning, smaller while it's on.
	local rush = player:GetAttribute("Rush")
	local stage = player:GetAttribute("RushStage")
	rushLabel.Visible = type(rush) == "string"
	rushLabel.Text = if type(rush) == "string" then rush else ""
	rushLabel.TextSize = if stage == "Warning" then 44 else 26
	if stage == "Warning" and lastRushStage ~= "Warning" then
		local soundId = player:GetAttribute("RushSound")
		if type(soundId) == "string" and soundId ~= "" then
			rushSound.SoundId = soundId
			rushSound:Play()
		end
	end
	lastRushStage = stage
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
	elseif BossPowers[id] then
		return "BossPower", BossPowers[id].Name, 2
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
	local requestLobby = Remotes.get("RequestLobby")
	continueButton.Activated:Connect(function()
		if not continueButton.Active then
			return -- already asked: wait for the lobby
		end
		continueButton.Active = false
		continueButton.Text = "..."
		requestLobby:FireServer()
	end)

	local playerGui = player:WaitForChild("PlayerGui")
	gui.Parent = playerGui
	notesGui.Parent = playerGui
	hpBillboard.Parent = playerGui

	updateNumbers()
	updateIcons()
	updateRunState()
	player.AttributeChanged:Connect(function(name: string)
		if string.match(name, "^Weapon_") or string.match(name, "^Ingredient_") then
			updateIcons()
		elseif name == "Hp" or name == "MaxHp" then
			updateHp()
		elseif name == "RunState" or name == "JustUnlocked" then
			updateRunState()
		else
			updateNumbers()
		end
	end)

	if player.Character then
		task.spawn(attachHpBar, player.Character)
	end
	player.CharacterAdded:Connect(attachHpBar)

	-- Hide the HUD while the "Order Up!" cards are open (UpgradeUIController's "OrderUp" screen):
	-- nothing on it changes during a pick, and its top bar would show through behind the title.
	task.spawn(function()
		local orderUp = playerGui:WaitForChild("OrderUp") :: ScreenGui
		local function sync()
			orderUpOpen = orderUp.Enabled
			updateRunState()
		end
		sync()
		orderUp:GetPropertyChangedSignal("Enabled"):Connect(sync)
	end)
end

return HUDController
