--!strict
-- THE server entry point. Every other server file is a ModuleScript in Services/.
-- Boot order: require all services -> init() each (no yielding) -> start() each.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigCheck = require(ReplicatedStorage.Shared.ConfigCheck)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

type Service = {
	init: ((self: Service) -> ())?,
	start: ((self: Service) -> ())?,
}

-- Services that must init first, in this order. The rest follow alphabetically.
local ORDER = { "DataService", "RunManager" }

for _, problem in ConfigCheck.run() do
	warn(`[Config] {problem}`)
end

Remotes.create()

local services: { [string]: Service } = {}
local names: { string } = {}
for _, module in script.Parent.Services:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			services[module.Name] = result
			table.insert(names, module.Name)
		else
			warn(`[Boot] require {module.Name} failed: {result}`)
		end
	end
end

local rank: { [string]: number } = {}
for i, name in ORDER do
	rank[name] = i
end
table.sort(names, function(a, b)
	local ra, rb = rank[a] or math.huge, rank[b] or math.huge
	if ra ~= rb then
		return ra < rb
	end
	return a < b
end)

for _, phase in { "init", "start" } do
	for _, name in names do
		local service = services[name] :: any
		local fn = service[phase]
		if fn then
			local ok, err = pcall(fn, service)
			if not ok then
				warn(`[Boot] {name}:{phase} failed: {err}`)
			end
		end
	end
end
