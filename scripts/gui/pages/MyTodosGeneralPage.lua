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
    local owned = MyTodos:collectOwnedFields(MyTodos.farmId)
    if owned == nil or #owned == 0 then return {} end

    table.sort(owned, function (a, b)
        local an, bn = tonumber(a.fieldId), tonumber(b.fieldId)
        if an ~= nil and bn ~= nil then return an < bn end
        return tostring(a.fieldId) < tostring(b.fieldId)
    end)

    local items = {}
    for _, entry in ipairs(owned) do
        table.insert(items, {
            fieldId = entry.fieldId,
            label = MyTodos:t("myTodos_settings_field_label", tostring(entry.fieldId)),
            -- Toggle "an" = Feld wird angezeigt; "aus" = ignoriert.
            checked = not MyTodos:isFieldIgnored(entry.fieldId),
        })
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

    -- 2. Tiere
    U.addSectionHeader(MyTodos:t("myTodos_page_husbandry"),
        self.layout, self.prefabs.section)
    U.populateSettingsList(collectDefs("husbandry"), self.layout, self.prefabs,
        MyTodos.settings, onChange)

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
