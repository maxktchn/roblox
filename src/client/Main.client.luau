--!strict
-- THE client entry point. Every other client file is a ModuleScript in Controllers/.
-- Boot order: require all controllers -> init() each (no yielding) -> start() each.

type Controller = {
	init: ((self: Controller) -> ())?,
	start: ((self: Controller) -> ())?,
}

local controllers: { [string]: Controller } = {}
local names: { string } = {}
for _, module in script.Parent.Controllers:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			controllers[module.Name] = result
			table.insert(names, module.Name)
		else
			warn(`[Boot] require {module.Name} failed: {result}`)
		end
	end
end
table.sort(names)

for _, phase in { "init", "start" } do
	for _, name in names do
		local controller = controllers[name] :: any
		local fn = controller[phase]
		if fn then
			local ok, err = pcall(fn, controller)
			if not ok then
				warn(`[Boot] {name}:{phase} failed: {err}`)
			end
		end
	end
end
