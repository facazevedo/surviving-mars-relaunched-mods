-- Train diagnostic attributes and Level 2 deletion.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining train helpers on repeated mod loads.
if FD.train_loaded then return end
FD.train_loaded = true

-- Create the train module namespace.
FD.Train = FD.Train or {}
local Train = FD.Train

-- State fields capture station, track, passenger, cargo, and command state.
local state_fields = {
	"command",
	"city",
	"holder",
	"current_station",
	"station_arrival_track",
	"track",
	"is_stopping",
	"at_station",
	"at_spawn_track",
	"units",
	"assigned_resources",
	"stockpiled_amount",
	"resource_storage",
	"auto_mode_on",
	"track_anim_moments_thread",
	"command_thread",
	"thread_running_destructors",
	"command_destructors",
	"command_queue",
	"forced_cmd_importance",
	"demolishing",
	"destroyed",
	"dead",
}

-- Method availability tells us which train cleanup/delete paths exist.
local methods = {
	"SetCommand",
	"DestroySilent",
	"AssignToTrack",
	"ClearPath",
	"DoDemolish",
	"ClearDone",
	"delete",
}

-- Fields that should not keep a train attached to active transport routes.
local related_delete_fields = {
	"holder",
	"current_station",
	"station_arrival_track",
	"track",
	"track_anim_moments_thread",
}

-- Return whether a class name is a station, track, or helper rather than a train.
local function HasExcludedClassName(class)
	return class:find("Station", 1, true) ~= nil
		or class:find("Track", 1, true) ~= nil
		or class:find("Tunnel", 1, true) ~= nil
		or class:find("Building", 1, true) ~= nil
		or class:find("Construction", 1, true) ~= nil
		or class:find("Sign", 1, true) ~= nil
		or class:find("Door", 1, true) ~= nil
end

-- Remove a train from station occupancy tables.
local function RemoveFromStation(station, train)
	if not FD.IsObjectValid(station) then
		return
	end

	FD.CallObjectMethod(station, "RemoveOccupyingTrain", train)
	FD.RemoveObjectFromTable(FD.ReadField(station, "trains"), train)
	FD.RemoveObjectFromTable(FD.ReadField(station, "occupying_trains"), train)
	FD.RemoveObjectFromTable(FD.ReadField(station, "colonists_inbound"), train)
	FD.RemoveObjectFromTable(FD.ReadField(station, "waiting_for_train"), train)
end

-- Remove a train from its assigned track.
local function RemoveFromTrack(track, train)
	if not FD.IsObjectValid(track) then
		return
	end

	FD.RemoveObjectFromTable(FD.ReadField(track, "assigned_vehicles"), train)
	FD.CallObjectMethod(track, "RemoveTransportLink", train)
end

-- Detach colonist passengers before the train object is removed.
local function DetachPassengers(train)
	local units = FD.ReadField(train, "units")

	for _, unit in ipairs(FD.ValidObjectsFromTable(units)) do
		if FD.Colonist and FD.Colonist.IdleForRelatedObjectDelete then
			FD.Colonist.IdleForRelatedObjectDelete(unit)
		end

		FD.RemoveObjectFromTable(units, unit)
		FD.WriteField(unit, "holder", false)
	end

	if type(units) ~= "table" then
		FD.WriteField(train, "units", {})
	end
end

-- Clear route, station, and cargo assignment state before deletion.
local function PrepareForDelete(train)
	local city = FD.ReadField(train, "city")
	local labels = FD.ReadField(city, "labels")
	local stations = labels and labels.Station

	FD.DeactivateUnitControlFor(train)
	FD.CallObjectMethod(train, "ClearPath")
	FD.StopCommandNoDestructors(train)
	DetachPassengers(train)

	RemoveFromTrack(FD.ReadField(train, "track"), train)
	RemoveFromStation(FD.ReadField(train, "current_station"), train)

	for _, station in ipairs(FD.ValidObjectsFromTable(stations)) do
		RemoveFromStation(station, train)
	end

	for _, field in ipairs(related_delete_fields) do
		FD.WriteField(train, field, false)
	end

	FD.WriteField(train, "assigned_resources", {})
	FD.WriteField(train, "is_stopping", false)
	FD.WriteField(train, "at_station", false)
	FD.WriteField(train, "at_spawn_track", false)
end

-- Detect mobile trains while excluding train stations, tracks, and helpers.
function Train.IsTrain(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	local class = FD.ClassName(obj)
	if HasExcludedClassName(class) then
		return false
	end

	return FD.IsKindOf(obj, "Train") or class == "Train"
end

-- Detach a train from doomed objects and stop its current command.
function Train.IdleForRelatedObjectDelete(train)
	if not Train.IsTrain(train) then
		return false
	end

	PrepareForDelete(train)
	return true
end

-- Show train diagnostics for the selected object.
function Train.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(Train.GetRelevantAttributes(obj))
	end
end

-- Delete a train through Level 2 cleanup and direct object removal fallback.
function Train.Delete(train)
	if not Train.IsTrain(train) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nSelected object is not a train.")
		return false
	end

	local summary = FD.ObjectSummary(train)
	PrepareForDelete(train)

	if FD.Level2DeleteObject(train) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleted train: " .. summary)
		return true
	end

	FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nCould not delete train: " .. summary)
	return false
end

-- Return all currently useful train diagnostic attributes.
function Train.GetRelevantAttributes(train)
	local rows = {}

	FD.AddCommonObjectAttributes(rows, train, "train", "trains require Level 2 because they are live transport units")
	FD.AddFieldAttributes(rows, train, FD.IDENTITY_FIELDS)
	FD.AddFieldAttributes(rows, train, state_fields)
	FD.AddMethodDiagnostics(rows, train, methods)

	return {
		title = "Train attributes",
		rows = rows,
	}
end
