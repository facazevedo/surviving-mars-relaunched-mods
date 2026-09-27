-- Mixed-rover selection owns only the drag completion override.
SMR_Selection = {}
local original_button_up
local patched_button_up
local patched_class
local active = false

local function IsSelectable(rover)
    if not IsValid(rover) or not IsKindOf(rover, "BaseRover") then return false end
    local pos = rover:GetPos()
    return pos and IsValidPos(pos) and rover:GetMap() == CurrentMap
end

function SMR_Selection.GetRovers()
    local result = {}
    local labels = UICity and UICity.labels
    for _, rover in ipairs(labels and labels.Rover or empty_table) do
        if IsSelectable(rover) then result[#result + 1] = rover end
    end
    return result
end

function SMR_Selection.SelectRovers(rovers)
    if #rovers > 1 then
        SelectObj(MultiSelectionWrapper:new({ selection_class = "BaseRover", objects = rovers }, rovers[1]))
    elseif #rovers == 1 then
        SelectObj(rovers[1])
    end
end

local function GatherRovers(start_pt, end_pt)
    local result, seen, samples = {}, {}, {}
    for _, rover in ipairs(SMR_Selection.GetRovers()) do
        samples[rover.SelectionClass or rover.class] = rover
    end
    for selection_class, sample in pairs(samples) do
        for _, rover in ipairs(GatherObjectsInScreenRect(start_pt, end_pt, sample, selection_class)) do
            if IsSelectable(rover) and not seen[rover] then
                seen[rover] = true
                result[#result + 1] = rover
            end
        end
    end
    return result
end

function SMR_Selection.ApplyModBehavior()
    if SMR_Config.ENABLE_MOD ~= true then
        return SMR_Selection.RestoreVanillaBehavior()
    end
    if patched_button_up then
        active = true
        return true
    end
    local class = rawget(_G, "SelectionModeDialog")
    local base = rawget(_G, "UnitDirectionModeDialog")
    if type(class) ~= "table" or type(class.OnMouseButtonUp) ~= "function"
        or type(base) ~= "table" or type(base.OnMouseButtonUp) ~= "function"
        or type(GatherObjectsInScreenRect) ~= "function" then
        SMR_Shortcuts.Log("Drag patch deferred", "selection_API_unavailable")
        return false
    end
    original_button_up = class.OnMouseButtonUp
    local original = original_button_up
    local base_button_up = base.OnMouseButtonUp
    patched_button_up = function(self, pt, button)
        if active and SMR_Config.ENABLE_MOD == true and pt and self.drag_start_pos and button == "L" then
            local rovers = GatherRovers(self.drag_start_pos, pt)
            if #rovers > 0 then
                -- Vanilla calls this base handler itself. Call it here only when
                -- replacing vanilla completion, never again on the fallback path.
                if base_button_up(self, pt, button) == "break" then return "break" end
                SMR_Selection.SelectRovers(rovers)
                self:CancelMultiselection()
                SMR_Shortcuts.Log("Completed mixed drag", "rovers=" .. tostring(#rovers))
                return "break"
            end
        end
        return original(self, pt, button)
    end
    patched_class = class
    class.OnMouseButtonUp = patched_button_up
    active = true
    SMR_Shortcuts.Log("Installed drag completion", "selection_ready")
    return true
end

function SMR_Selection.RestoreVanillaBehavior()
    active = false
    if patched_class and patched_class.OnMouseButtonUp == patched_button_up then
        patched_class.OnMouseButtonUp = original_button_up
        original_button_up, patched_button_up, patched_class = nil, nil, nil
        SMR_Shortcuts.Log("Restored drag completion", "owned_patch_removed")
    elseif patched_button_up then
        -- A later mod can retain our wrapper. Its inactive path stays vanilla.
        SMR_Shortcuts.Log("Drag wrapper dormant", "later_wrapper_owns_method")
    end
    return true
end
