--!strict
-- The Cookbook: which recipes the player has made (P2-8 #145, design:
-- docs/superpowers/specs/2026-11-17-lobby-design.md).
--
-- A recipe is found the first time its card is taken in a run (UpgradeService.onRecipeTaken;
-- the playtest bot's runs count, a DEV "Give" doesn't since it skips the card). Following the
-- saving rule (#102), it's only written to the save's Cookbook section when the run ends (Won or
-- Lost, DataService.onRunEnded). Quitting mid-run records nothing.
--
-- Player attributes: "Found_<recipeId>" = true for every found recipe (the lobby's Cookbook tab).

local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)
local UpgradeService = require(script.Parent.UpgradeService)

local CookbookService = {}

-- Recipes taken in the current run, not saved yet.
local foundThisRun: { [string]: boolean } = {}

-- Copy the saved Cookbook onto the player as attributes.
local function syncAttributes(player: Player, data: DataService.Data)
	for recipeId in data.Cookbook do
		player:SetAttribute(`Found_{recipeId}`, true)
	end
end

function CookbookService:start()
	UpgradeService.onRecipeTaken(function(recipeId: string)
		foundThisRun[recipeId] = true
	end)
	DataService.onRunEnded(function(player: Player, data: DataService.Data)
		for recipeId in foundThisRun do
			data.Cookbook[recipeId] = true
		end
		table.clear(foundThisRun)
		syncAttributes(player, data)
	end)
	DataService.onLoaded(function(player: Player, data: DataService.Data)
		-- A save (re)loading means a new session: anything from an unfinished run is gone.
		table.clear(foundThisRun)
		syncAttributes(player, data)
	end)
	local function watch(player: Player)
		-- A new run starts with nothing found yet.
		player:GetAttributeChangedSignal("RunState"):Connect(function()
			if player:GetAttribute("RunState") == "Playing" then
				table.clear(foundThisRun)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function()
		table.clear(foundThisRun)
	end)
end

return CookbookService
