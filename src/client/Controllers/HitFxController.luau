--!strict
-- Hit feedback (#43): the hit enemy flashes white and a damage number floats up. Visual only:
-- the server already decided the damage (WeaponService) and sends recent hits in batches
-- with the HitFx remote: { { part, position, amount, kind } }, kind = "Hit", "Crit" or "Burn".
--
-- Numbers: a fixed pool of BillboardGuis on attachments, reused oldest-first, so a huge
-- swarm never creates more than MAX_NUMBERS of them (PRD §8.3).
-- Flash: the enemy part turns white on this client only for FLASH_SECONDS, then gets its
-- own colour back. Burn ticks don't flash (a burning enemy would just stay white).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local HitFxController = {}

local MAX_NUMBERS = 40 -- damage numbers on screen at once
local NUMBER_SECONDS = 0.6 -- how long a number stays up
local NUMBER_RISE = 3 -- studs a number floats up over its lifetime
local FLASH_SECONDS = 0.08
local FLASH_COLOR = Color3.new(1, 1, 1)

-- How each kind of hit looks: text colour and size in pixels.
local STYLES = {
	Hit = { color = Color3.fromRGB(255, 255, 255), size = 22 },
	Crit = { color = Color3.fromRGB(255, 205, 40), size = 34 },
	Burn = { color = Color3.fromRGB(255, 130, 40), size = 17 },
}

type HitFx = { part: BasePart, position: Vector3, amount: number, kind: string }

type DamageNumber = {
	attachment: Attachment,
	billboard: BillboardGui,
	label: TextLabel,
	start: Vector3,
	age: number,
	active: boolean,
}

local numbers: { DamageNumber } = {}
local nextNumber = 1 -- the next pool slot to use (wraps around, so the oldest is reused)

-- Parts flashing right now: part -> its real colour and when to put it back.
local flashing: { [BasePart]: { color: Color3, untilTime: number } } = {}

-- One anchor part at the world origin; each number is an attachment on it, so moving a
-- number is just setting its attachment's position (no parts to move).
local function buildPool()
	local anchor = Instance.new("Part")
	anchor.Name = "HitNumbers"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new()

	for i = 1, MAX_NUMBERS do
		local attachment = Instance.new("Attachment")
		attachment.Parent = anchor

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(90, 40)
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.Enabled = false
		billboard.Parent = attachment

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextStrokeTransparency = 0.2 -- dark outline so numbers read on any floor
		label.Parent = billboard

		numbers[i] = {
			attachment = attachment,
			billboard = billboard,
			label = label,
			start = Vector3.zero,
			age = 0,
			active = false,
		}
	end
	anchor.Parent = workspace
end

local function showNumber(hit: HitFx)
	local style = STYLES[hit.kind] or STYLES.Hit
	local number = numbers[nextNumber]
	nextNumber = nextNumber % MAX_NUMBERS + 1

	-- Start just above the enemy, nudged sideways so numbers from one swing don't stack.
	local height = if hit.part then hit.part.Size.Y / 2 + 1 else 2
	number.start = hit.position + Vector3.new((math.random() - 0.5) * 1.5, height, (math.random() - 0.5) * 1.5)
	number.age = 0
	number.active = true
	number.attachment.Position = number.start
	number.label.Text = tostring(math.max(1, math.round(hit.amount))) .. (if hit.kind == "Crit" then "!" else "")
	number.label.TextColor3 = style.color
	number.label.TextSize = style.size
	number.label.TextTransparency = 0
	number.label.TextStrokeTransparency = 0.2
	number.billboard.Enabled = true
end

local function flash(part: BasePart)
	local now = os.clock()
	local entry = flashing[part]
	if entry then
		entry.untilTime = now + FLASH_SECONDS -- already white: just keep it white a bit longer
	else
		flashing[part] = { color = part.Color, untilTime = now + FLASH_SECONDS }
		part.Color = FLASH_COLOR
	end
end

local function onHits(hits: { HitFx })
	for _, hit in hits do
		showNumber(hit)
		if hit.kind ~= "Burn" and hit.part then
			flash(hit.part)
		end
	end
end

-- Every frame: float and fade the numbers, and end finished flashes.
local function update(deltaTime: number)
	for _, number in numbers do
		if number.active then
			number.age += deltaTime
			local t = number.age / NUMBER_SECONDS
			if t >= 1 then
				number.active = false
				number.billboard.Enabled = false
			else
				number.attachment.Position = number.start + Vector3.new(0, NUMBER_RISE * t, 0)
				-- Fully visible for the first half, then fade out.
				local fade = math.clamp((t - 0.5) * 2, 0, 1)
				number.label.TextTransparency = fade
				number.label.TextStrokeTransparency = 0.2 + 0.8 * fade
			end
		end
	end

	local now = os.clock()
	for part, entry in flashing do
		if now >= entry.untilTime then
			part.Color = entry.color
			flashing[part] = nil
		end
	end
end

function HitFxController:init()
	buildPool()
end

function HitFxController:start()
	Remotes.get("HitFx").OnClientEvent:Connect(onHits)
	RunService.RenderStepped:Connect(update)
end

return HitFxController
