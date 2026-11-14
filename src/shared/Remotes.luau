--!strict
-- Every RemoteEvent the game uses, in one list. The server creates them at boot
-- (ReplicatedStorage.Remotes); the client waits for them. Never create remotes anywhere else.
-- The client only ever sends movement (handled by Roblox) and card choices (PRD §8.4).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"OfferCards", -- server -> client: (cards: { Card }, rerollsLeft: number) for an "Order Up!"
	"ChooseCard", -- client -> server: index of the chosen card (server validates it was offered)
	"RequestReroll", -- client -> server: reroll the current offer
	"CloseCards", -- server -> client: the offer ended without a pick (e.g. the run was reset), hide the cards
	"WeaponFx", -- server -> client: a weapon just attacked, draw its effect (visual only)
	"RequestRestart", -- client -> server: "Play again" on the run-over banner (only while the run is over)
	"DevAction", -- client -> server: (action, arg) from the DEV panel; devs only, validated (DevCommandService)
	"DevMessage", -- server -> client: (text) reply shown on the DEV panel; devs only
	"HitFx", -- server -> client: { HitFx } recent hits, for enemy flashes and damage numbers (visual only)
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
	folder.Parent = ReplicatedStorage
end

-- Both sides: get a remote by name. Yields on the client until the server has created it.
function Remotes.get(name: string): RemoteEvent
	assert(table.find(NAMES, name), `Unknown remote "{name}"`)
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
