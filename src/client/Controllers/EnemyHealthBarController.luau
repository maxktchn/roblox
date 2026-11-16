--!strict
-- Enemy health bars (#81). A small bar floats over an enemy once it has been damaged; enemies
-- at full HP have none, so a swarm of 150 doesn't draw 150 bars. Bosses keep their own bar
-- (BossService).
--
-- The server says how hurt an enemy is with the attribute "HpFraction" on its part
-- (EnemyService, rounded to 5% steps). No attribute = full HP or dead = no bar.
--
-- Bars come from a fixed pool of MAX_BARS BillboardGuis (PRD §8.3): each one is pinned to an
-- enemy part with Adornee, so it follows the enemy with no per-frame work here. If every bar
-- is in use, more hurt enemies just go without one until a bar is free.

local EnemyHealthBarController = {}

local MAX_BARS = 60
local BAR_HEIGHT_PIXELS = 6
local MIN_WIDTH_STUDS = 1.6 -- small enemies still get a readable bar
local GAP_STUDS = 0.7 -- space between the top of the enemy and its bar
local FILL_COLOR = Color3.fromRGB(230, 60, 50)
local BACK_COLOR = Color3.fromRGB(35, 25, 25)

type Bar = { billboard: BillboardGui, fill: Frame }

local container: Folder
local freeBars: { Bar } = {}
local barOf: { [BasePart]: Bar } = {} -- enemy part -> the bar it's using

local function makeBar(): Bar
	local billboard = Instance.new("BillboardGui")
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Enabled = false

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = BACK_COLOR
	back.BorderSizePixel = 0
	back.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = FILL_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = back

	billboard.Parent = container
	return { billboard = billboard, fill = fill }
end

local function release(part: BasePart)
	local bar = barOf[part]
	if bar then
		barOf[part] = nil
		bar.billboard.Enabled = false
		bar.billboard.Adornee = nil :: any
		table.insert(freeBars, bar)
	end
end

-- Show, update or hide the bar for one enemy part from its "HpFraction" attribute.
local function refresh(part: BasePart)
	local fraction = part:GetAttribute("HpFraction")
	if type(fraction) ~= "number" then
		release(part) -- full HP, dead, or parked in the pool
		return
	end
	local bar = barOf[part] or table.remove(freeBars)
	if not bar then
		return -- every bar is in use
	end
	if not barOf[part] then
		-- A new bar for this enemy.
		barOf[part] = bar
		-- Sized to the enemy: as wide as it is (in studs), a few pixels tall.
		bar.billboard.Size = UDim2.new(math.max(part.Size.X, MIN_WIDTH_STUDS), 0, 0, BAR_HEIGHT_PIXELS)
		bar.billboard.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + GAP_STUDS, 0)
		bar.billboard.Adornee = part
		bar.billboard.Enabled = true
	end
	bar.fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
end

-- Enemy parts are pooled (EnemyService): each part is created once and reused, so one
-- listener per part is enough.
local function watch(part: Instance)
	if part:IsA("BasePart") then
		part:GetAttributeChangedSignal("HpFraction"):Connect(function()
			refresh(part)
		end)
		part.Destroying:Connect(function()
			release(part)
		end)
		refresh(part)
	end
end

function EnemyHealthBarController:start()
	-- The bars live in a folder only this client has.
	container = Instance.new("Folder")
	container.Name = "EnemyHealthBars"
	container.Parent = workspace
	for _ = 1, MAX_BARS do
		table.insert(freeBars, makeBar())
	end

	task.spawn(function()
		local enemies = workspace:WaitForChild("Enemies")
		for _, part in enemies:GetChildren() do
			watch(part)
		end
		enemies.ChildAdded:Connect(watch)
	end)
end

return EnemyHealthBarController
