--
-- MyTodosBasePage
--
-- Gemeinsame Basis fuer alle MyTodos-Settings-Pages. Erbt von
-- TabbedMenuFrameElement (FS25-native) und macht das Prefab-Handling
-- (unlink, clone, redraw) generisch.
--
-- Konkrete Pages (General, Husbandry, Fields) ueberschreiben:
--   self.titleKey  -- l10n-Key fuer den Header-Text
--   self:rebuild() -- baut die Layout-Inhalte auf (klont Prefabs)
--

MyTodosBasePage = {}
local MyTodosBasePage_mt = Class(MyTodosBasePage, TabbedMenuFrameElement)

function MyTodosBasePage.new(target, customMt)
    local self = TabbedMenuFrameElement.new(target, customMt or MyTodosBasePage_mt)
    self.wasOpened = false
    return self
end

-- Wird von der konkreten Subklasse aus setupGui() aufgerufen, mit dem
-- XML-Pfad ihrer eigenen Frame-XML.
function MyTodosBasePage.setupPage(class, guiName, xmlRel)
    local page = class.new()
    g_gui:loadGui(
        Utils.getFilename(xmlRel, MyTodos.MOD_DIR),
        guiName, page, true)
    return page
end

function MyTodosBasePage:initialize(menu)
    self.menu = menu

    -- Prefab-Elemente vom Layout abkoppeln (sie sind dort als Template
    -- definiert, sollen aber nicht selbst sichtbar sein). Sie werden
    -- zur Render-Zeit pro Setting/Item geklont. Pattern identisch zu
    -- CpGlobalSettingsFrame.
    self.booleanPrefab:unlinkElement()
    FocusManager:removeElement(self.booleanPrefab)
    self.multiTextPrefab:unlinkElement()
    FocusManager:removeElement(self.multiTextPrefab)
    self.sectionHeaderPrefab:unlinkElement()
    FocusManager:removeElement(self.sectionHeaderPrefab)

    self.prefabs = {
        boolean = self.booleanPrefab,
        multi   = self.multiTextPrefab,
        section = self.sectionHeaderPrefab,
    }

    if self.titleKey ~= nil and self.categoryHeaderText ~= nil then
        self.categoryHeaderText:setText(MyTodos:t(self.titleKey))
    end
end

function MyTodosBasePage:delete()
    if self.booleanPrefab ~= nil then self.booleanPrefab:delete() end
    if self.multiTextPrefab ~= nil then self.multiTextPrefab:delete() end
    if self.sectionHeaderPrefab ~= nil then self.sectionHeaderPrefab:delete() end
    MyTodosBasePage:superClass().delete(self)
end

-- Wird jedes Mal beim Aufschlagen der Page aufgerufen. Wir bauen die
-- Liste komplett neu auf -- das deckt den Fall ab dass sich Settings
-- aendern (z.B. die Liste eigener Felder fuer FieldsPage) zwischen
-- zwei Oeffnungen.
function MyTodosBasePage:onFrameOpen()
    MyTodosBasePage:superClass().onFrameOpen(self)
    if self.layout ~= nil then
        MyTodosSettingsUtil.clearLayout(self.layout)
        if self.rebuild ~= nil then
            self:rebuild()
        end
        if self.settingsSlider ~= nil and self.settingsSlider.setDataElement ~= nil then
            self.settingsSlider:setDataElement(self.layout)
        end
        FocusManager:setFocus(self.layout)
    end
end

function MyTodosBasePage:onClickCpMultiTextOption(_, _)
    -- No-op. Pages erfahren von Value-Aenderungen direkt via
    -- onClickCallback in den geklonten Settings (siehe SettingsUtil).
end
