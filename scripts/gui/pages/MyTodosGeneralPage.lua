--
-- MyTodosGeneralPage
--
-- Erste Tab-Page: allgemeine HUD-Einstellungen. Aktuell nur "HUD anzeigen".
-- Spaeter Platz fuer weitere globale Schalter.
--

MyTodosGeneralPage = {}
local MyTodosGeneralPage_mt = Class(MyTodosGeneralPage, MyTodosBasePage)

function MyTodosGeneralPage.new(target, customMt)
    local self = MyTodosBasePage.new(target, customMt or MyTodosGeneralPage_mt)
    self.titleKey = "myTodos_page_general"
    return self
end

function MyTodosGeneralPage.setupGui()
    MyTodosBasePage.setupPage(MyTodosGeneralPage,
        "MyTodosGeneralPage", "config/gui/pages/GeneralPage.xml")
end

function MyTodosGeneralPage:rebuild()
    local defs = {}
    for _, def in ipairs(MyTodos.SETTING_DEFS) do
        if def.page == "general" then
            table.insert(defs, def)
        end
    end

    MyTodosSettingsUtil.populateSettingsList(defs, self.layout, self.prefabs,
        MyTodos.settings, function (def, newValue)
            MyTodos:setSetting(def.key, newValue)
        end)
end
