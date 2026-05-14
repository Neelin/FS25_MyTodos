--
-- MyTodosHusbandryPage
--
-- Zweite Tab-Page: alle Schwellenwerte fuer Tier-Tasks (Futter, Wasser,
-- Mist, Guelle, Milch, Stroh, Weide). Werden als Multi-Text-Optionen
-- mit 5..95% in 5%-Schritten gerendert.
--

MyTodosHusbandryPage = {}
local MyTodosHusbandryPage_mt = Class(MyTodosHusbandryPage, MyTodosBasePage)

function MyTodosHusbandryPage.new(target, customMt)
    local self = MyTodosBasePage.new(target, customMt or MyTodosHusbandryPage_mt)
    self.titleKey = "myTodos_page_husbandry"
    return self
end

function MyTodosHusbandryPage.setupGui()
    MyTodosBasePage.setupPage(MyTodosHusbandryPage,
        "MyTodosHusbandryPage", "config/gui/pages/HusbandryPage.xml")
end

function MyTodosHusbandryPage:rebuild()
    local defs = {}
    for _, def in ipairs(MyTodos.SETTING_DEFS) do
        if def.page == "husbandry" then
            table.insert(defs, def)
        end
    end

    MyTodosSettingsUtil.populateSettingsList(defs, self.layout, self.prefabs,
        MyTodos.settings, function (def, newValue)
            MyTodos:setSetting(def.key, newValue)
        end)
end
