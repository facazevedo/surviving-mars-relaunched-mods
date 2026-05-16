-- Attribute Inspector mod
-- Bottom-right panel showing the currently selected object and its marker/deposit reference.

local PANEL_ID = "AttributeInspectorDialog"
local POLL_THREAD = "AttributeInspectorPoll"
local POLL_INTERVAL_MS = 250
local PANEL_Z_ORDER = 10000
local MAX_MARKER_GROUP_SCAN = 32

local AttributeInspectorDialog = false

-- Return an optional engine global without triggering mod-environment errors.
local function Global(name)
    return rawget(_G, name)
end

-- Invoke an optional function and return false instead of propagating errors.
local function SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return false
    end

    local ok, result = pcall(fn, ...)

    if ok then
        return result
    end

    return false
end

-- Check whether a map/game object still exists before inspecting it.
local function IsGameObjectValid(obj)
    if not obj then
        return false
    end

    local is_valid = Global("IsValid")

    if type(is_valid) == "function" then
        return SafeCall(is_valid, obj) and true or false
    end

    return true
end

-- Check whether an X window can still be safely updated.
local function IsWindowAlive(win)
    return win and win.window_state ~= "destroying" and win.window_state ~= "destroyed"
end

-- Test an object class relationship through the engine helper when available.
local function IsKindOf(obj, class_name)
    if not IsGameObjectValid(obj) then
        return false
    end

    return SafeCall(Global("IsKindOf"), obj, class_name) and true or false
end

-- Convert any inspected value into short, UI-safe text.
local function Text(value)
    local value_type = type(value)

    if value == nil then
        return "nil"
    end

    if value_type == "string" then
        return string.format("%q", value)
    end

    if value_type == "number" or value_type == "boolean" then
        return tostring(value)
    end

    if value_type == "function" then
        return "<function>"
    end

    local ok, result = pcall(tostring, value)

    return ok and result or string.format("<%s>", value_type)
end

-- Read a field safely from game userdata/table objects.
local function ReadField(obj, field)
    if not obj then
        return nil
    end

    local ok, value = pcall(function()
        return obj[field]
    end)

    return ok and value or nil
end

-- Call a zero-argument object method safely.
local function CallMethod(obj, method)
    local fn = ReadField(obj, method)

    if type(fn) ~= "function" then
        return nil
    end

    local ok, value = pcall(function()
        return fn(obj)
    end)

    return ok and value or nil
end

-- Read an editor/game property by id when the object supports GetProperty.
local function ReadProperty(obj, prop_id)
    if not IsGameObjectValid(obj) or type(ReadField(obj, "GetProperty")) ~= "function" then
        return nil
    end

    local ok, value = pcall(function()
        return obj:GetProperty(prop_id)
    end)

    return ok and value or nil
end

-- Return the object's class-like identifier for display.
local function ClassName(obj)
    return Text(ReadField(obj, "class") or CallMethod(obj, "GetClass") or obj)
end

-- Return the object's entity/model identifier for display.
local function EntityName(obj)
    if not IsGameObjectValid(obj) then
        return "nil"
    end

    return Text(CallMethod(obj, "GetEntity") or ReadField(obj, "entity"))
end

-- Return the object's current map/visual position for display.
local function PositionText(obj)
    if not IsGameObjectValid(obj) then
        return "nil"
    end

    return Text(CallMethod(obj, "GetPos") or CallMethod(obj, "GetVisualPos") or ReadField(obj, "pos"))
end

-- Return the object's orientation/angle for display.
local function AngleText(obj)
    if not IsGameObjectValid(obj) then
        return "nil"
    end

    return Text(CallMethod(obj, "GetAngle") or CallMethod(obj, "GetOrientation") or ReadField(obj, "angle"))
end

-- Return the runtime object handle, which can be looked up with HandleToObject.
local function HandleText(obj)
    return Text(ReadField(obj, "handle"))
end

-- Return an object's semantic id field when it has one.
local function IdText(obj)
    return Text(ReadField(obj, "id"))
end

-- Unwrap dialog contexts into the underlying property/game object.
local function ResolveContext(context)
    if not context then
        return false
    end

    local resolved = SafeCall(Global("ResolvePropObj"), context)

    return resolved or context
end

-- Look up an open dialog by id when the UI helper exists.
local function DialogById(id)
    return SafeCall(Global("GetDialog"), id)
end

-- Extract the selected object from a dialog context.
local function ContextObjectFromDialog(dialog)
    if not dialog then
        return false
    end

    local context = ReadField(dialog, "context")

    if not context then
        context = CallMethod(dialog, "GetContext")
    end

    if not context then
        context = ReadField(dialog, "Context")
    end

    local obj = ResolveContext(context)

    return IsGameObjectValid(obj) and obj or false
end

-- Return the first valid object in an array plus the original array count.
local function FirstValidFromArray(list)
    if type(list) ~= "table" then
        return false, 0
    end

    for _, obj in ipairs(list) do
        if IsGameObjectValid(obj) then
            return obj, #list
        end
    end

    return false, #list
end

-- Resolve selection while in editor-like contexts.
local function EditorSelection()
    local editor = Global("editor")

    if editor and type(editor.GetSel) == "function" then
        local obj, count = FirstValidFromArray(SafeCall(editor.GetSel))

        if obj then
            return obj, count, "editor.GetSel()"
        end
    end

    local selo = Global("selo")

    if type(selo) == "function" then
        local obj = SafeCall(selo)

        if IsGameObjectValid(obj) then
            return obj, 1, "selo()"
        end
    end

    return false, 0, "none"
end

-- Resolve selection from the normal gameplay UI.
local function GameplaySelection()
    local obj = ContextObjectFromDialog(DialogById("Infopanel"))

    if obj then
        return obj, 1, "infopanel"
    end

    obj = Global("SelectedObj")

    if IsGameObjectValid(obj) then
        return obj, 1, "SelectedObj"
    end

    local selection_obj, count = FirstValidFromArray(Global("Selection"))

    if selection_obj then
        return selection_obj, count, "Selection"
    end

    return false, 0, "none"
end

-- Return the best available selected object, count, and source label.
local function SelectedObject()
    local obj, count, source = GameplaySelection()

    if obj then
        return obj, count, source
    end

    return EditorSelection()
end

-- Detect whether an object is already a deposit marker.
local function IsMarker(obj)
    if not IsGameObjectValid(obj) then
        return false
    end

    return IsKindOf(obj, "DepositMarker")
        or IsKindOf(obj, "SurfaceDepositMarker")
        or IsKindOf(obj, "SubsurfaceDepositMarker")
        or ClassName(obj):find("DepositMarker", 1, true) ~= nil
end

-- Read a likely marker reference from either a field or property.
local function MarkerCandidate(obj, key)
    local candidate = ReadField(obj, key) or ReadProperty(obj, key)

    if IsGameObjectValid(candidate) then
        return candidate
    end

    return false
end

-- Find the marker/deposit object related to the selected object.
local function FindMarker(obj, visited)
    if not IsGameObjectValid(obj) then
        return false, "not found"
    end

    if IsMarker(obj) then
        return obj, "selected object is marker"
    end

    visited = visited or {}

    if visited[obj] then
        return false, "not found"
    end

    visited[obj] = true

    for _, key in ipairs({ "marker", "placed_obj" }) do
        local candidate = MarkerCandidate(obj, key)

        if candidate then
            return candidate, key
        end
    end

    local deposit = CallMethod(obj, "GetDeposit")

    if IsGameObjectValid(deposit) then
        return deposit, "GetDeposit()"
    end

    local group = ReadField(obj, "group")

    if type(group) == "table" then
        local scanned = 0

        for _, group_obj in ipairs(group) do
            scanned = scanned + 1

            if scanned > MAX_MARKER_GROUP_SCAN then
                break
            end

            local marker, source = FindMarker(group_obj, visited)

            if IsGameObjectValid(marker) then
                return marker, "group -> " .. source
            end
        end
    end

    return false, "not found"
end

-- Append a standard identity block for one object to the panel text.
local function AddObjectLines(lines, title, obj)
    lines[#lines + 1] = title
    lines[#lines + 1] = string.format("object = %s", Text(obj))
    lines[#lines + 1] = string.format("handle = %s", HandleText(obj))
    lines[#lines + 1] = string.format("id = %s", IdText(obj))
    lines[#lines + 1] = string.format("class = %s", ClassName(obj))
    lines[#lines + 1] = string.format("entity = %s", EntityName(obj))
    lines[#lines + 1] = string.format("pos = %s", PositionText(obj))
    lines[#lines + 1] = string.format("angle = %s", AngleText(obj))
end

-- Build the full inspector text for the selected object and its marker.
local function PanelText(obj, selected_count, source)
    local marker, marker_source = FindMarker(obj)
    local lines = {
        string.format("source = %s", source),
        string.format("selected_count = %d", selected_count or 1),
        "",
    }

    AddObjectLines(lines, "Selected object:", obj)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Object marker:"
    lines[#lines + 1] = string.format("marker_source = %s", marker_source)

    if IsGameObjectValid(marker) then
        AddObjectLines(lines, "Marker object:", marker)
    else
        lines[#lines + 1] = "marker = nil"
    end

    return table.concat(lines, "\n")
end

-- Find a panel child control by id across engine versions.
local function PanelControl(id)
    if not AttributeInspectorDialog then
        return false
    end

    local control = ReadField(AttributeInspectorDialog, id)

    if control then
        return control
    end

    local resolve_id = ReadField(AttributeInspectorDialog, "ResolveId")

    if type(resolve_id) == "function" then
        local ok, resolved = pcall(function()
            return AttributeInspectorDialog:ResolveId(id)
        end)

        if ok then
            return resolved
        end
    end

    return false
end

-- Update a text control while swallowing stale-window errors.
local function SetText(control, text)
    if type(ReadField(control, "SetText")) == "function" then
        pcall(function()
            control:SetText(text)
        end)
    end
end

-- Refresh the inspector panel with the current selected object, if any.
function AttributeInspector_UpdatePanel()
    if not IsWindowAlive(AttributeInspectorDialog) then
        return
    end

    local obj, selected_count, source = SelectedObject()
    local title = PanelControl("idTitle")
    local body = PanelControl("idBody")

    if IsGameObjectValid(obj) then
        SetText(title, string.format("Attribute Inspector  (Selected: %d)", selected_count or 1))
        SetText(body, PanelText(obj, selected_count, source))
    else
        SetText(title, "Attribute Inspector  (Selected: 0)")
        SetText(body, "")
    end
end

DefineClass.AttributeInspectorPanel = {
    __parents = { "XDialog" },
    IdNode = true,
    Dock = "box",
    HAlign = "right",
    VAlign = "bottom",
    Margins = box(0, 0, 20, 80),
    Padding = box(8, 8, 8, 8),
    LayoutMethod = "VList",
    LayoutVSpacing = 4,
    Clip = "self",
    MinWidth = 520,
    MaxWidth = 680,
    MinHeight = 260,
    MaxHeight = 560,
    Background = RGBA(0, 0, 0, 230),
    HandleMouse = true,
}

-- Construct child controls and start the polling fallback thread.
function AttributeInspectorPanel:Init()
    AttributeInspectorDialog = self

    self.idTitle = XLabel:new({
        Id = "idTitle",
        Text = "Attribute Inspector  (Selected: 0)",
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = RGB(255, 255, 255),
        HAlign = "stretch",
        VAlign = "top",
    }, self)

    self.idBody = XText:new({
        Id = "idBody",
        Text = "",
        Translate = false,
        TextStyle = "ConsoleLog",
        TextColor = RGB(255, 255, 255),
        HAlign = "stretch",
        VAlign = "top",
        WordWrap = true,
        MinHeight = 220,
        MaxHeight = 500,
        UseClipBox = true,
    }, self)

    if self.CreateThread then
        self:CreateThread(POLL_THREAD, function(dialog)
            local sleep = Global("Sleep")

            while IsWindowAlive(dialog) do
                AttributeInspectorDialog = dialog
                pcall(AttributeInspector_UpdatePanel)

                if type(sleep) ~= "function" then
                    break
                end

                sleep(POLL_INTERVAL_MS)
            end
        end, self)
    end
end

-- Create the inspector panel once the in-game UI parent is available.
function AttributeInspector_EnsurePanel()
    local parent = false
    local ok = pcall(function()
        local get_interface = Global("GetInGameInterface")
        local terminal = Global("terminal")

        parent = type(get_interface) == "function" and get_interface() or false
        parent = parent or (terminal and terminal.desktop)
    end)

    if not ok or not parent or IsWindowAlive(AttributeInspectorDialog) then
        return
    end

    pcall(function()
        AttributeInspectorDialog = AttributeInspectorPanel:new({
            Id = PANEL_ID,
            ZOrder = PANEL_Z_ORDER,
        }, parent)
    end)

    pcall(AttributeInspector_UpdatePanel)
end

-- Close the inspector panel manually from Lua/debug sessions.
function AttributeInspector_ClosePanel()
    if not IsWindowAlive(AttributeInspectorDialog) then
        return
    end

    pcall(function()
        if AttributeInspectorDialog.Close then
            AttributeInspectorDialog:Close()
        elseif AttributeInspectorDialog.Delete then
            AttributeInspectorDialog:Delete()
        end

        AttributeInspectorDialog = false
    end)
end

-- Ensure the panel exists, then refresh its contents.
local function RefreshInspector()
    AttributeInspector_EnsurePanel()
    AttributeInspector_UpdatePanel()
end

-- Create/update the panel when the gameplay interface is created.
function OnMsg.InGameInterfaceCreated()
    pcall(RefreshInspector)
end

-- Refresh when the selected gameplay object changes.
function OnMsg.SelectedObjChange()
    pcall(RefreshInspector)
end

-- Refresh when the gameplay selection table changes.
function OnMsg.SelectionChange()
    pcall(RefreshInspector)
end

-- Refresh when an object is added to multi-selection.
function OnMsg.SelectionAdded()
    pcall(RefreshInspector)
end

-- Refresh when an object is removed from multi-selection.
function OnMsg.SelectionRemoved()
    pcall(RefreshInspector)
end

-- Refresh when entering editor-style selection contexts.
function OnMsg.GameEnterEditor()
    pcall(RefreshInspector)
end

-- Refresh when leaving editor-style selection contexts.
function OnMsg.GameExitEditor()
    pcall(RefreshInspector)
end

pcall(RefreshInspector)
