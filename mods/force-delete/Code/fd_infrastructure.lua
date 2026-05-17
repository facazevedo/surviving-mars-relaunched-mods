-- Infrastructure diagnostics and deletion.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining infrastructure helpers on repeated mod loads.
if FD.infrastructure_loaded then return end
FD.infrastructure_loaded = true

-- Create the infrastructure module namespace.
FD.Infrastructure = FD.Infrastructure or {}
local Infrastructure = FD.Infrastructure

-- State fields capture common network ownership and demolition state.
local state_fields = {
	"command",
	"parent",
	"building",
	"city",
	"grid",
	"supply_grid",
	"connected",
	"demolishing",
	"demolishing_countdown",
	"demolishing_thread",
}

-- Return the infrastructure subtype used for diagnostics.
function Infrastructure.Subtype(obj)
	local class = FD.ClassName(obj)

	if FD.IsKindOf(obj, "ElectricityGridElement") or class:find("Cable", 1, true) then
		return "cable"
	end

	if FD.IsKindOf(obj, "LifeSupportGridElement") or class:find("Pipe", 1, true) then
		return "pipe"
	end

	if class:find("Track", 1, true) or class:find("Rail", 1, true) then
		return "track"
	end

	return false
end

-- Detect cables, pipes, tracks, and similar network/grid pieces.
function Infrastructure.IsInfrastructure(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	return Infrastructure.Subtype(obj) ~= false
end

-- Show infrastructure diagnostics for the selected object.
function Infrastructure.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(Infrastructure.GetRelevantAttributes(obj))
	end
end

-- Delete infrastructure through normal demolition when available.
function Infrastructure.Delete(obj)
	return FD.DeleteNamedNonUnitObject(
		obj,
		Infrastructure.IsInfrastructure(obj),
		"infrastructure",
		"Selected object is not infrastructure."
	)
end

-- Return infrastructure diagnostic attributes.
function Infrastructure.GetRelevantAttributes(obj)
	local rows = {}

	FD.AddCommonObjectAttributes(rows, obj, "infrastructure")
	FD.AddAttribute(rows, "infrastructure_subtype", Infrastructure.Subtype(obj) or "unknown")
	FD.AddFieldAttributes(rows, obj, FD.IDENTITY_FIELDS)
	FD.AddFieldAttributes(rows, obj, state_fields)
	FD.AddMethodDiagnostics(rows, obj, FD.DEMOLISHABLE_METHODS)

	return {
		title = "Infrastructure attributes",
		rows = rows,
	}
end
