--!strict
-- The lobby (P2-8 #143-#145, PRD §7.1, design: docs/superpowers/specs/2026-11-17-lobby-design.md).
--
-- The server's run state ("RunState" player attribute) is "Lobby" between runs: on joining and
-- after Continue on the run-over banner. While it is, this controller shows the lobby and keeps
-- the chef standing still in the kitchen (their root part is anchored here on the client, the way
-- the "Order Up!" card screen freezes them).

local Players = game:GetService("Players")

local LobbyController = {}

local player = Players.LocalPlayer

local function inLobby(): boolean
	return player:GetAttribute("RunState") == "Lobby"
end

-- Anchor the chef in the lobby, free them in a run.
local function syncChef()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = inLobby()
	end
end

function LobbyController:init() end

function LobbyController:start()
	player:GetAttributeChangedSignal("RunState"):Connect(syncChef)
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		syncChef()
	end)
	syncChef()
end

return LobbyController
