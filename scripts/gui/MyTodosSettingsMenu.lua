--
-- MyTodosSettingsMenu
--
-- TabbedMenu-Subklasse im Stil des FS25-ESC-Menues. Jede Page ist eine
-- TabbedMenuFrameElement-Subklasse mit eigener XML. Geoeffnet wird das
-- Menue per MessageCenter-Event (MessageType.GUI_MYTODOS_OPEN), nicht
-- direkt per g_gui:showGui -- so kann anderer Code spaeter optional auf
-- eine bestimmte Seite springen, analog zum Courseplay-Vorbild.
--
-- Layout (config/gui/MyTodosSettingsMenu.xml) und Profile-Namen sind
-- direkt von Courseplay's CpInGameMenu uebernommen und nutzen die
-- Vanilla-fs25_*-Profile -- Optik ist damit identisch zum ESC-Menue.
--

MyTodosSettingsMenu = {
    BASE_XML_KEY = "MyTodosSettingsMenu"
}
local MyTodosSettingsMenu_mt = Class(MyTodosSettingsMenu, TabbedMenu)

function MyTodosSettingsMenu.new(target, customMt, messageCenter, l10n, inputManager)
    local self = MyTodosSettingsMenu:superClass().new(
        target, customMt or MyTodosSettingsMenu_mt,
        messageCenter, l10n, inputManager)

    self.messageCenter = messageCenter
    self.l10n = l10n
    self.inputManager = inputManager

    self.defaultMenuButtonInfo = {}
    self.backButtonInfo = {}

    -- Subscribe vor Page-Setup -- die Page-Refs (self.pageGeneral etc.)
    -- werden erst in onGuiSetupFinished -> initializePages gesetzt, aber
    -- der Subscribe macht nichts ausser Callback registrieren.
    self.messageCenter:subscribe(MessageType.GUI_MYTODOS_OPEN, function ()
        g_gui:showGui("MyTodosSettingsMenu")
        self:changeScreen(MyTodosSettingsMenu)
        self:updatePages()
    end, self)

    return self
end

-- Statische Initialisierung -- analog Courseplay:
--   1. MessageType registrieren
--   2. Jede Page-Subklasse via setupGui() in g_gui registrieren
--   3. Hauptmenue selbst in g_gui registrieren
function MyTodosSettingsMenu.setupGui()
    if MessageType.GUI_MYTODOS_OPEN == nil then
        MessageType.GUI_MYTODOS_OPEN = nextMessageTypeId()
    end

    -- Nur noch EINE Page (kombiniert alle Settings auf einem Tab).
    MyTodosGeneralPage.setupGui()

    g_myTodosSettingsMenu = MyTodosSettingsMenu.new(
        nil, nil, g_messageCenter, g_i18n, g_inputBinding)
    g_gui:loadGui(
        Utils.getFilename("config/gui/MyTodosSettingsMenu.xml", MyTodos.MOD_DIR),
        "MyTodosSettingsMenu", g_myTodosSettingsMenu)
end

function MyTodosSettingsMenu:initializePages()
    self.clickBackCallback = function ()
        if self.currentPage and self.currentPage.onClickBack then
            self.currentPage:onClickBack(true)
        end
        self:exitMenu()
    end

    self.pageGeneral:initialize(self)
end

function MyTodosSettingsMenu:setupMenuPages()
    -- Nur noch EIN Tab: alle Settings auf einer Page. Icon = das ESC-Menue-
    -- "Einstellungen"-Tab-Icon (Zahnrad/Slider). Per mtDumpSlices als gueltiger
    -- Slice verifiziert. Alternativen falls optisch gewuenscht:
    -- gui.icon_options_generalSettings / gui.icon_options_gameSettings.
    -- (Frueheres gui.icon_options_gameplay existiert NICHT -> Kuh-Fallback;
    --  gui.icon_gear war das Getriebe-Symbol.)
    local pages = {
        { self.pageGeneral, function () return true end, "gui.icon_ingameMenu_options" },
    }
    for i, def in ipairs(pages) do
        local page, predicate, sliceId = unpack(def)
        if page ~= nil then
            self:registerPage(page, i, predicate)
            self:addPageTab(page, nil, nil, sliceId)
        end
    end
end

function MyTodosSettingsMenu:setupMenuButtonInfo()
    MyTodosSettingsMenu:superClass().setupMenuButtonInfo(self)
    local onBack = self.clickBackCallback

    self.backButtonInfo = {
        inputAction = InputAction.MENU_BACK,
        text = g_i18n:getText(InGameMenu.L10N_SYMBOL.BUTTON_BACK),
        callback = onBack,
    }

    -- Nur noch eine Page -> keine Prev/Next-Buttons, nur "Zurueck".
    self.defaultMenuButtonInfo = {
        self.backButtonInfo,
    }
    self.defaultMenuButtonInfoByActions[InputAction.MENU_BACK] = self.defaultMenuButtonInfo[1]

    self.defaultButtonActionCallbacks = {
        [InputAction.MENU_BACK] = onBack,
    }
end

function MyTodosSettingsMenu:onGuiSetupFinished()
    MyTodosSettingsMenu:superClass().onGuiSetupFinished(self)
    self:initializePages()
    self:setupMenuPages()
end

function MyTodosSettingsMenu:onMenuOpened()
    if MyTodos ~= nil and MyTodos.onSettingsOpened ~= nil then
        MyTodos:onSettingsOpened()
    end
end

function MyTodosSettingsMenu:onClose(element)
    MyTodosSettingsMenu:superClass().onClose(self, element)
    if MyTodos ~= nil and MyTodos.onSettingsClosed ~= nil then
        MyTodos:onSettingsClosed()
    end
end

function MyTodosSettingsMenu:onButtonBack()
    if self.currentPage.onClickBack then
        if not self.currentPage:onClickBack() then
            return
        end
    end
    if self.currentPage:requestClose(self.clickBackCallback) then
        MyTodosSettingsMenu:superClass().onButtonBack(self)
    end
end

function MyTodosSettingsMenu:onPageNext()
    if self.currentPage:requestClose(function ()
            TabbedMenu:superClass().onPageNext(self)
        end) then
        TabbedMenu:superClass().onPageNext(self)
    end
end

function MyTodosSettingsMenu:onPagePrevious()
    if self.currentPage:requestClose(function ()
            TabbedMenu:superClass().onPagePrevious(self)
        end) then
        TabbedMenu:superClass().onPagePrevious(self)
    end
end
