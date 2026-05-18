-- Animal diagnostic attributes and Level 2 deletion.

-- Attach to the shared Force Delete namespace.
local FD = ForceDelete
if not FD then return end

-- Avoid redefining animal helpers on repeated mod loads.
if FD.animal_loaded then return end
FD.animal_loaded = true

-- Create the animal module namespace.
FD.Animal = FD.Animal or {}
local Animal = FD.Animal

-- State fields capture animal location, command, and target references.
local state_fields = {
	"command",
	"dome",
	"pasture",
	"holder",
	"target",
	"goto_target",
	"destination",
	"fx_moving_target",
	"command_thread",
	"thread_running_destructors",
	"command_destructors",
	"command_queue",
	"dead",
}

-- Method availability tells us which safe delete paths exist on this object.
local methods = { "SetCommand", "Die", "delete" }

-- Show one standard animal delete result message.
local function ShowDeleteResult(status, summary)
	FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\n" .. status .. " animal: " .. summary)
end

-- Ask the game's command system to kill the animal when that path exists.
local function TryCommandedDeath(animal)
	return type(FD.ReadField(animal, "Die")) == "function"
		and FD.CallObjectMethod(animal, "SetCommand", "Die")
end

-- Fall back through direct animal deletion methods.
local function TryDirectDelete(animal)
	if FD.CallObjectMethod(animal, "Die") then
		return true
	end

	if FD.CallObjectMethod(animal, "delete") then
		return true
	end

	return FD.SafeCall(FD.Global("DoneObject"), animal)
end

-- Detect live animals and pets while excluding animal-related buildings.
function Animal.IsAnimal(obj)
	if not FD.IsObjectValid(obj) then
		return false
	end

	local class = FD.ClassName(obj)
	if FD.IsKindOf(obj, "BaseAnimal")
		or FD.IsKindOf(obj, "BasePet")
		or FD.IsKindOf(obj, "Pet")
		or FD.IsKindOf(obj, "PastureAnimal") then
		return true
	end

	if class:find("Building", 1, true) then
		return false
	end

	return class:find("Animal", 1, true) ~= nil
		or class:find("Pet", 1, true) ~= nil
end

-- Show animal diagnostics for the selected object.
function Animal.OnSelected(obj)
	if FD.DisplayAttributes then
		FD.DisplayAttributes.Show(Animal.GetRelevantAttributes(obj))
	end
end

-- Delete an animal through the safest available game path.
function Animal.Delete(animal)
	if not Animal.IsAnimal(animal) then
		FD.ShowDeleteMessage("Ctrl+Shift+Delete pressed.\n\nSelected object is not an animal.")
		return false
	end

	local summary = FD.ObjectSummary(animal)

	-- Prefer the game's animal death command for normal cleanup.
	if TryCommandedDeath(animal) then
		ShowDeleteResult("Deleting", summary)
		return true
	end

	if TryDirectDelete(animal) then
		ShowDeleteResult("Deleted", summary)
		return true
	end

	ShowDeleteResult("Could not delete", summary)
	return false
end

-- Return all currently useful animal diagnostic attributes.
function Animal.GetRelevantAttributes(animal)
	local rows = {}

	FD.AddCommonObjectAttributes(rows, animal, "animal")

	-- Add identity values first so the selected object is easy to recognize.
	FD.AddFieldAttributes(rows, animal, FD.IDENTITY_FIELDS)

	-- Add current command, location, and target references.
	FD.AddFieldAttributes(rows, animal, state_fields)

	-- Show which future reset/delete methods are present.
	FD.AddMethodDiagnostics(rows, animal, methods)

	return {
		title = "Animal attributes",
		rows = rows,
	}
end
