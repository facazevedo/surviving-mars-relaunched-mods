-- Decoration diagnostic attributes and deletion.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining decoration helpers on repeated mod loads.
if FD.decoration_loaded then return end
FD.decoration_loaded = true

-- Create the decoration module namespace.
FD.Decoration = FD.Decoration or {}
local Decoration = FD.Decoration

-- Build categories and labels used by constructed decoration objects.
local decoration_categories = {
	Decorations = true,
	OutsideDecorations = true,
	RockFormations = true,
	Sceneries = true,
}

-- Label names used by parks, rock formations, lights, and similar decoration objects.
local decoration_labels = {
	Decoration = true,
	Decorations = true,
	Park = true,
	Parks = true,
	Garden = true,
	RockFormation = true,
	RockFormations = true,
	FlowerLamp = true,
}

-- Metadata fields used by decoration templates and placed decoration objects.
local metadata_fields = { "build_category", "label1", "label2", "label3" }

-- Class-name fragments for map props and non-building decorations.
local decoration_class_parts = {
	"Decoration",
	"Decor",
	"Garden",
	"Rock",
	"rock",
	"Stone",
	"RockFormation",
	"Rocks_",
	"rocks",
	"RocksDark",
	"Boulder",
	"Crater",
	"Debris",
	"Cliff",
	"Bush",
	"SurfacePassageRocks",
	"UndergroundPassageRocks",
	"WasteRockObstructor",
	"LightSphereHalo",
	"LightPillarHalo",
}

-- Generic terrain classes need id/entity checks before they count as decorations.
local terrain_class_parts = {
	"TerrainObj",
	"TerrainObject",
	"TerrainProp",
	"TerrainDecal",
}

-- Terrain id/entity fragments used by large rocks and other scenario props.
local terrain_prop_parts = {
	"Boulder",
	"Bush",
	"Cliff",
	"Crater",
	"Debris",
	"Rock",
	"rock",
	"Rocks",
	"rocks",
	"Sand01_stones",
	"SandRed_stones",
	"Stone",
	"stones",
	"SurfacePassageRocks",
	"Underground_Rocks",
	"UndergroundPassageRocks",
	"WasteRockObstructor",
}

-- Fields that often hold terrain prop ids or entity names.
local terrain_prop_fields = {
	"id",
	"name",
	"display_name",
	"template_name",
	"entity",
}

-- Class-name fragments that should not be claimed as decorations.
local excluded_class_parts = {
	"Colonist",
	"Drone",
	"Rover",
	"Shuttle",
	"Rocket",
	"Dome",
	"Deposit",
	"Marker",
	"BuildingSite",
	"ConstructionSite",
	"WasteRockDump",
	"WasteRockProcessor",
}

-- State fields capture decoration ownership and demolition state.
local state_fields = {
	"city",
	"dome",
	"parent",
	"parent_dome",
	"build_category",
	"label1",
	"label2",
	"label3",
	"template_name",
	"entity",
	"demolishing",
	"demolishing_countdown",
	"demolishing_thread",
	"destroyed",
}

-- Return whether text contains any literal fragment from one list.
local function TextContainsAny(text, parts)
	text = FD.SafeToString(text)

	for _, part in ipairs(parts) do
		if text:find(part, 1, true) ~= nil then
			return true
		end
	end

	return false
end

-- Return whether one value names a decoration category or label.
local function IsDecorationName(value)
	local text = FD.SafeToString(value)

	return decoration_categories[text] == true or decoration_labels[text] == true
end

-- Return whether object or template fields mark the object as a decoration.
local function HasDecorationMetadata(obj)
	for _, field in ipairs(metadata_fields) do
		if IsDecorationName(FD.ReadField(obj, field)) then
			return true
		end
	end

	local template = FD.ReadField(obj, "template")
		or FD.ReadField(obj, "template_obj")
		or FD.ReadField(obj, "building_template")

	for _, field in ipairs(metadata_fields) do
		if IsDecorationName(FD.ReadField(template, field)) then
			return true
		end
	end

	return false
end

-- Return whether a class name looks like a decoration or map prop.
local function HasDecorationClassName(class)
	return TextContainsAny(class, decoration_class_parts)
end

-- Return whether a class name belongs to another supported object family.
local function HasExcludedClassName(class)
	return TextContainsAny(class, excluded_class_parts)
end

-- Return whether a generic terrain object looks like a placed rock/prop.
local function HasTerrainPropSignature(obj, class)
	if not TextContainsAny(class, terrain_class_parts) then
		return false
	end

	for _, field in ipairs(terrain_prop_fields) do
		if TextContainsAny(FD.ReadField(obj, field), terrain_prop_parts) then
			return true
		end
	end

	return TextContainsAny(FD.CallMethod(obj, "GetEntity"), terrain_prop_parts)
end

-- Notify editor systems before direct map-prop removal.
local function BeginEditorDelete(obj)
	FD.SafeCall(FD.Global("SuspendPassEditsForEditOp"))
	FD.SafeCall(FD.Global("Msg"), "EditorCallback", "EditorCallbackDelete", { obj })
end

-- Resume editor systems after direct map-prop removal.
local function EndEditorDelete()
	FD.SafeCall(FD.Global("ResumePassEditsForEditOp"))
end

-- Delete non-demolishable map props the same way Attribute Inspector does.
local function DeleteMapPropDirect(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	local delete = FD.ReadField(obj, "delete")
	local done_object = FD.Global("DoneObject")
	local can_delete = type(delete) == "function"
	local can_done_object = type(done_object) == "function"

	if not can_delete and not can_done_object then
		return false
	end

	BeginEditorDelete(obj)

	local ok = pcall(function()
		if can_delete then
			delete(obj)
			return
		end

		done_object(obj)
	end)

	EndEditorDelete()
	return ok
end

-- Delete decorations through demolition when possible or direct map-prop removal.
local function DeleteDecorationObject(obj)
	if FD.IsDemolishable(obj) or FD.IsDemolishedBuilding(obj) then
		return FD.DeleteNonUnitObject(obj)
	end

	return DeleteMapPropDirect(obj)
end

-- Detect explicit decorations and otherwise accept unclaimed map props as decorations.
function Decoration.IsDecoration(obj)
	if not FD.IsObjectValid(obj) or FD.IsProtectedUnit(obj) or FD.IsDomeLikeObject(obj) then
		return false
	end

	if FD.Deposit and FD.Deposit.IsDeposit(obj) then
		return false
	end

	if FD.Infrastructure and FD.Infrastructure.IsInfrastructure(obj) then
		return false
	end

	if FD.Rover and FD.Rover.IsRover(obj) then
		return false
	end

	local class = FD.ClassName(obj)
	local has_metadata = HasDecorationMetadata(obj)

	if HasExcludedClassName(class) and not has_metadata then
		return false
	end

	if has_metadata or HasDecorationClassName(class) or HasTerrainPropSignature(obj, class) then
		return true
	end

	-- Decoration is the final dispatch type, so any valid object not claimed by
	-- an explicit module is treated as a removable scenario/map prop.
	return true
end

-- Show decoration diagnostics for the selected object.
function Decoration.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(Decoration.GetRelevantAttributes(obj))
	end
end

-- Delete a decoration through normal demolition when available.
function Decoration.Delete(obj)
	if not Decoration.IsDecoration(obj) then
		FD.ShowDeleteMessage("Force delete pressed.\n\nSelected object is not a decoration.")
		return false
	end

	local summary = FD.ObjectSummary(obj)

	if DeleteDecorationObject(obj) then
		FD.ShowDeleteMessage("Force delete pressed.\n\nDeleted decoration: " .. summary)
		return true
	end

	FD.ShowDeleteMessage("Force delete pressed.\n\nCould not delete decoration: " .. summary)
	return false
end

-- Return decoration diagnostic attributes.
function Decoration.GetRelevantAttributes(obj)
	local rows = {}

	FD.AddCommonObjectAttributes(rows, obj, "decoration")
	FD.AddFieldAttributes(rows, obj, FD.IDENTITY_FIELDS)
	FD.AddFieldAttributes(rows, obj, state_fields)
	FD.AddMethodDiagnostics(rows, obj, FD.DEMOLISHABLE_METHODS)

	return {
		title = "Decoration attributes",
		rows = rows,
	}
end
