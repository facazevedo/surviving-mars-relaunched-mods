local action_id = "SelectMixedRovers_CtrlR"
local rover_selection_class = "BaseRover"
local patched_drag_selection

-- Return true only for rovers that can safely participate in a map selection wrapper.
local function IsSelectableRover(rover)
	if not IsValid(rover) or not IsKindOf(rover, "BaseRover") then
		return false
	end

	local pos = rover.GetPos and rover:GetPos()
	if not pos or IsValidPos and not IsValidPos(pos) then
		return false
	end

	if CurrentMap and rover.GetMap and rover:GetMap() ~= CurrentMap then
		return false
	end

	return true
end

-- Select one rover directly or wrap multiple rovers for vanilla multi-selection.
local function SelectRoverList(rovers)
	local count = rovers and #rovers or 0
	if count > 1 then
		SelectObj(MultiSelectionWrapper:new({
			selection_class = rover_selection_class,
			objects = rovers,
		}, rovers[1]))
		return true
	end

	if count == 1 then
		SelectObj(rovers[1])
		return true
	end

	return false
end

-- Return all currently valid rovers from the city label table.
local function GetAllSelectableRovers()
	local labels = UICity and UICity.labels
	local rovers = labels and labels.Rover or empty_table
	local result = {}

	for _, rover in ipairs(rovers) do
		if IsSelectableRover(rover) then
			result[#result + 1] = rover
		end
	end

	return result
end

-- Return true when at least one rover can be selected.
local function HasSelectableRovers()
	local labels = UICity and UICity.labels
	local rovers = labels and labels.Rover or empty_table

	for _, rover in ipairs(rovers) do
		if IsSelectableRover(rover) then
			return true
		end
	end

	return false
end

-- Select every rover in the current colony from the Ctrl+R shortcut.
local function SelectMixedRovers()
	local rovers = GetAllSelectableRovers()

	if #rovers == 1 then
		ViewAndSelectObject(rovers[1])
		return true
	end

	return SelectRoverList(rovers)
end

-- Gather rovers inside a drag rectangle across all rover subclasses.
local function GatherRoversInScreenRect(start_pt, end_pt)
	if not GatherObjectsInScreenRect then
		return empty_table
	end

	local rovers = {}
	local rovers_set = {}
	local sample_by_class = {}

	for _, rover in ipairs(GetAllSelectableRovers()) do
		local selection_class = rover.SelectionClass or rover.class or rover_selection_class
		if selection_class and not sample_by_class[selection_class] then
			sample_by_class[selection_class] = rover
		end
	end

	for selection_class, sample in pairs(sample_by_class) do
		local gathered = GatherObjectsInScreenRect(start_pt, end_pt, sample, selection_class) or empty_table
		for _, obj in ipairs(gathered) do
			if IsSelectableRover(obj) and not rovers_set[obj] then
				rovers_set[obj] = true
				rovers[#rovers + 1] = obj
			end
		end
	end

	return rovers
end

-- Patch only the selection dialog so normal non-rover selection remains stable.
local function PatchDragSelection()
	if patched_drag_selection
		or not SelectionModeDialog
		or not SelectionModeDialog.OnMousePos
		or not SelectionModeDialog.OnMouseButtonUp
	then
		return
	end

	local original_mouse_pos = SelectionModeDialog.OnMousePos

	-- Let vanilla update drag state, then normalize rover drag class.
	function SelectionModeDialog:OnMousePos(pt, button)
		local result = original_mouse_pos(self, pt, button)

		-- If vanilla sees a rover first, mark the drag as a shared rover selection
		if IsValid(self.drag_selection_obj) and IsKindOf(self.drag_selection_obj, rover_selection_class) then
			self.drag_selection_class = rover_selection_class
		end

		return result
	end

	local original_mouse_button_up = SelectionModeDialog.OnMouseButtonUp

	-- Replace vanilla button-up selection only when the drag rectangle contains rovers.
	function SelectionModeDialog:OnMouseButtonUp(pt, button)
		-- Preserve the base dialog's button-up handling before deciding how to finish selection
		if UnitDirectionModeDialog and UnitDirectionModeDialog.OnMouseButtonUp then
			local result = UnitDirectionModeDialog.OnMouseButtonUp(self, pt, button)
			if result == "break" then
				return "break"
			end
		end

		if not pt or not self.drag_start_pos or button ~= "L" then
			return original_mouse_button_up(self, pt, button)
		end

		-- Prefer mixed-rover selection whenever the drag rectangle contains rovers
		local rovers = GatherRoversInScreenRect(self.drag_start_pos, pt)
		if SelectRoverList(rovers) then
			self:CancelMultiselection()
			return "break"
		end

		return original_mouse_button_up(self, pt, button)
	end

	patched_drag_selection = true
end

-- Register the bindable Ctrl+R action for selecting all rovers.
local function AddSelectMixedRoversAction(parent, context)
	if not XAction then
		return
	end

	XAction:new({
		ActionId = action_id,
		ActionMode = "Game",
		ActionTranslate = false,
		ActionName = "Select mixed rovers",
		ActionShortcut = "Ctrl-R",
		ActionBindable = true,
		-- Enable Ctrl+R only when at least one selectable rover exists.
		ActionState = function(self, host)
			return HasSelectableRovers() and "enabled" or "disabled"
		end,
		-- Select every rover from the registered shortcut path.
		OnAction = function(self, host, source, ...)
			local dlg = GetHUD()
			if not dlg or not dlg:GetVisible() then
				return
			end

			FocusInfopanel = false
			if SelectMixedRovers() then
				return "break"
			end
		end,
		IgnoreRepeated = true,
	}, parent, context)
end

local patched
-- Patch drag behavior and register the bindable Ctrl+R shortcut once available.
local function PatchGameShortcuts()
	PatchDragSelection()

	-- GameShortcuts is initialized late, so this patch is safe to retry
	if patched or not GameShortcuts or not GameShortcuts.Init then
		return
	end

	local original_init = GameShortcuts.Init

	-- Add the Ctrl+R shortcut action after the base shortcut container initializes.
	function GameShortcuts:Init(parent, context)
		original_init(self, parent, context)
		AddSelectMixedRoversAction(parent, context)
	end

	patched = true
end

-- Preserve any existing OnMsg handler while adding this mod's retry hook.
local function ChainOnMsg(message_name, handler)
	local previous = OnMsg[message_name]

	-- Call the existing message handler first, then this mod's retry hook.
	OnMsg[message_name] = function(...)
		if previous then
			previous(...)
		end

		handler(...)
	end
end

ChainOnMsg("ClassesPostprocess", PatchGameShortcuts)
ChainOnMsg("DataLoaded", PatchGameShortcuts)
PatchGameShortcuts()
