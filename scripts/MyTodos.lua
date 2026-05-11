--
-- MyTodos
--
-- Bootstrap, Lifecycle-Hooks, HUD-Drawing und Settings-Persistenz.
-- Field-Logik liegt in MyTodosFields.lua, Husbandry in
-- MyTodosHusbandry.lua, Konsolenbefehle in MyTodosCommands.lua.
--
-- Position: das HUD ankert dynamisch an Giants' InputHelpDisplay
-- (das F1-Hilfepanel oben links). MyTodos zeichnet sich rechts davon
-- mit kleinem Abstand, mit demselben Top-Y. Wenn der Spieler F1
-- drueckt und das Hilfepanel ausblendet, bleibt MyTodos an derselben
-- Bildschirmposition kleben (Geometrie wird unabhaengig vom Visible
-- State gepflegt).
--

MyTodos = {}
MyTodos.MOD_NAME = g_currentModName
MyTodos.MOD_DIR = g_currentModDirectory
MyTodos.VERSION = "0.0.1"

MyTodos.SCAN_TIMEOUT_MS = 30000
MyTodos.RESCAN_INTERVAL_MS = 5000

-- Abstand zwischen InputHelp-rechte-Kante und MyTodos-linke-Kante
-- (normalisierte Screen-Koords).
MyTodos.HUD_ANCHOR_MARGIN_X = 0.005

-- Font-Groessen: Body-Text uebernimmt 1:1 die Groesse die Giants' InputHelp
-- gerade nutzt (in `inputHelp.textSize` per `scalePixelToScreenHeight(12)`
-- berechnet, skaliert also mit UI-Scale und Aufloesung). Title nochmal etwas
-- groesser fuer optische Hierarchie. Fallback nur falls InputHelp beim
-- ersten Draw noch nicht initialisiert ist.
MyTodos.HUD_TITLE_SCALE = 1.15
MyTodos.HUD_FALLBACK_TEXT_SIZE = 0.010
MyTodos.HUD_LINE_SPACING = 1.4
MyTodos.HUD_PAD_X = 0.010
MyTodos.HUD_PAD_Y = 0.004
MyTodos.HUD_MIN_WIDTH = 0.16
-- Pro Sektion ein eigenes Zeilen-Budget. Sonst frisst eine sehr lange
-- Sektion (z.B. 20 Felder) die andere komplett auf.
MyTodos.HUD_MAX_FIELD_LINES = 14
MyTodos.HUD_MAX_HUSB_LINES = 8

MyTodos.SETTINGS_X = 0.5
MyTodos.SETTINGS_Y = 0.7
MyTodos.SETTINGS_TEXT_SIZE = 0.014
MyTodos.SETTINGS_TITLE_SIZE = 0.016
MyTodos.SETTINGS_LINE_SPACING = 1.6
MyTodos.SETTINGS_PAD_X = 0.018
MyTodos.SETTINGS_PAD_Y = 0.008
MyTodos.SETTINGS_MIN_WIDTH = 0.22

MyTodos.HUD_BG_COLOR        = { 0,    0,    0,    0.75 }
MyTodos.HUD_HEADER_COLOR    = { 0.20, 0.40, 0.05, 0.95 }
MyTodos.HUD_TEXT_COLOR      = { 1,    1,    1,    1 }
MyTodos.HUD_DIM_COLOR       = { 0.78, 0.78, 0.78, 1 }
MyTodos.HUD_HEADER_TEXT     = { 1,    1,    1,    1 }
MyTodos.HUD_EDIT_COLOR      = { 1.0,  0.85, 0.25, 1 }

MyTodos.SETTINGS_FILENAME = "MyTodos.xml"

-- Settings catalog. type ∈ {"bool", "percent"}. percent zyklisiert
-- 5..95 in 5%-Schritten beim Klick (wrap-around). group setzt eine
-- visuelle Sub-Header in den Settings-Dialog.
MyTodos.PERCENT_STEP = 5
MyTodos.PERCENT_MIN = 5
MyTodos.PERCENT_MAX = 95

MyTodos.SETTING_DEFS = {
    -- hudVisible kann auch via Tastenkombi (Default: RShift+T, Action
    -- MYTODOS_TOGGLE_HUD) umgeschaltet werden. Hier als Fallback im
    -- Settings-Dialog, falls die Tastenbelegung vergessen wurde.
    { key = "hudVisible",  label = "HUD anzeigen",  type = "bool",    default = true },
    -- Schwellwerte: Trigger wenn Wert unter/ueber dieser Marke ist.
    -- "Futter unter 20%" heisst: Task erscheint sobald Trog unter 20% voll.
    -- "Mist ueber 80%" heisst: Task erscheint sobald Lager ueber 80% voll.
    { key = "foodThreshold",         label = "Futter unter",  type = "percent", default = 20, group = "Tiere" },
    { key = "waterThreshold",        label = "Wasser unter",  type = "percent", default = 20, group = "Tiere" },
    { key = "strawThreshold",        label = "Stroh unter",   type = "percent", default = 20, group = "Tiere" },
    { key = "meadowThreshold",       label = "Weide unter",   type = "percent", default = 20, group = "Tiere" },
    { key = "manureThreshold",       label = "Mist ueber",    type = "percent", default = 80, group = "Tiere" },
    { key = "liquidManureThreshold", label = "Guelle ueber",  type = "percent", default = 80, group = "Tiere" },
    { key = "milkThreshold",         label = "Milch ueber",   type = "percent", default = 80, group = "Tiere" },
}

-- Lifecycle ---------------------------------------------------------

function MyTodos:onMissionLoaded(mission)
    self.mission = mission
    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()

    Logging.info("[MyTodos %s] mission loaded - server=%s client=%s",
        self.VERSION, tostring(self.isServer), tostring(self.isClient))
end

function MyTodos:onMapLoaded()
    self.farmId = nil
    self.fieldTasks = {}
    self.fieldHistory = {}
    self.fieldOwnedCount = 0
    self.husbandryTasks = {}
    self.husbandryOwnedCount = 0
    self.scanWaited = 0
    self.timeSinceRescan = 0
    self.firstScanDone = false

    self.settingsOpen = false
    self.settings = {}
    for _, def in ipairs(MyTodos.SETTING_DEFS) do
        self.settings[def.key] = def.default
    end

    self:loadSettings()
    self:setupGui()

    if g_currentMission ~= nil and g_currentMission.addUpdateable ~= nil then
        g_currentMission:addUpdateable(self)
    end

    -- registerActionEvents NICHT hier aufrufen -- Giants resettet den
    -- Input-Context bei jedem On-Foot/Vehicle-Wechsel. Stattdessen via
    -- PlayerInputComponent.registerGlobalPlayerActionEvents Hook (siehe
    -- unten), der bei jedem Context-Aufbau feuert.
    self:updateMouseCursor()
end

function MyTodos:setupGui()
    if g_gui == nil or MyTodosSettingsScreen == nil then
        Logging.warning("[MyTodos] cannot setup GUI: g_gui or MyTodosSettingsScreen missing")
        return
    end
    if g_gui.guis ~= nil and g_gui.guis.MyTodosSettingsScreen ~= nil then
        return
    end
    local xmlPath = MyTodos.MOD_DIR .. "config/MyTodosSettingsScreen.xml"
    local screen = MyTodosSettingsScreen.new()
    g_gui:loadGui(xmlPath, "MyTodosSettingsScreen", screen)
    Logging.info("[MyTodos] settings GUI loaded from %s", xmlPath)
end

-- Update / scan -----------------------------------------------------

function MyTodos:update(dt)
    if self.farmId == nil then
        self.scanWaited = self.scanWaited + dt
        local farmId = self:getLocalFarmId()
        local spectatorId = FarmManager.SPECTATOR_FARM_ID
        if farmId ~= nil and farmId ~= spectatorId then
            self.farmId = farmId
            self:scanFields(true)
        elseif self.scanWaited > MyTodos.SCAN_TIMEOUT_MS then
            Logging.warning("[MyTodos] gave up waiting for local farmId after %.1fs",
                self.scanWaited / 1000)
            if g_currentMission ~= nil and g_currentMission.removeUpdateable ~= nil then
                g_currentMission:removeUpdateable(self)
            end
        end
        return
    end

    self.timeSinceRescan = self.timeSinceRescan + dt
    if self.timeSinceRescan >= MyTodos.RESCAN_INTERVAL_MS then
        self.timeSinceRescan = 0
        self:scanFields(false)
    end
end

function MyTodos:scanFields(verbose)
    if not self.firstScanDone then
        self.precisionFarming = self:detectPrecisionFarming()
    end

    local owned = self:collectOwnedFields(self.farmId)
    self.fieldOwnedCount = #owned

    -- Aggregat erzwingen, damit fieldState nicht hinterherhinkt.
    for _, entry in ipairs(owned) do
        if type(entry.field.updateState) == "function" then
            pcall(entry.field.updateState, entry.field)
        end
    end

    -- History updaten + Tasks ableiten; passive Felder rausfiltern
    local tasks = {}
    for _, entry in ipairs(owned) do
        local fs = entry.field.fieldState
        if fs ~= nil then
            self:updateFieldHistory(entry.fieldId, fs)
        end
        local task = self:deriveFieldTask(entry.field, entry.fieldId)
        if task ~= nil then
            table.insert(tasks, { fieldId = entry.fieldId, task = task })
        end
    end
    table.sort(tasks, function(a, b)
        local an = tonumber(a.fieldId) or math.huge
        local bn = tonumber(b.fieldId) or math.huge
        if an ~= bn then return an < bn end
        return tostring(a.fieldId) < tostring(b.fieldId)
    end)
    self.fieldTasks = tasks

    if verbose then
        local pf = self.precisionFarming
        local pfMsg = pf or "no"
        if pf == "loaded-inactive" then
            pfMsg = "loaded-inactive (PF-Mod registriert, aber g_precisionFarming nil -- vermutlich im Save nicht aktiviert; Verhalten wie Vanilla)"
        elseif pf == "active" then
            pfMsg = "active (g_precisionFarming verfuegbar)"
        end
        Logging.info("[MyTodos] precision farming: %s", pfMsg)
        Logging.info("[MyTodos] plowing required: %s",
            tostring(self:isPlowingRequired()))
        Logging.info("[MyTodos] local farm=%d owns %d field(s), %d with tasks (after %.2fs)",
            self.farmId, self.fieldOwnedCount, #tasks, self.scanWaited / 1000)
        for _, t in ipairs(tasks) do
            Logging.info("[MyTodos]   field %s -> %s", tostring(t.fieldId), t.task)
        end
        self.firstScanDone = true
    end

    -- Husbandries laufen im selben Polling-Tick
    self:scanHusbandries(verbose)
end

-- Action events / settings dialog -----------------------------------

function MyTodos:registerActionEvents()
    if g_inputBinding == nil then return end
    local function registerSilent(name, callback)
        local success, eventId = g_inputBinding:registerActionEvent(
            name, self, callback, false, true, false, true)
        if success and eventId ~= nil and g_inputBinding.setActionEventTextVisibility ~= nil then
            g_inputBinding:setActionEventTextVisibility(eventId, false)
        end
    end
    registerSilent("MYTODOS_TOGGLE_SETTINGS", MyTodos.onActionToggleSettings)
    registerSilent("MYTODOS_TOGGLE_HUD",      MyTodos.onActionToggleHud)
end

function MyTodos:onActionToggleSettings()
    if g_gui == nil then return end
    if g_gui.currentGuiName == "MyTodosSettingsScreen" then
        g_gui:showGui("")
    elseif g_gui.currentGui == nil then
        g_gui:showGui("MyTodosSettingsScreen")
    end
end

function MyTodos:onActionToggleHud()
    self:setSetting("hudVisible", not (self.settings.hudVisible == true))
end

function MyTodos:onSettingsOpened()
    self.settingsOpen = true
end

function MyTodos:onSettingsClosed()
    self.settingsOpen = false
    self:saveSettings()
    self:updateMouseCursor()
end

function MyTodos:setSetting(key, value)
    self.settings[key] = value
    self:saveSettings()
    self:updateMouseCursor()
    Logging.info("[MyTodos] setting %s = %s", key, tostring(value))
end

function MyTodos:_settingDef(key)
    for _, def in ipairs(MyTodos.SETTING_DEFS) do
        if def.key == key then return def end
    end
    return nil
end

function MyTodos:toggleSetting(key)
    self:setSetting(key, not self.settings[key])
end

function MyTodos:cyclePercentSetting(key)
    local def = self:_settingDef(key)
    if def == nil then return end
    local cur = self.settings[key] or def.default or MyTodos.PERCENT_MIN
    local nxt = cur + MyTodos.PERCENT_STEP
    if nxt > MyTodos.PERCENT_MAX then nxt = MyTodos.PERCENT_MIN end
    self:setSetting(key, nxt)
end

function MyTodos:updateMouseCursor()
    if g_inputBinding ~= nil and g_inputBinding.setShowMouseCursor ~= nil then
        g_inputBinding:setShowMouseCursor(self.settingsOpen)
    end
end

-- InputHelp-Metrics -------------------------------------------------
--
-- Liefert linke obere Ecke fuer das HUD plus den Body-Textsize-Wert.
-- Beides kommt aus Giants' InputHelpDisplay (das F1-Hilfepanel oben
-- links) -- so passt MyTodos pixel-genau neben das Game-Panel und nutzt
-- exakt dieselbe Schriftgroesse wie die F1-Hilfezeilen.
--
-- Bewusst KEIN Visibility-Check: lineBg.width, Position und textSize
-- werden auch dann gepflegt wenn das Panel via F1 ausgeblendet wurde --
-- so springt/aendert sich MyTodos nicht wenn der Spieler die Hilfe
-- versteckt.
function MyTodos:getHudMetrics()
    local margin = MyTodos.HUD_ANCHOR_MARGIN_X
    local anchorX = (g_hudAnchorLeft or 0) + margin
    local anchorY = g_hudAnchorTop or 1.0
    local textSize = MyTodos.HUD_FALLBACK_TEXT_SIZE
    local hud = g_currentMission and g_currentMission.hud
    local inputHelp = hud and hud.inputHelp
    if inputHelp ~= nil then
        if type(inputHelp.getPosition) == "function" then
            local ok, posX, posY = pcall(inputHelp.getPosition, inputHelp)
            if ok and posX ~= nil and posY ~= nil then
                local lineBg = inputHelp.lineBg
                local width = (lineBg and lineBg.width) or 0
                if width > 0 then
                    anchorX = posX + width + margin
                    anchorY = posY
                end
            end
        end
        if type(inputHelp.textSize) == "number" and inputHelp.textSize > 0 then
            textSize = inputHelp.textSize
        end
    end
    return anchorX, anchorY, textSize
end

-- Drawing primitives ------------------------------------------------

function MyTodos:ensureBgOverlay()
    if self.bgOverlay == nil and g_baseUIFilename ~= nil then
        self.bgOverlay = Overlay.new(g_baseUIFilename, 0, 0, 1, 1)
        if g_colorBgUVs ~= nil then
            self.bgOverlay:setUVs(g_colorBgUVs)
        end
    end
end

function MyTodos:drawPanel(left, bottom, width, height, color)
    self:ensureBgOverlay()
    if self.bgOverlay == nil then return end
    self.bgOverlay:setColor(color[1], color[2], color[3], color[4])
    self.bgOverlay:setPosition(left, bottom)
    self.bgOverlay:setDimension(width, height)
    self.bgOverlay:render()
end

-- HUD draw ----------------------------------------------------------

function MyTodos:draw()
    if not self.isClient then return end
    if g_gui ~= nil and g_gui.currentGui ~= nil then return end
    if self.fieldTasks == nil then return end
    if self.settings.hudVisible == false then return end

    self:drawHud()
end

function MyTodos:drawHud()
    -- Anker + Schriftgroesse beide aus Giants' InputHelp-Geometrie.
    local anchorX, anchorY, size = self:getHudMetrics()
    local titleSize = size * MyTodos.HUD_TITLE_SCALE
    local lineH = size * MyTodos.HUD_LINE_SPACING
    local padX = MyTodos.HUD_PAD_X
    local padY = MyTodos.HUD_PAD_Y

    local titleText = "MyTodos"
    setTextBold(true)
    local maxW = getTextWidth(titleSize, titleText)
    setTextBold(false)

    local fTasks = self.fieldTasks or {}
    local hTasks = self.husbandryTasks or {}
    local hasField = #fTasks > 0
    local hasHusb = #hTasks > 0
    local fieldOwned = self.fieldOwnedCount or 0
    local husbOwned = self.husbandryOwnedCount or 0
    local showSubHeaders = hasField and hasHusb

    local rows = {}
    local function addRow(text, color, isHeader)
        table.insert(rows, { text = text, color = color, isHeader = isHeader })
        maxW = math.max(maxW, getTextWidth(size, text))
    end

    -- Schreibt bis maxLines Tasks aus `tasks` (formatiert via fmt) ins
    -- rows-Array. Wenn ueberlaeuft, eine "(+N weitere)"-Zeile am Ende.
    local function emitSection(tasks, maxLines, fmt)
        local shown = 0
        for _, t in ipairs(tasks) do
            if shown >= maxLines then
                addRow(string.format("(+%d weitere)", #tasks - shown),
                    MyTodos.HUD_DIM_COLOR, false)
                return
            end
            addRow(fmt(t), MyTodos.HUD_TEXT_COLOR, false)
            shown = shown + 1
        end
    end

    if not hasField and not hasHusb then
        local s
        if fieldOwned == 0 and husbOwned == 0 then
            s = "(keine eigenen Felder/Tiere)"
        else
            s = "(nichts zu tun)"
        end
        addRow(s, MyTodos.HUD_DIM_COLOR, false)
    else
        if hasField then
            if showSubHeaders then
                addRow("── Felder ──", MyTodos.HUD_DIM_COLOR, true)
            end
            emitSection(fTasks, MyTodos.HUD_MAX_FIELD_LINES, function(t)
                return string.format("F%s  %s", tostring(t.fieldId), t.task)
            end)
        end

        if hasHusb then
            if showSubHeaders then
                addRow("── Tiere ──", MyTodos.HUD_DIM_COLOR, true)
            end
            emitSection(hTasks, MyTodos.HUD_MAX_HUSB_LINES, function(t)
                return t.task
            end)
        end
    end

    local panelW = math.max(MyTodos.HUD_MIN_WIDTH, maxW + 2 * padX)
    local headerH = titleSize + 2 * padY
    local bodyH = padY + #rows * lineH + padY
    local totalH = headerH + bodyH

    local panelLeft = anchorX
    local panelTop = anchorY
    local panelBottom = panelTop - totalH

    self:drawPanel(panelLeft, panelTop - headerH, panelW, headerH, MyTodos.HUD_HEADER_COLOR)
    self:drawPanel(panelLeft, panelBottom, panelW, bodyH, MyTodos.HUD_BG_COLOR)

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)

    local textLeft = panelLeft + padX

    setTextBold(true)
    setTextColor(MyTodos.HUD_HEADER_TEXT[1], MyTodos.HUD_HEADER_TEXT[2],
                 MyTodos.HUD_HEADER_TEXT[3], MyTodos.HUD_HEADER_TEXT[4])
    renderText(textLeft, panelTop - padY, titleSize, titleText)
    setTextBold(false)

    local y = panelTop - headerH - padY
    for _, row in ipairs(rows) do
        local c = row.color
        setTextColor(c[1], c[2], c[3], c[4])
        if row.isHeader then setTextBold(true) end
        renderText(textLeft, y, size, row.text)
        if row.isHeader then setTextBold(false) end
        y = y - lineH
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
    setTextColor(1, 1, 1, 1)
end

function MyTodos:_settingRowText(def)
    local typ = def.type or "bool"
    if typ == "bool" then
        local mark = self.settings[def.key] and "[X]" or "[ ]"
        return string.format("%s  %s", mark, def.label)
    elseif typ == "percent" then
        local v = self.settings[def.key] or def.default or MyTodos.PERCENT_MIN
        return string.format("[ %d%% ]  %s", v, def.label)
    end
    return def.label
end

-- Baut die Render-Liste fuer das Settings-Panel. Group-Wechsel wird in
-- eine Sub-Header-Zeile uebersetzt; sonst pro Setting eine Click-Zeile.
function MyTodos:_buildSettingRows()
    local rows = {}
    local lastGroup = nil
    for _, def in ipairs(MyTodos.SETTING_DEFS) do
        if def.group ~= lastGroup then
            if def.group ~= nil then
                table.insert(rows, {
                    isHeader = true,
                    text = "── " .. def.group .. " ──",
                })
            end
            lastGroup = def.group
        end
        table.insert(rows, {
            key = def.key,
            type = def.type or "bool",
            text = self:_settingRowText(def),
        })
    end
    return rows
end

function MyTodos:drawSettingsContent()
    local size = MyTodos.SETTINGS_TEXT_SIZE
    local titleSize = MyTodos.SETTINGS_TITLE_SIZE
    local lineH = size * MyTodos.SETTINGS_LINE_SPACING
    local padX = MyTodos.SETTINGS_PAD_X
    local padY = MyTodos.SETTINGS_PAD_Y

    local titleText = "MyTodos - Einstellungen"
    setTextBold(true)
    local maxW = getTextWidth(titleSize, titleText)
    setTextBold(false)

    local rowTexts = self:_buildSettingRows()
    for _, row in ipairs(rowTexts) do
        maxW = math.max(maxW, getTextWidth(size, row.text))
    end
    local closeText = "[ Schliessen ]"
    maxW = math.max(maxW, getTextWidth(size, closeText))

    local panelW = math.max(MyTodos.SETTINGS_MIN_WIDTH, maxW + 2 * padX)
    local headerH = titleSize + 2 * padY
    local closeRowH = lineH
    local bodyH = padY + #rowTexts * lineH + padY + closeRowH + padY
    local totalH = headerH + bodyH

    local panelLeft = MyTodos.SETTINGS_X - panelW / 2
    local panelTop = MyTodos.SETTINGS_Y
    local panelBottom = panelTop - totalH

    self:drawPanel(panelLeft, panelTop - headerH, panelW, headerH, MyTodos.HUD_HEADER_COLOR)
    self:drawPanel(panelLeft, panelBottom, panelW, bodyH, MyTodos.HUD_BG_COLOR)

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)

    setTextBold(true)
    setTextColor(MyTodos.HUD_HEADER_TEXT[1], MyTodos.HUD_HEADER_TEXT[2],
                 MyTodos.HUD_HEADER_TEXT[3], MyTodos.HUD_HEADER_TEXT[4])
    renderText(MyTodos.SETTINGS_X, panelTop - padY, titleSize, titleText)
    setTextBold(false)

    local y = panelTop - headerH - padY
    local rowBounds = {}
    local textLeft = panelLeft + padX
    for _, row in ipairs(rowTexts) do
        if row.isHeader then
            setTextAlignment(RenderText.ALIGN_CENTER)
            setTextBold(true)
            setTextColor(MyTodos.HUD_DIM_COLOR[1], MyTodos.HUD_DIM_COLOR[2],
                         MyTodos.HUD_DIM_COLOR[3], MyTodos.HUD_DIM_COLOR[4])
            renderText(MyTodos.SETTINGS_X, y, size, row.text)
            setTextBold(false)
        else
            setTextAlignment(RenderText.ALIGN_LEFT)
            setTextColor(MyTodos.HUD_TEXT_COLOR[1], MyTodos.HUD_TEXT_COLOR[2],
                         MyTodos.HUD_TEXT_COLOR[3], MyTodos.HUD_TEXT_COLOR[4])
            renderText(textLeft, y, size, row.text)
            table.insert(rowBounds, {
                key = row.key,
                type = row.type,
                left = panelLeft,
                bottom = y - lineH,
                width = panelW,
                height = lineH,
            })
        end
        y = y - lineH
    end

    -- Schliessen-Button unten zentriert
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(MyTodos.HUD_EDIT_COLOR[1], MyTodos.HUD_EDIT_COLOR[2],
                 MyTodos.HUD_EDIT_COLOR[3], MyTodos.HUD_EDIT_COLOR[4])
    y = y - padY
    renderText(MyTodos.SETTINGS_X, y, size, closeText)
    table.insert(rowBounds, {
        key = "__close__",
        left = panelLeft,
        bottom = y - lineH,
        width = panelW,
        height = lineH,
    })

    self.settingsRowBounds = rowBounds

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
    setTextColor(1, 1, 1, 1)
end

function MyTodos:handleSettingsClick(posX, posY)
    local rows = self.settingsRowBounds
    if rows == nil then return false end
    for _, row in ipairs(rows) do
        if posX >= row.left and posX <= row.left + row.width
                and posY >= row.bottom and posY <= row.bottom + row.height then
            if row.key == "__close__" then
                if g_gui ~= nil and g_gui.showGui ~= nil then
                    g_gui:showGui("")
                end
            elseif row.type == "percent" then
                self:cyclePercentSetting(row.key)
            else
                self:toggleSetting(row.key)
            end
            return true
        end
    end
    return false
end

-- Settings persistence ----------------------------------------------

function MyTodos:getSettingsPath()
    return getUserProfileAppPath() .. "modSettings/" .. MyTodos.SETTINGS_FILENAME
end

function MyTodos:loadSettings()
    local path = self:getSettingsPath()
    if not fileExists(path) then
        return
    end
    local xmlFile = loadXMLFile("MyTodosSettings", path)
    if xmlFile == nil or xmlFile == 0 then return end
    for _, def in ipairs(MyTodos.SETTING_DEFS) do
        local p = "myTodos.settings#" .. def.key
        local typ = def.type or "bool"
        if typ == "bool" then
            local v = getXMLBool(xmlFile, p)
            if v ~= nil then self.settings[def.key] = v end
        elseif typ == "percent" then
            local v = getXMLInt(xmlFile, p)
            if v ~= nil then self.settings[def.key] = v end
        end
    end
    delete(xmlFile)
    Logging.info("[MyTodos] loaded settings: hudVisible=%s",
        tostring(self.settings.hudVisible))
end

function MyTodos:saveSettings()
    createFolder(getUserProfileAppPath() .. "modSettings")
    local path = self:getSettingsPath()
    local xmlFile = createXMLFile("MyTodosSettings", path, "myTodos")
    if xmlFile == nil or xmlFile == 0 then
        Logging.warning("[MyTodos] could not create settings file at %s", path)
        return
    end
    for _, def in ipairs(MyTodos.SETTING_DEFS) do
        local p = "myTodos.settings#" .. def.key
        local typ = def.type or "bool"
        if typ == "bool" then
            setXMLBool(xmlFile, p, self.settings[def.key] and true or false)
        elseif typ == "percent" then
            setXMLInt(xmlFile, p, self.settings[def.key] or def.default or MyTodos.PERCENT_MIN)
        end
    end
    saveXMLFile(xmlFile)
    delete(xmlFile)
end

-- Helpers (von allen Modulen genutzt) -------------------------------

function MyTodos:dumpKeys(label, t)
    if t == nil then
        Logging.info("[MyTodos] %s: <nil>", label)
        return
    end
    local keys = {}
    for k, v in pairs(t) do
        local desc
        local tv = type(v)
        if tv == "number" or tv == "boolean" or tv == "string" then
            desc = string.format("%s=%s", tostring(k), tostring(v))
        else
            desc = string.format("%s=<%s>", tostring(k), tv)
        end
        table.insert(keys, desc)
    end
    table.sort(keys)
    Logging.info("[MyTodos] %s: %s", label, table.concat(keys, ", "))
end

-- Hooks -------------------------------------------------------------

Mission00.load = Utils.appendedFunction(Mission00.load, function(mission)
    MyTodos:onMissionLoaded(mission)
end)

BaseMission.loadMapFinished = Utils.appendedFunction(BaseMission.loadMapFinished, function(mission)
    MyTodos:onMapLoaded()
end)

BaseMission.draw = Utils.appendedFunction(BaseMission.draw, function(mission)
    MyTodos:draw()
end)

-- Action-Events muessen JEDES MAL neu registriert werden wenn Giants den
-- Input-Context aufbaut (on-foot <-> vehicle, GUI auf/zu, ...). Sonst sind
-- die Bindings zwar im Preferences-Menue sichtbar, feuern aber nicht.
-- Pattern wie in FS25_FarmlandOverview.
if PlayerInputComponent ~= nil then
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents,
        function(playerInput, controlling)
            MyTodos:registerActionEvents()
        end)
end
