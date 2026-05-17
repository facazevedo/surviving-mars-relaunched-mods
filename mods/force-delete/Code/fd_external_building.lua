-- External building diagnostics and deletion.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining external-building helpers on repeated mod loads.
if FD.external_building_loaded then return end
FD.external_building_loaded = true

-- Create the external-building module namespace.
FD.ExternalBuilding = FD.ExternalBuilding or {}
local ExternalBuilding = FD.ExternalBuilding

-- State fields capture production, city, stockpile, and demolition state.
local state_fields = {
	"city",
	"dome",
	"parent",
	"building",
	"workers",
	"drones",
	"stockpiles",
	"consumption_resource_request",
	"maintenance_resource_request",
	"consumption_resource_stockpile",
	"demolishing",
	"demolishing_countdown",
	"demolishing_thread",
	"working",
	"suspended",
	"last_production_start_ts",
}

-- Return whether an object is a non-unit building-like object.
function ExternalBuilding.IsBuildingLike(obj)
	return FD.IsBuildingLike(obj)
end

-- Detect external buildings while excluding infrastructure and dome-only buildings.
function ExternalBuilding.IsExternalBuilding(obj)
	if not ExternalBuilding.IsBuildingLike(obj) or FD.IsProtectedUnit(obj) then
		return false
	end

	if FD.Infrastructure and FD.Infrastructure.IsInfrastructure(obj) then
		return false
	end

	if FD.InternalBuilding and FD.InternalBuilding.IsInternalBuilding(obj) then
		return false
	end

	if FD.IsDomeLikeObject(obj) then
		return false
	end

	return true
end

-- Show external-building diagnostics for the selected object.
function ExternalBuilding.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(ExternalBuilding.GetRelevantAttributes(obj))
	end
end

-- Delete an external building through normal demolition when available.
function ExternalBuilding.Delete(obj)
	return FD.DeleteNamedNonUnitObject(
		obj,
		ExternalBuilding.IsExternalBuilding(obj),
		"external building",
		"Selected object is not an external building."
	)
end

-- Return external-building diagnostic attributes.
function ExternalBuilding.GetRelevantAttributes(obj)
	local rows = {}

	FD.AddCommonObjectAttributes(rows, obj, "external_building")
	FD.AddFieldAttributes(rows, obj, FD.IDENTITY_FIELDS)
	FD.AddFieldAttributes(rows, obj, state_fields)
	FD.AddMethodDiagnostics(rows, obj, FD.DEMOLISHABLE_METHODS)

	return {
		title = "External building attributes",
		rows = rows,
	}
end
