-- Internal dome building diagnostics and deletion.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining internal-building helpers on repeated mod loads.
if FD.internal_building_loaded then return end
FD.internal_building_loaded = true

-- Create the internal-building module namespace.
FD.InternalBuilding = FD.InternalBuilding or {}
local InternalBuilding = FD.InternalBuilding

-- State fields capture dome-local ownership, work, and demolition state.
local state_fields = {
	"dome",
	"parent_dome",
	"parent",
	"city",
	"workers",
	"visitors",
	"residents",
	"service_comfort_workers",
	"demolishing",
	"demolishing_countdown",
	"demolishing_thread",
	"working",
	"suspended",
}

-- Template flags that indicate an object is meant for dome interiors.
local dome_only_fields = { "dome_required", "inside_dome", "dome_only", "only_in_dome" }

-- Return whether a value explicitly says the building requires a dome.
local function IsDomeRequiredFlag(value)
	return value == true
		or value == "dome"
		or value == "inside"
		or value == "required"
		or value == "only"
end

-- Return whether a class name strongly indicates a dome-only building.
local function HasInternalClassName(class)
	return class:find("DomeBuilding", 1, true) ~= nil
		or class:find("DomeService", 1, true) ~= nil
		or class:find("DomeResidence", 1, true) ~= nil
		or class:find("DomeWorkplace", 1, true) ~= nil
end

-- Return whether object or template fields mark the building as dome-only.
local function HasDomeOnlyFlag(obj)
	for _, field in ipairs(dome_only_fields) do
		if IsDomeRequiredFlag(FD.ReadField(obj, field)) then
			return true
		end
	end

	local template = FD.ReadField(obj, "template")
		or FD.ReadField(obj, "template_obj")
		or FD.ReadField(obj, "building_template")

	for _, field in ipairs(dome_only_fields) do
		if IsDomeRequiredFlag(FD.ReadField(template, field)) then
			return true
		end
	end

	return false
end

-- Return whether an object is a building-like object.
function InternalBuilding.IsBuildingLike(obj)
	return FD.IsBuildingLike(obj)
end

-- Detect buildings that are meant to exist only inside domes.
function InternalBuilding.IsInternalBuilding(obj)
	if not InternalBuilding.IsBuildingLike(obj) then
		return false
	end

	if FD.Infrastructure and FD.Infrastructure.IsInfrastructure(obj) then
		return false
	end

	local class = FD.ClassName(obj)
	return FD.IsKindOf(obj, "DomeBuilding")
		or HasInternalClassName(class)
		or HasDomeOnlyFlag(obj)
end

-- Show internal-building diagnostics for the selected object.
function InternalBuilding.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(InternalBuilding.GetRelevantAttributes(obj))
	end
end

-- Delete an internal building through normal demolition when available.
function InternalBuilding.Delete(obj)
	return FD.DeleteNamedNonUnitObject(
		obj,
		InternalBuilding.IsInternalBuilding(obj),
		"internal building",
		"Selected object is not an internal building."
	)
end

-- Return internal-building diagnostic attributes.
function InternalBuilding.GetRelevantAttributes(obj)
	local rows = {}

	FD.AddCommonObjectAttributes(rows, obj, "internal_building")
	FD.AddFieldAttributes(rows, obj, FD.IDENTITY_FIELDS)
	FD.AddFieldAttributes(rows, obj, state_fields)
	FD.AddMethodDiagnostics(rows, obj, FD.DEMOLISHABLE_METHODS)

	return {
		title = "Internal building attributes",
		rows = rows,
	}
end
