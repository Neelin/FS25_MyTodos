--
-- MyTodosFieldsPage
--
-- Dritte Tab-Page: pro eigenes Feld eine Toggle-Zeile zum Ignorieren
-- (verschwindet dann komplett aus dem HUD). Persistiert pro Save+FarmId
-- via MyTodos:toggleFieldIgnored.
--

MyTodosFieldsPage = {}
local MyTodosFieldsPage_mt = Class(MyTodosFieldsPage, MyTodosBasePage)

function MyTodosFieldsPage.new(target, customMt)
    local self = MyTodosBasePage.new(target, customMt or MyTodosFieldsPage_mt)
    self.titleKey = "myTodos_page_fields"
    return self
end

function MyTodosFieldsPage.setupGui()
    MyTodosBasePage.setupPage(MyTodosFieldsPage,
        "MyTodosFieldsPage", "config/gui/pages/FieldsPage.xml")
end

function MyTodosFieldsPage:rebuild()
    if MyTodos.farmId == nil then
        return
    end
    local owned = MyTodos:collectOwnedFields(MyTodos.farmId)
    if owned == nil or #owned == 0 then
        return
    end

    table.sort(owned, function (a, b)
        local an, bn = tonumber(a.fieldId), tonumber(b.fieldId)
        if an ~= nil and bn ~= nil then return an < bn end
        return tostring(a.fieldId) < tostring(b.fieldId)
    end)

    local items = {}
    for _, entry in ipairs(owned) do
        table.insert(items, {
            fieldId = entry.fieldId,
            label = MyTodos:t("myTodos_settings_field_label",
                tostring(entry.fieldId)),
            -- HUD-Logik filtert _ignorierte_ raus -> Toggle "an" bedeutet:
            -- Feld wird _angezeigt_, "aus" = ignoriert. Intuitiver als
            -- umgekehrt.
            checked = not MyTodos:isFieldIgnored(entry.fieldId),
        })
    end

    MyTodosSettingsUtil.populateToggleList(items, self.layout, self.prefabs,
        function (item, checked)
            -- checked=true heisst angezeigt -> ignored=false.
            MyTodos:setFieldIgnored(item.fieldId, not checked)
        end)
end
