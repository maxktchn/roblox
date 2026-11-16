--!strict
-- The name and HP bar floating over a boss (the Microwave Monster, The Big Cheese #84).
-- Not a service: BossService and MiniBossService call attach() when their boss spawns.
--
-- attach() returns the bar's fill. Each frame, the caller sets
--   fill.Size = UDim2.fromScale(hp / maxHp, 1)
-- When the boss dies or the run restarts, the caller passes that fill to remove(): a dead
-- boss's part is parked under the map, and an always-on-top bar would show through the floor.

local BossHpBar = {}

local BACK_COLOR = Color3.fromRGB(30, 30, 36)
local FILL_COLOR = Color3.fromRGB(220, 60, 50)

-- Put a name + HP bar over `part`. Boss parts are pooled, so an old bar is removed first.
-- Sized in studs, so it scales with the camera like the boss.
function BossHpBar.attach(part: BasePart, title: string): Frame
	local old = part:FindFirstChild("BossHp")
	if old then
		old:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BossHp"
	billboard.Size = UDim2.fromScale(12, 2.2)
	billboard.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.Size = UDim2.fromScale(1, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = title
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard

	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.Position = UDim2.fromScale(0, 0.58)
	back.Size = UDim2.fromScale(1, 0.38)
	back.BackgroundColor3 = BACK_COLOR
	back.BorderSizePixel = 0
	back.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = FILL_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = back
	return fill
end

-- Take down the bar that `fill` (from attach) belongs to. Does nothing for nil.
function BossHpBar.remove(fill: Frame?)
	local billboard = fill and fill:FindFirstAncestorOfClass("BillboardGui")
	if billboard then
		billboard:Destroy()
	end
end

return BossHpBar
