--
-- MyTodosOverviewDialog
--
-- Komplettuebersicht (RShift+O) als echter Engine-Dialog (MessageDialog-
-- Subklasse, geoeffnet via g_gui:showDialog). Dadurch uebernimmt die
-- Engine Input-Context, Fokus, Gamepad-Scrolling und das Schliessen per
-- ESC / Controller-B (MENU_BACK am Back-Button-Profil). Das fruehere
-- reine draw()-Overlay kannte keinen Input-Context und war nicht
-- controllerfreundlich. Architektur-Vorbild: FS25_FarmlandOverview
-- (FieldDlgFrame).
--
-- Inhalt: eine SmoothList mit Sektionen (Felder / Tiere). Die Section-
-- Header kommen nativ ueber das listSectionHeader-Template +
-- getTitleForSectionHeader. Zeilen kommen aus den strukturierten
-- Task-Daten des letzten Scans (fieldTasks[].primary/parallel,
-- husbandryTasks[].numAnimals/parts).
--
-- BEWUSST KEIN "empty"-ListItem-Template: SmoothListElement waehlt bei
-- nur-einem-Daten-Template einen singularCellName ueber pairs() -- mit
-- einem zusaetzlichen empty-Template koennte dabei das falsche Template
-- gewinnen. Der Leer-Fall laeuft stattdessen als header-lose Sektion
-- mit einer Hinweis-Zeile.
--

MyTodosOverviewDialog = {}
local MyTodosOverviewDialog_mt = Class(MyTodosOverviewDialog, MessageDialog)

function MyTodosOverviewDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or MyTodosOverviewDialog_mt)
    self.sections = {}
    return self
end

-- Einmalig aus MyTodos:setupGui() aufgerufen. Die Custom-Profile sind
-- dort bereits via g_gui:loadProfiles geladen.
function MyTodosOverviewDialog.setupGui()
    if g_gui.guis ~= nil and g_gui.guis.MyTodosOverviewDialog ~= nil then
        return
    end
    g_myTodosOverviewDialog = MyTodosOverviewDialog.new()
    g_gui:loadGui(
        Utils.getFilename("config/gui/OverviewDialog.xml", MyTodos.MOD_DIR),
        "MyTodosOverviewDialog", g_myTodosOverviewDialog)
end

function MyTodosOverviewDialog:onGuiSetupFinished()
    MyTodosOverviewDialog:superClass().onGuiSetupFinished(self)
    self.taskTable:setDataSource(self)
    self.taskTable:setDelegate(self)
end

-- Beim Oeffnen: ein frischer Silent-Scan damit der Dialog den Live-Stand
-- zeigt (das HUD pollt nur alle 5s), dann Sektionen/Zeilen bauen.
function MyTodosOverviewDialog:onOpen()
    MyTodosOverviewDialog:superClass().onOpen(self)

    if MyTodos.farmId ~= nil then
        MyTodos:scanFields(false)
    end

    self.sections = {}

    local fieldRows = {}
    for _, t in ipairs(MyTodos.fieldTasks or {}) do
        table.insert(fieldRows, {
            icon = t.iconFile,
            name = MyTodos:t("myTodos_settings_field_label", tostring(t.fieldId)),
            task = t.primary or t.task or "",
            extra = table.concat(t.parallel or {}, ", "),
        })
    end
    if #fieldRows > 0 then
        table.insert(self.sections, {
            title = string.upper(MyTodos:t("myTodos_section_fields")),
            rows = fieldRows,
        })
    end

    local husbRows = {}
    for _, t in ipairs(MyTodos.husbandryTasks or {}) do
        local name = t.name or ""
        if t.numAnimals ~= nil then
            name = string.format("%s (%d)", name, t.numAnimals)
        end
        table.insert(husbRows, {
            icon = t.iconFile,
            name = name,
            task = (t.parts ~= nil and table.concat(t.parts, ", ")) or t.task or "",
            extra = "",
        })
    end
    if #husbRows > 0 then
        table.insert(self.sections, {
            title = string.upper(MyTodos:t("myTodos_section_animals")),
            rows = husbRows,
        })
    end

    -- Leerer Stand: header-lose Sektion (title=nil unterdrueckt den
    -- Section-Header in SmoothListElement) mit einer Hinweis-Zeile.
    if #self.sections == 0 then
        local msgKey = "myTodos_hud_nothing_to_do"
        if (MyTodos.fieldOwnedCount or 0) == 0
                and (MyTodos.husbandryOwnedCount or 0) == 0 then
            msgKey = "myTodos_hud_no_owned"
        end
        table.insert(self.sections, {
            title = nil,
            rows = { { icon = nil, name = "", task = MyTodos:t(msgKey), extra = "" } },
        })
    end

    self.taskTable:reloadData()

    self:setSoundSuppressed(true)
    FocusManager:setFocus(self.taskTable)
    self:setSoundSuppressed(false)
end

function MyTodosOverviewDialog:onClose()
    self.sections = {}
    MyTodosOverviewDialog:superClass().onClose(self)
end

-- SmoothList dataSource ----------------------------------------------

function MyTodosOverviewDialog:getNumberOfSections(list)
    return #self.sections
end

function MyTodosOverviewDialog:getNumberOfItemsInSection(list, section)
    local sec = self.sections[section]
    if sec == nil then return 0 end
    return #sec.rows
end

function MyTodosOverviewDialog:getTitleForSectionHeader(list, section)
    local sec = self.sections[section]
    if sec == nil then return nil end
    return sec.title
end

function MyTodosOverviewDialog:populateCellForItemInSection(list, section, index, cell)
    local sec = self.sections[section]
    local row = sec ~= nil and sec.rows[index] or nil
    if row == nil then return end

    local icon = cell:getAttribute("ftIcon")
    if icon ~= nil then
        if row.icon ~= nil then
            icon:setImageFilename(row.icon)
            icon:setVisible(true)
        else
            icon:setVisible(false)
        end
    end
    cell:getAttribute("name"):setText(row.name)
    cell:getAttribute("task"):setText(row.task)
    cell:getAttribute("extra"):setText(row.extra)
end

function MyTodosOverviewDialog:onClickBack(sender)
    self:close()
end
