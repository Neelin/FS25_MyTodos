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

    MyTodosGeneralPage.setupGui()
    MyTodosHusbandryPage.setupGui()
    MyTodosFieldsPage.setupGui()

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
    self.pageHusbandry:initialize(self)
    self.pageFields:initialize(self)
end

function MyTodosSettingsMenu:setupMenuPages()
    -- Reihenfolge bestimmt die Tab-Reihenfolge oben. Predicate gibt true
    -- zurueck wenn der Tab aktivierbar ist (analog Courseplay --
    -- Vehicle-Tab dort nur sichtbar wenn man im Fahrzeug sitzt etc.).
    -- Bei uns alle Tabs immer aktiv.
    local pages = {
        { self.pageGeneral,   function () return true end, "gui.icon_options_gameplay" },
        { self.pageHusbandry, function () return true end, "gui.icon_options_audio" },
        { self.pageFields,    function () return true end, "gui.icon_options_controls" },
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
    local onPrev = self:makeSelfCallback(self.onPagePrevious)
    local onNext = self:makeSelfCallback(self.onPageNext)

    self.backButtonInfo = {
        inputAction = InputAction.MENU_BACK,
        text = g_i18n:getText(InGameMenu.L10N_SYMBOL.BUTTON_BACK),
        callback = onBack,
    }
    self.nextPageButtonInfo = {
        inputAction = InputAction.MENU_PAGE_NEXT,
        text = g_i18n:getText("ui_ingameMenuNext"),
        callback = self.onPageNext,
    }
    self.prevPageButtonInfo = {
        inputAction = InputAction.MENU_PAGE_PREV,
        text = g_i18n:getText("ui_ingameMenuPrev"),
        callback = self.onPagePrevious,
    }

    self.defaultMenuButtonInfo = {
        self.backButtonInfo,
        self.nextPageButtonInfo,
        self.prevPageButtonInfo,
    }
    self.defaultMenuButtonInfoByActions[InputAction.MENU_BACK]      = self.defaultMenuButtonInfo[1]
    self.defaultMenuButtonInfoByActions[InputAction.MENU_PAGE_NEXT] = self.defaultMenuButtonInfo[2]
    self.defaultMenuButtonInfoByActions[InputAction.MENU_PAGE_PREV] = self.defaultMenuButtonInfo[3]

    self.defaultButtonActionCallbacks = {
        [InputAction.MENU_BACK]      = onBack,
        [InputAction.MENU_PAGE_NEXT] = onNext,
        [InputAction.MENU_PAGE_PREV] = onPrev,
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
