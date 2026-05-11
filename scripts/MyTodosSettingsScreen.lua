--
-- MyTodosSettingsScreen
--
-- Minimaler ScreenElement-Subclass: dient nur dazu, einen "echten" GUI-Kontext
-- zu oeffnen, damit die Engine die Maus von der Kamera entkoppelt
-- (gleiches Verhalten wie das ESC-Menue). Die eigentliche Darstellung
-- und Klick-Behandlung delegieren wir an MyTodos.
--

MyTodosSettingsScreen = {}
local MyTodosSettingsScreen_mt = Class(MyTodosSettingsScreen, ScreenElement)

function MyTodosSettingsScreen.new(target, customMt)
    local self = ScreenElement.new(target, customMt or MyTodosSettingsScreen_mt)
    return self
end

function MyTodosSettingsScreen:onCreate()
end

function MyTodosSettingsScreen:onOpen()
    MyTodosSettingsScreen:superClass().onOpen(self)
    if MyTodos ~= nil and MyTodos.onSettingsOpened ~= nil then
        MyTodos:onSettingsOpened()
    end
end

function MyTodosSettingsScreen:onClose()
    MyTodosSettingsScreen:superClass().onClose(self)
    if MyTodos ~= nil and MyTodos.onSettingsClosed ~= nil then
        MyTodos:onSettingsClosed()
    end
end

function MyTodosSettingsScreen:draw()
    MyTodosSettingsScreen:superClass().draw(self)
    if MyTodos ~= nil and MyTodos.drawSettingsContent ~= nil then
        MyTodos:drawSettingsContent()
    end
end

function MyTodosSettingsScreen:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    eventUsed = MyTodosSettingsScreen:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
    if not eventUsed and isDown and button == Input.MOUSE_BUTTON_LEFT then
        if MyTodos ~= nil and MyTodos.handleSettingsClick ~= nil then
            if MyTodos:handleSettingsClick(posX, posY) then
                eventUsed = true
            end
        end
    end
    return eventUsed
end

function MyTodosSettingsScreen:keyEvent(unicode, sym, modifier, isDown)
    if MyTodosSettingsScreen:superClass().keyEvent ~= nil then
        MyTodosSettingsScreen:superClass().keyEvent(self, unicode, sym, modifier, isDown)
    end
    if isDown and Input ~= nil and sym == Input.KEY_esc then
        self:close()
    end
end

function MyTodosSettingsScreen:close()
    if g_gui ~= nil and g_gui.showGui ~= nil then
        g_gui:showGui("")
    end
end
