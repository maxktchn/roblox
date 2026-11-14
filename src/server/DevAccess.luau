--!strict
-- Who may use developer chat commands (/stress, /levelup, /boss ...).
-- One rule for every dev tool: anyone in Studio, the experience's owner, and the user ids
-- in Config/DevTools.DevUserIds. Lives outside Services/ because it is a helper, not a service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DevTools = require(ReplicatedStorage.Config.DevTools)

local DevAccess = {}

function DevAccess.isAllowed(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return table.find(DevTools.DevUserIds, player.UserId) ~= nil
end

return DevAccess
