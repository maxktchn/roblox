--!strict
-- FPS readout for the phone stress test (issue #12). Only appears after /stress
-- (the server sets the player attribute "StressTest").
--
-- Shows, live:
--   FPS          frames drawn in the last second on this device
--   worst frame  the slowest frame in the last 5 seconds, in milliseconds
--   enemies / tips on the ground / server FPS / ping
--   screen size and graphics quality (they change FPS a lot, so note them with the result)
-- After DevTools.StressMeasureSeconds it adds a summary line: average FPS over the test, and the
-- "1% low" (the FPS of the slowest 1% of frames), which is what stutter feels like.
-- Screenshot the readout and post it in issue #12 with the phone model.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DevTools = require(ReplicatedStorage.Config.DevTools)

local StressOverlayController = {}

local player = Players.LocalPlayer

local label: TextLabel? = nil
local started = false
local startClock = 0
local summary: string? = nil

-- Frame times for the live numbers and the whole-test summary.
local lastSecond: { number } = {} -- clock times of frames in the last second
local recent: { { clock: number, dt: number } } = {} -- frames in the last 5 seconds
local allFrames: { number } = {} -- every frame time during the measured test

local function makeLabel()
	local gui = Instance.new("ScreenGui")
	gui.Name = "StressOverlay"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")

	local text = Instance.new("TextLabel")
	text.Name = "Readout"
	text.AnchorPoint = Vector2.new(0, 0.5)
	-- Left side, away from the top bar and the screen edge (phones cut corners off).
	text.Position = UDim2.new(0, 24, 0.5, 0)
	text.Size = UDim2.fromOffset(300, 210)
	text.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	text.BackgroundTransparency = 0.25
	text.TextColor3 = Color3.fromRGB(120, 255, 140)
	text.Font = Enum.Font.Code
	text.TextSize = 16
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Text = ""
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 8)
	padding.Parent = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = text
	text.Parent = gui
	label = text
end

-- The FPS of the slowest 1% of frames, and the average FPS, from a list of frame times.
local function summarize(frames: { number }): (number, number)
	local total = 0
	for _, dt in frames do
		total += dt
	end
	local sorted = table.clone(frames)
	table.sort(sorted, function(a, b)
		return a > b
	end)
	local slowCount = math.max(1, math.floor(#sorted / 100))
	local slowTotal = 0
	for i = 1, slowCount do
		slowTotal += sorted[i]
	end
	return #frames / total, slowCount / slowTotal
end

local function onFrame(deltaTime: number)
	if not started then
		return
	end
	local now = os.clock()

	table.insert(lastSecond, now)
	while lastSecond[1] and now - lastSecond[1] > 1 do
		table.remove(lastSecond, 1)
	end
	table.insert(recent, { clock = now, dt = deltaTime })
	while recent[1] and now - recent[1].clock > 5 do
		table.remove(recent, 1)
	end
	local worst = 0
	for _, frame in recent do
		worst = math.max(worst, frame.dt)
	end

	local elapsed = now - startClock
	-- Skip the first 3 seconds: the swarm is still building up to the cap.
	if not summary and elapsed > 3 then
		table.insert(allFrames, deltaTime)
		if elapsed >= DevTools.StressMeasureSeconds + 3 then
			local average, low = summarize(allFrames)
			summary =
				string.format("%ds TEST: avg %.0f fps, 1%% low %.0f fps", DevTools.StressMeasureSeconds, average, low)
		end
	end

	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.zero
	local quality = UserSettings():GetService("UserGameSettings").SavedQualityLevel
	local lines = {
		"STRESS TEST",
		string.format("FPS          %d", #lastSecond),
		string.format("worst frame  %.0f ms (last 5s)", worst * 1000),
		string.format("enemies      %s", tostring(player:GetAttribute("StressAlive") or "?")),
		string.format("tips         %s", tostring(player:GetAttribute("StressTips") or "?")),
		string.format("server FPS   %s", tostring(player:GetAttribute("StressServerFps") or "?")),
		string.format("ping         %.0f ms", player:GetNetworkPing() * 1000),
		string.format("screen       %dx%d  quality %s", viewport.X, viewport.Y, quality.Name),
		summary or string.format(
			"measuring... %ds left",
			math.max(0, math.ceil(DevTools.StressMeasureSeconds + 3 - elapsed))
		),
	}
	if label then
		label.Text = table.concat(lines, "\n")
	end
end

local function checkStarted()
	if not started and player:GetAttribute("StressTest") then
		started = true
		startClock = os.clock()
		makeLabel()
	end
end

function StressOverlayController:init() end

function StressOverlayController:start()
	player:GetAttributeChangedSignal("StressTest"):Connect(checkStarted)
	checkStarted()
	RunService.RenderStepped:Connect(onFrame)
end

return StressOverlayController
