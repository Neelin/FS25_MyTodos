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

-- Werteliste + Anzeige-Format fuer eine MultiTextOption aus der Def.
--   percent: PERCENT_MIN..PERCENT_MAX in PERCENT_STEP-Schritten, "%d %%"
--   count:   def.min..def.max in 1er-Schritten, "%d"
--   select:  def.values verbatim, Format def.valueFormat (Default "%g")
local function buildValueList(def)
    local values = {}
    local fmt
    if def.type == "count" then
        for v = (def.min or 1), (def.max or 30) do
            table.insert(values, v)
        end
        fmt = "%d"
    elseif def.type == "select" then
        values = def.values or {}
        fmt = def.valueFormat or "%g"
    else -- "percent"
        for v = MyTodos.PERCENT_MIN, MyTodos.PERCENT_MAX, MyTodos.PERCENT_STEP do
            table.insert(values, v)
        end
        fmt = "%d %%"
    end
    return values, fmt
end

-- Klont einen Multi-Text-Option-Row (extends MultiTextOptionElement) fuer
-- percent/count/select-Settings. onChange bekommt den WERT, nicht den
-- State-Index.
local function cloneMulti(def, parent, prefab, currentValue, onChange)
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
        local values, fmt = buildValueList(def)
        local texts = {}
        local stateForValue = 1
        local cur = tonumber(currentValue)
        for i, v in ipairs(values) do
            texts[i] = string.format(fmt, v)
            -- Float-tolerant vergleichen: select-Werte (z.B. 0.5) kommen
            -- als Float aus der Settings-XML zurueck.
            if cur ~= nil and math.abs(v - cur) < 1e-6 then
                stateForValue = i
            end
        end
        if setting.setTexts ~= nil then
            setting:setTexts(texts)
        end
        if setting.setState ~= nil then
            setting:setState(stateForValue, false)
        end
        setting.onClickCallback = function (_, state)
            local newValue = values[state]
            if newValue ~= nil then
                onChange(newValue)
            end
        end
        FocusManager:loadElementFromCustomValues(setting)
    end
    return row
end

-- Exponierter Section-Header-Helper: fuegt manuell eine Sub-Header-Zeile ins
-- Layout ein. Genutzt von der kombinierten Single-Page, um zwischen den
-- Gruppen (Allgemein / Tiere / Felder) Ueberschriften zu setzen.
function MyTodosSettingsUtil.addSectionHeader(text, layout, sectionPrefab)
    return cloneSectionHeader(text, layout, sectionPrefab)
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
        else
            -- percent / count / select rendern alle als MultiTextOption
            row = cloneMulti(def, layout, prefabs.multi, current,
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

-- Variante fuer eine dynamische Liste von Multi-Option-Rows (Used vom
-- Tiere-Block fuer den Per-Stall-Futter-Modus). Jedes item:
--   { label=<Stallname>, state=<1-basierter Start-Index>,
--     options={ {value=<modus>, text=<Anzeige>}, ... } }
-- onChange wird mit (item, value) des gewaehlten Options-Eintrags aufgerufen.
function MyTodosSettingsUtil.populateOptionList(items, layout, prefabs, onChange)
    local alt = false
    for _, item in ipairs(items) do
        local row = prefabs.multi:clone(layout)
        local setting = row:getDescendantByName("setting")
        local label   = row:getDescendantByName("label")

        if label ~= nil and label.setText ~= nil then
            label:setText(item.label)
        end
        if setting ~= nil then
            local texts = {}
            for i, opt in ipairs(item.options) do texts[i] = opt.text end
            if setting.setTexts ~= nil then setting:setTexts(texts) end
            if setting.setState ~= nil then setting:setState(item.state or 1, false) end
            setting.onClickCallback = function (_, state)
                local opt = item.options[state]
                if opt ~= nil then onChange(item, opt.value) end
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
