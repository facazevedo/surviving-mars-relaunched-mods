-- Decoration diagnostic attributes and deletion.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining decoration helpers on repeated mod loads.
if FD.decorations_loaded then return end
FD.decorations_loaded = true

-- Create the decoration module namespace.
FD.Decoration = FD.Decoration or {}
local Decoration = FD.Decoration

-- Build categories and labels used by constructed decoration objects.
local decoration_categories = {
	Decorations = true,
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
	"Stone",
	"RockFormation",
	"Rocks_",
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
	for _, text in ipairs(decoration_class_parts) do
		if class:find(text, 1, true) ~= nil then
			return true
		end
	end

	return false
end

-- Return whether a class name belongs to another supported object family.
local function HasExcludedClassName(class)
	for _, text in ipairs(excluded_class_parts) do
		if class:find(text, 1, true) ~= nil then
			return true
		end
	end

	return false
end

-- Detect decorations, rocks, parks, and map props while excluding gameplay objects.
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

	return has_metadata or HasDecorationClassName(class)
end

-- Show decoration diagnostics for the selected object.
function Decoration.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(Decoration.GetRelevantAttributes(obj))
	end
end

-- Delete a decoration through normal demolition when available.
function Decoration.Delete(obj)
	return FD.DeleteNamedNonUnitObject(
		obj,
		Decoration.IsDecoration(obj),
		"decoration",
		"Selected object is not a decoration."
	)
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
