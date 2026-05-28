-- Copy Move object classification + copy/move inclusion rules.
-- Owns the single answer to "what kind of object is this?" and "should copy or
-- move include it?", so selection, copy, and dome logic stay consistent.

CopyMove = rawget(_G, "CopyMove") or {}
local CM = CopyMove
_G.CopyMove = CM

local Classify = CM.Classify or {}
CM.Classify = Classify
local Object = CM.Object

function Classify.IsColonist(obj)
	return Object.IsKindOf(obj, "Colonist")
end

function Classify.IsDrone(obj)
	return Object.IsKindOf(obj, "Drone")
end

function Classify.IsAnimal(obj)
	return Object.IsKindOf(obj, "Animal")
end

function Classify.IsDome(obj)
	return Object.IsKindOf(obj, "Dome")
end

function Classify.IsBuilding(obj)
	return Object.IsKindOf(obj, "Building")
end

-- A building that lives inside a dome (carries a valid parent_dome).
function Classify.IsInteriorBuilding(obj)
	return Classify.IsBuilding(obj)
		and Object.IsValid(Object.ReadField(obj, "parent_dome"))
end

-- A decoration / map prop is any valid object not claimed by the unit, dome, or
-- building families. This lets the selection target scenery, rocks, etc.
function Classify.IsDecoration(obj)
	if not Object.IsValid(obj) then
		return false
	end
	if Classify.IsColonist(obj) or Classify.IsDrone(obj) or Classify.IsAnimal(obj) then
		return false
	end
	if Classify.IsDome(obj) or Classify.IsBuilding(obj) then
		return false
	end
	return true
end

-- Whether an object may be selected/tinted by the mod. Everything valid is
-- selectable; the copy/move rules below decide what is acted upon.
function Classify.IsSelectable(obj)
	return Object.IsValid(obj)
end

-- Copy inclusion rule (used by group/dome copy in a later phase).
function Classify.ShouldCopy(obj)
	if not Object.IsValid(obj) then
		return false
	end
	local cfg = CM.Config
	if Classify.IsColonist(obj) then
		return cfg.COPY_INCLUDE_COLONISTS == true
	end
	if Classify.IsDrone(obj) then
		return cfg.COPY_INCLUDE_DRONES == true
	end
	if Classify.IsAnimal(obj) then
		return cfg.COPY_INCLUDE_ANIMALS == true
	end
	return true
end
