-- Rocket diagnostic attributes and Level 2 deletion.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining rocket helpers on repeated mod loads.
if FD.rocket_loaded then return end
FD.rocket_loaded = true

-- Create the rocket module namespace.
FD.Rocket = FD.Rocket or {}
local Rocket = FD.Rocket

-- Engine classes that represent actual rocket or pod objects.
local rocket_classes = {
	"RocketBase",
	"UniversalRocketBase",
	"SupplyRocketBase",
	"LanderRocketBase",
	"DragonRocketBase",
	"ZeusRocketBase",
	"ForeignAidRocketBase",
	"ForeignTradeRocketBase",
	"RefugeeRocketBase",
	"RocketExpeditionBase",
	"ArkPodBase",
}

-- Class-name fragments that are rocket helpers, not the rocket itself.
local excluded_class_parts = {
	"RocketLandingSite",
	"LandingSite",
	"LandingPad",
	"TradePad",
	"RocketBuilding",
	"BuildingSite",
	"ConstructionSite",
	"RocketProjectile",
}

-- State fields capture rocket command, flight, cargo, and request state.
local state_fields = {
	"command",
	"status",
	"category",
	"RocketType",
	"landed",
	"arrival_loc",
	"departure_loc",
	"landing_site",
	"reserved_site",
	"launch_time",
	"flight_time",
	"cargo",
	"rovers",
	"departures",
	"boarding",
	"boarded",
	"disembarking",
	"drones",
	"drones_entering",
	"drones_exiting",
	"refuel_request",
	"export_requests",
	"unload_request",
	"unload_fuel_request",
	"maintenance_request",
	"dust_thread",
	"departure_thread",
	"demolishing",
	"demolishing_countdown",
	"demolishing_thread",
	"destroyed",
}

-- Method availability tells us which rocket cleanup/delete paths exist.
local methods = {
	"CanDemolish",
	"DoDemolish",
	"OnDemolish",
	"ClearDone",
	"delete",
	"SetCommand",
	"ForceInterruptIncomingDrones",
	"DisconnectFromCommandCenters",
	"StopDroneControl",
	"ClearTradePad",
	"ClearDepartures",
	"ClearAllResources",
}

-- Request fields should be nil so request destructors do not index booleans.
local request_fields = {
	"refuel_request",
	"export_requests",
	"unload_request",
	"unload_fuel_request",
	"maintenance_request",
	"consumption_resource_request",
	"maintenance_resource_request",
}

-- Unit lists can hold drones or rovers that still have rocket destructors.
local unit_list_fields = {
	"drones",
	"drones_entering",
	"drones_exiting",
	"rovers",
	"boarding",
	"boarded",
	"disembarking",
}

-- Return whether a class name belongs to a rocket helper object.
local function HasExcludedClassName(class)
	for _, text in ipairs(excluded_class_parts) do
		if class:find(text, 1, true) ~= nil then
			return true
		end
	end

	return false
end

-- Stop one rocket-owned thread field.
local function StopThreadField(rocket, field)
	local thread = FD.ReadField(rocket, field)

	if FD.SafeCall(FD.Global("IsValidThread"), thread) then
		FD.SafeCall(FD.Global("DeleteThread"), thread)
	end

	FD.WriteField(rocket, field, false)
end

-- Clear request references that can keep drones or resources attached.
local function ClearRequestFields(rocket)
	for _, field in ipairs(request_fields) do
		FD.WriteField(rocket, field, nil)
	end
end

-- Return a safe fallback position for units detached from a rocket.
local function RocketFallbackPos(rocket)
	return FD.CallMethod(rocket, "GetPos") or FD.ReadField(rocket, "pos")
end

-- Detach one rocket-owned unit without invoking rocket LeadOut destructors.
local function DetachUnitFromRocket(unit, fallback_pos)
	if not FD.IsObjectValid(unit) then
		return
	end

	FD.StopCommandNoDestructors(unit)
	FD.WriteField(unit, "holder", false)
	FD.WriteField(unit, "building", false)
	FD.WriteField(unit, "target", false)
	FD.WriteField(unit, "goto_target", false)
	FD.WriteField(unit, "d_request", nil)
	FD.WriteField(unit, "s_request", nil)
	FD.WriteField(unit, "w_request", nil)
	FD.WriteField(unit, "picked_up_from_req", nil)

	if fallback_pos and type(FD.ReadField(unit, "SetPos")) == "function" then
		FD.CallObjectMethod(unit, "SetPos", fallback_pos)
	end

	FD.CallObjectMethod(unit, "SetHolder", false)
	FD.CallObjectMethod(unit, "SetOutside", true)

	if FD.Drone and FD.Drone.IsDrone(unit) then
		FD.CallObjectMethod(unit, "SetCommand", "Idle")
	end
end

-- Detach rocket-owned units before the rocket object is removed.
local function DetachUnits(rocket)
	local fallback_pos = RocketFallbackPos(rocket)
	local seen = {}

	for _, field in ipairs(unit_list_fields) do
		for _, unit in ipairs(FD.ValidObjectsFromTable(FD.ReadField(rocket, field))) do
			if not seen[unit] then
				seen[unit] = true
				DetachUnitFromRocket(unit, fallback_pos)
			end
		end

		FD.WriteField(rocket, field, {})
	end
end

-- Stop active rocket work before deletion so stale command callbacks do not run.
local function PrepareForDelete(rocket)
	FD.CallObjectMethod(rocket, "ForceInterruptIncomingDrones")
	FD.CallObjectMethod(rocket, "DisconnectFromCommandCenters")
	FD.CallObjectMethod(rocket, "StopDroneControl")
	FD.CallObjectMethod(rocket, "ClearTradePad")
	FD.CallObjectMethod(rocket, "ClearDepartures")

	StopThreadField(rocket, "dust_thread")
	StopThreadField(rocket, "departure_thread")
	FD.StopCommandNoDestructors(rocket)
	ClearRequestFields(rocket)
	DetachUnits(rocket)

	FD.WriteField(rocket, "launch_after_unload", false)
	FD.WriteField(rocket, "waiting_resources", false)
	FD.WriteField(rocket, "working", false)
	FD.WriteField(rocket, "auto_connect", false)
	FD.WriteField(rocket, "landing_disabled", true)
	FD.WriteField(rocket, "launch_disabled", true)
end

-- Detect rockets and pods while excluding landing sites and pad helpers.
function Rocket.IsRocket(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	local class = FD.ClassName(obj)
	if HasExcludedClassName(class) then
		return false
	end

	for _, class_name in ipairs(rocket_classes) do
		if FD.IsKindOf(obj, class_name) then
			return true
		end
	end

	return class:find("Rocket", 1, true) ~= nil
		or class:find("ArkPod", 1, true) ~= nil
end

-- Show rocket diagnostics for the selected object.
function Rocket.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(Rocket.GetRelevantAttributes(obj))
	end
end

-- Delete a rocket through Level 2 cleanup and direct object removal fallback.
function Rocket.Delete(rocket)
	if not Rocket.IsRocket(rocket) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nSelected object is not a rocket.")
		return false
	end

	local summary = FD.ObjectSummary(rocket)
	PrepareForDelete(rocket)

	if FD.Level2DeleteObject(rocket) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleted rocket: " .. summary)
		return true
	end

	FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nCould not delete rocket: " .. summary)
	return false
end

-- Return all currently useful rocket diagnostic attributes.
function Rocket.GetRelevantAttributes(rocket)
	local rows = {}

	FD.AddCommonObjectAttributes(rows, rocket, "rocket", "rockets require Level 2 because they own flight, cargo, and drone state")
	FD.AddFieldAttributes(rows, rocket, FD.IDENTITY_FIELDS)
	FD.AddFieldAttributes(rows, rocket, state_fields)
	FD.AddMethodDiagnostics(rows, rocket, methods)

	return {
		title = "Rocket attributes",
		rows = rows,
	}
end
