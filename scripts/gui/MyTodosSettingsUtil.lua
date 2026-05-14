--
-- MyTodosSettingsUtil
--
-- Helper-Sammlung fuer die Page-Klassen. Klonen von Prefab-Elementen
-- (Section-Header, Boolean-Toggle, Multi-Text-Option) ins ScrollingLayout
-- einer Page, plus Bindung an MyTodos.SETTING_DEFS und MyTodos.settings.
--
-- Bewusst minimal gehalten: keine eigene Setting-Klassen-Hierarchie
-- (so wie Courseplay's AIParameter*). Werte werden direkt aus
-- MyTodos.settings gelesen und ueber MyTodos:setSetting* zurueckgeschrieben.
--

MyTodosSettingsUtil = {}

-- Trennt prefab-Klone optisch durch alternierende Hintergrundfarbe,
-- damit die Liste lesbarer wird (CP nutzt dasselbe Pattern).
local COLOR_ALT_LIGHT_KEY = "fs25_colorGreyDark_50"
local COLOR_ALT_DARK_KEY  = "fs25_colorGreyDark"

local function applyAlternatingColor(element, alt)
    if element == nil or element.setImageColor == nil then return end
    if g_gui == nil or g_gui.presets == nil then return end
    local key = alt and COLOR_ALT_DARK_KEY or COLOR_ALT_LIGHT_KEY
    local preset = g_gui.presets[key]
    if preset == nil then return end
    element:setImageColor(1, unpack(GuiUtils.getColorArray(preset)))
end

-- Klont eine Sub-Title-Zeile (Section-Header). Optional, wenn ueberhaupt
-- groupKey gesetzt ist.
local function cloneSectionHeader(text, parent, sectionHeaderPrefab)
    if sectionHeaderPrefab == nil or text == nil then return end
    local header = sectionHeaderPrefab:clone(parent)
    if header.setText ~= nil then
        header:setText(text)
    end
    FocusManager:loadElementFromCustomValues(header)
    return header
end

-- Klont einen Boolean-Toggle (extends BinaryOptionElement).
-- onClickCallback: Funktion(state) wird beim Klick aufgerufen mit dem
-- neuen Boolean-Wert.
local function cloneBoolean(def, parent, prefab, currentValue, onChange)
    local row = prefab:clone(parent)
    local setting = row:getDescendantByName("setting")
    local label   = row:getDescendantByName("label")
    local tooltip = row:getDescendantByName("tooltip")

    if label ~= nil and label.setText ~= nil then
        label:setText(MyTodos:t(def.labelKey))
    end
    if tooltip ~= nil and tooltip.setText ~= nil and def.tooltipKey ~= nil then
        tooltip:setText(MyTodos:t(def.tooltipKey))
    end
    if setting ~= nil then
        if setting.setIsChecked ~= nil then
            setting:setIsChecked(currentValue == true, true, false)
        end
        setting.onClickCallback = function (_, state)
            -- BinaryOption: state==1 (LEFT/Off) oder 2 (RIGHT/On).
            -- BinaryOptionElement.STATE_RIGHT ist 2 -> "On"/checked.
            local checked = (state == BinaryOptionElement.STATE_RIGHT)
            onChange(checked)
        end
        FocusManager:loadElementFromCustomValues(setting)
    end
    return row
end

-- Klont einen Multi-Text-Option-Row (extends MultiTextOptionElement).
-- Wir haben aktuell nur "percent" (5..95 in 5er-Schritten). Texte werden
-- pre-computed.
local function clonePercent(def, parent, prefab, currentValue, onChange)
    local row = prefab:clone(parent)
    local setting = row:getDescendantByName("setting")
    local label   = row:getDescendantByName("label")
    local tooltip = row:getDescendantByName("tooltip")

    if label ~= nil and label.setText ~= nil then
        label:setText(MyTodos:t(def.labelKey))
    end
    if tooltip ~= nil and tooltip.setText ~= nil and def.tooltipKey ~= nil then
        tooltip:setText(MyTodos:t(def.tooltipKey))
    end
    if setting ~= nil then
        local texts = {}
        local stateForValue = 1
        local idx = 1
        for v = MyTodos.PERCENT_MIN, MyTodos.PERCENT_MAX, MyTodos.PERCENT_STEP do
            texts[idx] = string.format("%d %%", v)
            if v == currentValue then stateForValue = idx end
            idx = idx + 1
        end
        if setting.setTexts ~= nil then
            setting:setTexts(texts)
        end
        if setting.setState ~= nil then
            setting:setState(stateForValue, false)
        end
        setting.onClickCallback = function (_, state)
            local newValue = MyTodos.PERCENT_MIN + (state - 1) * MyTodos.PERCENT_STEP
            onChange(newValue)
        end
        FocusManager:loadElementFromCustomValues(setting)
    end
    return row
end

-- Hauptfunktion: nimmt eine gefilterte Liste von SETTING_DEFS, eine Layout-
-- Box und drei Prefab-Elemente und baut die Settings-Liste auf.
-- onChange wird pro Setting aufgerufen mit (def, newValue).
function MyTodosSettingsUtil.populateSettingsList(defs, layout, prefabs, settings, onChange)
    local alt = false
    for _, def in ipairs(defs) do
        if def.sectionHeaderKey ~= nil then
            cloneSectionHeader(MyTodos:t(def.sectionHeaderKey), layout, prefabs.section)
        end

        local typ = def.type or "bool"
        local current = settings[def.key]
        if current == nil then current = def.default end

        local row
        if typ == "bool" then
            row = cloneBoolean(def, layout, prefabs.boolean, current,
                function (v) onChange(def, v) end)
        elseif typ == "percent" then
            row = clonePercent(def, layout, prefabs.multi, current,
                function (v) onChange(def, v) end)
        end

        if row ~= nil then
            applyAlternatingColor(row, alt)
            alt = not alt
        end
    end
    layout:invalidateLayout()
end

-- Variante fuer eine dynamische Liste von Toggle-Rows mit Custom-Label
-- (Used by FieldsPage fuer "ignored field" Toggle pro eigenem Feld).
function MyTodosSettingsUtil.populateToggleList(items, layout, prefabs, onToggle)
    local alt = false
    for _, item in ipairs(items) do
        local row = prefabs.boolean:clone(layout)
        local setting = row:getDescendantByName("setting")
        local label   = row:getDescendantByName("label")

        if label ~= nil and label.setText ~= nil then
            label:setText(item.label)
        end
        if setting ~= nil then
            if setting.setIsChecked ~= nil then
                setting:setIsChecked(item.checked == true, true, false)
            end
            setting.onClickCallback = function (_, state)
                local checked = (state == BinaryOptionElement.STATE_RIGHT)
                onToggle(item, checked)
            end
            FocusManager:loadElementFromCustomValues(setting)
        end

        applyAlternatingColor(row, alt)
        alt = not alt
    end
    layout:invalidateLayout()
end

-- Hilft beim Aufraeumen: vor dem Re-Build alle Kinder einer ScrollingLayout
-- entfernen (sonst akkumulieren wir Rows beim mehrfachen Oeffnen).
function MyTodosSettingsUtil.clearLayout(layout)
    if layout == nil or layout.elements == nil then return end
    for i = #layout.elements, 1, -1 do
        local child = layout.elements[i]
        if child ~= nil and child.delete ~= nil then
            child:delete()
        end
    end
    if layout.invalidateLayout ~= nil then
        layout:invalidateLayout()
    end
end
