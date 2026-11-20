--!strict
-- Every RemoteEvent the game uses, in one list. The server creates them at boot
-- (ReplicatedStorage.Remotes); the client waits for them. Never create remotes anywhere else.
-- The client only ever sends movement (handled by Roblox), card choices and its aim
-- direction (PRD §8.4); the server validates all of it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"OfferCards", -- server -> client: (cards: { Card }, rerollsLeft: number) for an "Order Up!"
	"ChooseCard", -- client -> server: index of the chosen card (server validates it was offered)
	"RequestReroll", -- client -> server: reroll the current offer
	"CloseCards", -- server -> client: the offer ended without a pick (e.g. the run was reset), hide the cards
	"WeaponFx", -- server -> client: a weapon just attacked, draw its effect (visual only)
	"RequestRestart", -- client -> server: Play in the lobby (only while in the lobby, P2-8)
	"RequestLobby", -- client -> server: Continue on the run-over banner (only once a run has ended)
	"DevAction", -- client -> server: (action, arg) from the DEV panel; devs only, validated (DevCommandService)
	"RunReport", -- server -> client: (text) end-of-run report for tuning; devs only (RunReportService)
	"DevMessage", -- server -> client: (text) reply shown on the DEV panel; devs only
	"HitFx", -- server -> client: { HitFx } recent hits, for enemy flashes and damage numbers (visual only)
	"GearAction", -- client -> server: (action, arg) from the Gear screen; validated (GearService, P2-4)
	"GearState", -- server -> client: (state, message?) the player's gear and currencies for the Gear screen
}

-- Unreliable remotes: for frequent, throwaway updates where only the latest one matters
-- (a lost or late message is simply replaced by the next). Get them with getUnreliable.
local UNRELIABLE_NAMES = {
	"AimDirection", -- client -> server: (x, z) flat aim direction for the starter weapon (PRD §2.2)
}

local Remotes = {}

local FOLDER_NAME = "Remotes"

-- Server only: create the folder and every RemoteEvent. Call once at boot.
function Remotes.create()
	assert(RunService:IsServer(), "Remotes.create is server-only")
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in UNRELIABLE_NAMES do
		local remote = Instance.new("UnreliableRemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

-- Both sides: get a remote by name. Yields on the client until the server has created it.
function Remotes.get(name: string): RemoteEvent
	assert(table.find(NAMES, name), `Unknown remote "{name}"`)
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name) :: RemoteEvent
end

-- Both sides: get an unreliable remote by name (see UNRELIABLE_NAMES).
function Remotes.getUnreliable(name: string): UnreliableRemoteEvent
	assert(table.find(UNRELIABLE_NAMES, name), `Unknown unreliable remote "{name}"`)
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name) :: UnreliableRemoteEvent
end

return Remotes
