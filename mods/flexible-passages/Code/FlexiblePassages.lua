-- Flexible Passages -- main entry file.

local function FP_Init(reason)
	local mod = rawget(_G, "FlexiblePassages")
	if type(mod) ~= "table" or mod.Lifecycle == nil then
		return false
	end

	return mod.Lifecycle.Enable(reason)
end

-- Mod code loads before the engine rebuilds its classes. Patching here would
-- capture the old controller and leave stale ownership state after ClassesBuilt.

function OnMsg.ClassesBuilt()
	FP_Init("ClassesBuilt")
end

function OnMsg.CityStart()
	FP_Init("CityStart")
end

function OnMsg.LoadGame()
	FP_Init("LoadGame")
end

function OnMsg.DoneGame()
	local mod = rawget(_G, "FlexiblePassages")
	if type(mod) == "table" and mod.Lifecycle ~= nil then
		mod.Lifecycle.Disable("DoneGame")
	end
end

function OnMsg.ModUnloadLua(mod_id)
	if mod_id ~= "FlexiblePassages" then return end
	local mod = rawget(_G, "FlexiblePassages")
	if type(mod) == "table" and mod.Lifecycle ~= nil then
		mod.Lifecycle.Disable("ModUnloadLua")
	end
end
