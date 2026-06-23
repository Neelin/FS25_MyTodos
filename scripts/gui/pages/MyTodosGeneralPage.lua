--
-- MyTodosGeneralPage
--
-- Seit 31.05.2026 die EINZIGE Settings-Page. Frueher gab es drei Tabs
-- (General / Husbandry / Fields); jetzt liegt alles auf EINEM Tab
-- (Zahnrad-Icon), gruppiert unter drei Section-Headern:
--   1. Allgemein  (HUD-/Header-Toggle, Zeilen-Budgets; page=="general")
--   2. Tiere      (Schwellwerte, SETTING_DEFS mit page=="husbandry")
--   3. Felder     (Sampler-Schwellwerte page=="fields" + dynamische
--                  Sichtbarkeits-Toggles pro eigenem Feld)
--
-- Klasse/XML heissen aus Kompatibilitaetsgruenden weiter "...General..."
-- (Umbenennen waere reines Bruch-Risiko ohne Mehrwert -- Frame-Name,
-- guiName, modDesc-sourceFile und XML <GUI name> muessten synchron bleiben).
--

MyTodosGeneralPage = {}
local MyTodosGeneralPage_mt = Class(MyTodosGeneralPage, MyTodosBasePage)

function MyTodosGeneralPage.new(target, customMt)
    local self = MyTodosBasePage.new(target, customMt or MyTodosGeneralPage_mt)
    -- Header oben zeigt den Mod-Namen (eigener Tab-Titel waere redundant
    -- zum Zahnrad-Icon). myTodos_hud_title = "MyTodos" in allen Sprachen.
    self.titleKey = "myTodos_hud_title"
    return self
end

function MyTodosGeneralPage.setupGui()
    MyTodosBasePage.setupPage(MyTodosGeneralPage,
        "MyTodosGeneralPage", "config/gui/pages/GeneralPage.xml")
end

-- Sammelt SETTING_DEFS einer page-Gruppe in Definitions-Reihenfolge.
local function collectDefs(pageName)
    local defs = {}
    for _, def in ipairs(MyTodos.SETTING_DEFS) do
        if def.page == pageName then
            table.insert(defs, def)
        end
    end
    return defs
end

-- Baut die Feld-Sichtbarkeits-Items (dynamisch pro eigenem Feld). Leere
-- Liste wenn keine FarmId / keine eigenen Felder. Logik 1:1 aus der
-- frueheren FieldsPage.
local function buildFieldItems()
    if MyTodos.farmId == nil then return {} end

    -- fieldId -> Eintrag, damit Felder und Paddy-Grundstuecke ohne Dubletten
    -- gesammelt und am Ende gemeinsam nach Nummer sortiert werden.
    local byId = {}
    local order = {}
    local function add(fid)
        if fid == nil or byId[fid] ~= nil then return end
        byId[fid] = {
            fieldId = fid,
            label = MyTodos:t("myTodos_settings_field_label", tostring(fid)),
            -- Toggle "an" = wird angezeigt; "aus" = ignoriert.
            checked = not MyTodos:isFieldIgnored(fid),
        }
        table.insert(order, fid)
    end

    for _, entry in ipairs(MyTodos:collectOwnedFields(MyTodos.farmId) or {}) do
        add(entry.fieldId)
    end
    -- Paddy/Perennial-Grundstuecke (Reis/Trauben/Oliven, kein Field-Objekt --
    -- siehe MyTodosPaddies.lua). paddyPlotIds wird beim Scan gefuellt und
    -- enthaelt auch ignorierte, damit sie wieder einblendbar bleiben.
    for _, fid in ipairs(MyTodos.paddyPlotIds or {}) do
        add(fid)
    end

    if #order == 0 then return {} end
    table.sort(order, function (a, b)
        local an, bn = tonumber(a), tonumber(b)
        if an ~= nil and bn ~= nil then return an < bn end
        return tostring(a) < tostring(b)
    end)

    local items = {}
    for _, fid in ipairs(order) do
        table.insert(items, byId[fid])
    end
    return items
end

-- Baut die Per-Stall-Futter-Modus-Items (dynamisch pro eigenem Stall mit
-- Trog-Futter). Optionen je Stall: Auto, <vom Stall unterstuetzte Futtertypen>,
-- Aus. Start-State = aktuell gespeicherter Modus. Bei Namens-Dubletten (zwei
-- "Kuehe") wird ein Zaehler-Suffix angehaengt, damit die Zeilen unterscheidbar
-- sind. Leere Liste wenn keine FarmId / keine passenden Staelle.
local function buildFoodModeItems()
    if MyTodos.farmId == nil then return {} end
    local list = MyTodos:collectOwnedHusbandries(MyTodos.farmId)
    if #list == 0 then return {} end

    local nameCount = {}
    for _, e in ipairs(list) do
        nameCount[e.name] = (nameCount[e.name] or 0) + 1
    end

    local seen = {}
    local items = {}
    for _, e in ipairs(list) do
        local p = e.placeable
        if type(p.spec_husbandryFood) == "table" then  -- nur Trog-Futter-Staelle
            local options = {
                { value = "auto", text = MyTodos:t("myTodos_foodmode_auto") },
            }
            for _, f in ipairs(MyTodos:_husbandrySupportedFeeds(p)) do
                table.insert(options, { value = f.name, text = f.label })
            end
            table.insert(options,
                { value = "off", text = MyTodos:t("myTodos_foodmode_off") })

            local id = MyTodos:_husbandryId(p)
            local mode = MyTodos:getHusbandryFoodMode(id)
            local state = 1
            for i, opt in ipairs(options) do
                if opt.value == mode then state = i break end
            end

            local label = e.name
            if (nameCount[e.name] or 0) > 1 then
                seen[e.name] = (seen[e.name] or 0) + 1
                label = string.format("%s %d", e.name, seen[e.name])
            end

            table.insert(items,
                { id = id, label = label, options = options, state = state })
        end
    end
    return items
end

-- Baut alle drei Sektionen nacheinander ins selbe ScrollingLayout. Wird bei
-- jedem Oeffnen aufgerufen (clearLayout passiert davor in BasePage:onFrameOpen).
function MyTodosGeneralPage:rebuild()
    local U = MyTodosSettingsUtil
    local onChange = function (def, newValue)
        MyTodos:setSetting(def.key, newValue)
    end

    -- 1. Allgemein
    U.addSectionHeader(MyTodos:t("myTodos_page_general"),
        self.layout, self.prefabs.section)
    U.populateSettingsList(collectDefs("general"), self.layout, self.prefabs,
        MyTodos.settings, onChange)

    -- 2. Tiere: erst die globalen Schwellwerte, dann pro eigenem Stall ein
    -- Futter-Modus-Selektor (Auto / konkreter Typ / Aus).
    U.addSectionHeader(MyTodos:t("myTodos_page_husbandry"),
        self.layout, self.prefabs.section)
    U.populateSettingsList(collectDefs("husbandry"), self.layout, self.prefabs,
        MyTodos.settings, onChange)
    local foodItems = buildFoodModeItems()
    if #foodItems > 0 then
        U.addSectionHeader(MyTodos:t("myTodos_foodmode_header"),
            self.layout, self.prefabs.section)
        U.populateOptionList(foodItems, self.layout, self.prefabs,
            function (item, value)
                MyTodos:setHusbandryFoodMode(item.id, value)
            end)
    end

    -- 3. Felder: erst die Sampler-Schwellwerte (SETTING_DEFS page=="fields"),
    -- dann die dynamischen Sichtbarkeits-Toggles pro eigenem Feld.
    local fieldDefs = collectDefs("fields")
    local fieldItems = buildFieldItems()
    if #fieldDefs > 0 or #fieldItems > 0 then
        U.addSectionHeader(MyTodos:t("myTodos_page_fields"),
            self.layout, self.prefabs.section)
        U.populateSettingsList(fieldDefs, self.layout, self.prefabs,
            MyTodos.settings, onChange)
        if #fieldItems > 0 then
            U.populateToggleList(fieldItems, self.layout, self.prefabs,
                function (item, checked)
                    MyTodos:setFieldIgnored(item.fieldId, not checked)
                end)
        end
    end
end
