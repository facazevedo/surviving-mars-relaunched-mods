-- Shuttle diagnostic attributes and Level 2 deletion.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining shuttle helpers on repeated mod loads.
if FD.shuttle_loaded then return end
FD.shuttle_loaded = true

-- Create the shuttle module namespace.
FD.Shuttle = FD.Shuttle or {}
local Shuttle = FD.Shuttle

-- State fields capture mobile shuttle routing, task, passenger, and resource state.
local state_fields = {
	"command",
	"holder",
	"target",
	"goto_target",
	"destination",
	"transport_task",
	"transport_request",
	"request",
	"resource_request",
	"passenger",
	"passengers",
	"colonist",
	"colonists",
	"resource",
	"amount",
	"dome",
	"city",
	"hub",
	"shuttle_hub",
	"command_thread",
	"thread_running_destructors",
	"command_destructors",
	"command_queue",
	"dead",
}

-- Method availability tells us which safe delete paths exist on this object.
local methods = { "SetCommand", "ClearPath", "delete" }

-- Fields that can keep a shuttle command pointing at soon-deleted objects.
local related_delete_fields = {
	"holder",
	"target",
	"goto_target",
	"destination",
	"transport_request",
	"request",
	"resource_request",
	"dest_dome",
}

-- Free one shuttle landing reservation from a valid landing container.
local function FreeLandingSpot(container, shuttle)
	if FD.IsObjectValid(container) then
		FD.CallObjectMethod(container, "FreeLandingSpot", shuttle)
	end
end

-- Return whether a task looks like the colonist shuttle transport object.
local function IsColonistTransportTask(task)
	if type(task) ~= "table" and type(task) ~= "userdata" then
		return false
	end

	return FD.ReadField(task, "source_dome") ~= nil
		or FD.ReadField(task, "dest_dome") ~= nil
		or FD.ReadField(task, "colonist") ~= nil
end

-- Clear a colonist transport task without letting it resume after deletion.
local function ClearColonistTransportTask(shuttle, task)
	local colonist = FD.ReadField(task, "colonist")
	local is_current_task = FD.ReadField(shuttle, "transport_task") == task

	FreeLandingSpot(FD.ReadField(task, "source_dome"), shuttle)
	FreeLandingSpot(FD.ReadField(task, "dest_dome"), shuttle)

	if FD.IsObjectValid(colonist) and FD.ReadField(colonist, "transport_task") == task then
		FD.WriteField(colonist, "transport_task", false)
	end

	-- Current shuttle commands may still read transport_task.state before the
	-- command thread stops, so keep the task object and mark it finished.
	FD.WriteField(task, "state", "done")

	if not is_current_task and FD.ReadField(task, "shuttle") == shuttle then
		FD.WriteField(task, "shuttle", false)
	end
end

-- Clear shuttle transport state before related objects are deleted.
local function PrepareForRelatedObjectDelete(shuttle)
	local task = FD.ReadField(shuttle, "transport_task")
	local keep_colonist_task = IsColonistTransportTask(task)

	FD.CallObjectMethod(shuttle, "LandingEnd")
	FD.CallObjectMethod(shuttle, "WaitingEnd")
	FD.CallObjectMethod(shuttle, "ClearPath")
	FD.CallObjectMethod(shuttle, "ClearRequests")

	if keep_colonist_task then
		ClearColonistTransportTask(shuttle, task)
		keep_colonist_task = FD.ReadField(shuttle, "transport_task") == task
			and FD.ReadField(shuttle, "is_colonist_transport_task") == true
	end

	FreeLandingSpot(FD.ReadField(shuttle, "dest_dome"), shuttle)

	for _, field in ipairs(related_delete_fields) do
		FD.WriteField(shuttle, field, false)
	end

	FD.WriteField(shuttle, "assigned_to_d_req", false)
	FD.WriteField(shuttle, "assigned_to_s_req", false)

	if not keep_colonist_task then
		FD.WriteField(shuttle, "transport_task", false)
		FD.WriteField(shuttle, "is_colonist_transport_task", false)
	end

	FD.WriteField(shuttle, "history_entry", false)
	FD.WriteField(shuttle, "landing", false)
	FD.WriteField(shuttle, "waiting", false)
end

-- Detect mobile shuttles while excluding shuttle hubs and buildings.
function Shuttle.IsShuttle(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	local class = FD.ClassName(obj)
	if class:find("Hub", 1, true)
		or class:find("Building", 1, true)
		or class:find("Construction", 1, true) then
		return false
	end

	return FD.IsKindOf(obj, "Shuttle")
		or class:find("Shuttle", 1, true) ~= nil
end

-- Detach a shuttle from doomed objects and stop its current route.
function Shuttle.IdleForRelatedObjectDelete(shuttle)
	if not Shuttle.IsShuttle(shuttle) then
		return false
	end

	FD.StopCommandNoDestructors(shuttle)
	PrepareForRelatedObjectDelete(shuttle)
	return true
end

-- Show shuttle diagnostics for the selected object.
function Shuttle.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(Shuttle.GetRelevantAttributes(obj))
	end
end

-- Delete a shuttle through direct object removal paths.
function Shuttle.Delete(shuttle)
	if not Shuttle.IsShuttle(shuttle) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nSelected object is not a shuttle.")
		return false
	end

	local summary = FD.ObjectSummary(shuttle)

	-- Clear path if available so the shuttle is not actively navigating.
	FD.CallObjectMethod(shuttle, "ClearPath")

	-- Prefer the object's own delete method when available.
	if FD.CallObjectMethod(shuttle, "delete") then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleted shuttle: " .. summary)
		return true
	end

	-- Use DoneObject as the final engine-level fallback.
	if FD.SafeCall(FD.Global("DoneObject"), shuttle) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nDeleted shuttle: " .. summary)
		return true
	end

	FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nCould not delete shuttle: " .. summary)
	return false
end

-- Return all currently useful shuttle diagnostic attributes.
function Shuttle.GetRelevantAttributes(shuttle)
	local rows = {}

	FD.AddCommonObjectAttributes(rows, shuttle, "shuttle")

	-- Add identity values first so the selected object is easy to recognize.
	FD.AddFieldAttributes(rows, shuttle, FD.IDENTITY_FIELDS)

	-- Add routing, transport, passenger, and resource references.
	FD.AddFieldAttributes(rows, shuttle, state_fields)

	-- Show which future reset/delete methods are present.
	FD.AddMethodDiagnostics(rows, shuttle, methods)

	return {
		title = "Shuttle attributes",
		rows = rows,
	}
end
