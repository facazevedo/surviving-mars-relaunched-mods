-- Flexible Passages -- main entry file.

local function FP_Init(reason)
	local mod = rawget(_G, "FlexiblePassages")
	if type(mod) ~= "table" or mod.Lifecycle == nil then
		return false
	end

	return mod.Lifecycle.Enable(reason)
end

FP_Init("code_load")

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
