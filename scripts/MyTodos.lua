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
-- Version kommt aus der modDesc.xml (single source of truth) -- eine
-- haendisch gepflegte Kopie hier drin driftet nur.
MyTodos.VERSION = "?"
if g_modManager ~= nil and type(g_modManager.getModByName) == "function" then
    local modInfo = g_modManager:getModByName(g_currentModName)
    if modInfo ~= nil and modInfo.version ~= nil then
        MyTodos.VERSION = tostring(modInfo.version)
    end
end

-- Nach so langer Wartezeit ohne farmId loggen wir EINMAL einen Hinweis
-- (kein Aufgeben mehr -- wir pollen weiter, siehe reconcileFarmId).
MyTodos.SCAN_TIMEOUT_MS = 30000
MyTodos.RESCAN_INTERVAL_MS = 5000
-- Takt fuer den farmId-Abgleich (Erst-Zuweisung, Admin-Farmwechsel,
-- Farmverlust). Bewusst kurz: Erstzuweisung soll schnell greifen, der
-- Aufwand ist ein simpler getFarmId()-Vergleich.
MyTodos.FARM_POLL_INTERVAL_MS = 3000

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

MyTodos.HUD_BG_COLOR        = { 0,    0,    0,    0.75 }
MyTodos.HUD_HEADER_COLOR    = { 0.20, 0.40, 0.05, 0.95 }
MyTodos.HUD_TEXT_COLOR      = { 1,    1,    1,    1 }
MyTodos.HUD_DIM_COLOR       = { 0.78, 0.78, 0.78, 1 }
MyTodos.HUD_SEP_COLOR       = { 1,    1,    1,    0.22 }
MyTodos.HUD_HEADER_TEXT     = { 1,    1,    1,    1 }

MyTodos.SETTINGS_FILENAME = "MyTodos.xml"

-- Settings catalog. type ∈ {"bool", "percent", "count", "select"}.
--   percent: MultiTextOption 5..95 in 5%-Schritten (Int-persistiert)
--   count:   MultiTextOption def.min..def.max in 1er-Schritten (Int)
--   select:  MultiTextOption mit fester Werteliste def.values, Anzeige
--            via def.valueFormat (Float-persistiert, fuer 0.5er-Schritte)
MyTodos.PERCENT_STEP = 5
MyTodos.PERCENT_MIN = 5
MyTodos.PERCENT_MAX = 95

-- Werteliste fuer "select"-Settings: from..to inklusive, in step-Schritten.
local function buildRange(from, to, step)
    local out = {}
    local v = from
    while v <= to + 1e-9 do
        table.insert(out, v)
        v = v + step
    end
    return out
end

-- labelKey ist ein l10n-Key (aus l10n/l10n_<lang>.xml).
-- page bestimmt unter welchem Section-Header die Option im Settings-Menue
-- erscheint ("general", "husbandry", "fields"). Die Sichtbarkeits-Toggles
-- pro eigenem Feld werden zusaetzlich dynamisch gebaut, nicht aus
-- SETTING_DEFS.
MyTodos.SETTING_DEFS = {
    -- hudVisible kann auch via Tastenkombi (Default: RShift+T, Action
    -- MYTODOS_TOGGLE_HUD) umgeschaltet werden. Hier als Fallback im
    -- Settings-Menue, falls die Tastenbelegung vergessen wurde.
    { key = "hudVisible",  labelKey = "myTodos_setting_hudVisible",  type = "bool",    default = true, page = "general" },
    -- Gruene Titelleiste ("MyTodos") ueber dem HUD ausblendbar.
    { key = "hudShowHeader", labelKey = "myTodos_setting_hudShowHeader", type = "bool", default = true, page = "general" },
    -- Zeilen-Budget pro HUD-Sektion (1..30). Min 1 garantiert dass immer
    -- mindestens ein Feld bzw. eine Tier-Zeile sichtbar bleibt; Ueberlauf
    -- wird wie bisher zur "(+N weitere)"-Zeile. Die Komplettuebersicht
    -- (RShift+O) ignoriert beide Caps.
    { key = "maxFieldLines", labelKey = "myTodos_setting_maxFieldLines", type = "count", default = 14, min = 1, max = 30, page = "general" },
    { key = "maxHusbLines",  labelKey = "myTodos_setting_maxHusbLines",  type = "count", default = 8,  min = 1, max = 30, page = "general" },
    -- Schwellwerte: Trigger wenn Wert unter/ueber dieser Marke ist.
    -- "Futter unter 20%" heisst: Task erscheint sobald Trog unter 20% voll.
    -- "Mist ueber 80%" heisst: Task erscheint sobald Lager ueber 80% voll.
    { key = "foodThreshold",         labelKey = "myTodos_setting_foodThreshold",         type = "percent", default = 20, page = "husbandry" },
    { key = "waterThreshold",        labelKey = "myTodos_setting_waterThreshold",        type = "percent", default = 20, page = "husbandry" },
    { key = "strawThreshold",        labelKey = "myTodos_setting_strawThreshold",        type = "percent", default = 20, page = "husbandry" },
    { key = "meadowThreshold",       labelKey = "myTodos_setting_meadowThreshold",       type = "percent", default = 20, page = "husbandry" },
    { key = "manureThreshold",       labelKey = "myTodos_setting_manureThreshold",       type = "percent", default = 80, page = "husbandry" },
    { key = "liquidManureThreshold", labelKey = "myTodos_setting_liquidManureThreshold", type = "percent", default = 80, page = "husbandry" },
    { key = "milkThreshold",         labelKey = "myTodos_setting_milkThreshold",         type = "percent", default = 80, page = "husbandry" },
    -- Sampler-Schwellen in % der Feldflaeche (Schwad/Steine) bzw. der
    -- gewichteten Unkraut-Abdeckung. Defaults = bisheriges Verhalten
    -- (WINDROW_/STONE_MIN_FRACTION 0.5%, WEED_TOTAL_MIN_FACTOR 2%, siehe
    -- MyTodosFields.lua). Die 50-Pixel-Floors bleiben zusaetzlich aktiv.
    { key = "windrowThreshold", labelKey = "myTodos_setting_windrowThreshold", type = "select", values = buildRange(0.5, 10, 0.5), valueFormat = "%g %%", default = 0.5, page = "fields" },
    { key = "stonesThreshold",  labelKey = "myTodos_setting_stonesThreshold",  type = "select", values = buildRange(0.5, 10, 0.5), valueFormat = "%g %%", default = 0.5, page = "fields" },
    { key = "weedThreshold",    labelKey = "myTodos_setting_weedThreshold",    type = "select", values = buildRange(0.5, 10, 0.5), valueFormat = "%g %%", default = 2, page = "fields" },
}

-- l10n-Helper: zieht einen Text aus l10n/l10n_<lang>.xml und applied
-- string.format wenn weitere Argumente uebergeben werden. Fallback
-- (g_i18n nicht da) liefert den Key, damit nichts crasht.
function MyTodos:t(key, ...)
    if g_i18n == nil or type(g_i18n.getText) ~= "function" then
        return key
    end
    local text = g_i18n:getText(key)
    if select("#", ...) > 0 then
        return string.format(text, ...)
    end
    return text
end

-- Liste aller l10n-Keys die irgendwo im Code per self:t() referenziert
-- werden. Single source of truth fuer den Self-Check beim Mod-Start.
-- Wenn ein neuer Key dazukommt: hier eintragen damit der Check ihn
-- mitvalidiert (und beide Sprachdateien gepflegt werden).
MyTodos.L10N_KEYS = {
    "myTodos_hud_title", "myTodos_hud_no_owned", "myTodos_hud_nothing_to_do",
    "myTodos_hud_more", "myTodos_hud_field_row", "myTodos_overview_title",
    "myTodos_overview_col_name", "myTodos_overview_col_task",
    "myTodos_overview_col_extra",
    "myTodos_section_fields", "myTodos_section_animals",
    "myTodos_page_general", "myTodos_page_husbandry", "myTodos_page_fields",
    "myTodos_setting_hudVisible", "myTodos_setting_hudShowHeader",
    "myTodos_setting_maxFieldLines", "myTodos_setting_maxHusbLines",
    "myTodos_setting_windrowThreshold", "myTodos_setting_stonesThreshold",
    "myTodos_setting_weedThreshold",
    "myTodos_setting_foodThreshold",
    "myTodos_setting_waterThreshold", "myTodos_setting_strawThreshold",
    "myTodos_setting_meadowThreshold", "myTodos_setting_manureThreshold",
    "myTodos_setting_liquidManureThreshold", "myTodos_setting_milkThreshold",
    "myTodos_settings_field_label",
    "myTodos_task_plow", "myTodos_task_seed", "myTodos_task_cultivate",
    "myTodos_task_roll", "myTodos_task_mulch", "myTodos_task_lime",
    "myTodos_task_stones", "myTodos_task_fertilize",
    "myTodos_task_no_fieldstate",
    "myTodos_fruit_withered", "myTodos_fruit_cut", "myTodos_fruit_harvest",
    "myTodos_fruit_forage", "myTodos_fruit_growing", "myTodos_fruit_regrowing",
    "myTodos_weed_large_pct", "myTodos_weed_small_pct",
    "myTodos_weed_large", "myTodos_weed_small",
    "myTodos_pf_lime_label", "myTodos_pf_lime_strong_acid",
    "myTodos_pf_n_label", "myTodos_pf_n_deficit",
    "myTodos_windrow_straw", "myTodos_windrow_grass", "myTodos_windrow_hay",
    "myTodos_windrow_alfalfa", "myTodos_windrow_alfalfa_hay",
    "myTodos_husb_default_name", "myTodos_husb_food", "myTodos_husb_tmr",
    "myTodos_husb_water",
    "myTodos_husb_meadow", "myTodos_husb_straw", "myTodos_husb_manure",
    "myTodos_husb_liquid_manure", "myTodos_husb_pallets_full_suffix",
    "myTodos_husb_pallets_full",
}

-- Validiert beim Mod-Start dass alle in MyTodos.L10N_KEYS gelisteten Keys
-- in der aktuellen Sprachdatei existieren. Schweigt wenn alles passt;
-- sonst eine sammelnde Warning ins Log. Hilft uns wenn jemand eine neue
-- Sprache anlegt oder einen Key vergisst zu pflegen.
function MyTodos:checkL10n()
    if g_i18n == nil or type(g_i18n.hasText) ~= "function" then return end
    local missing = {}
    for _, key in ipairs(MyTodos.L10N_KEYS) do
        if not g_i18n:hasText(key) then
            table.insert(missing, key)
        end
    end
    if #missing == 0 then return end
    Logging.warning("[MyTodos] %d l10n key(s) missing in active language: %s",
        #missing, table.concat(missing, ", "))
end

-- Lifecycle ---------------------------------------------------------

function MyTodos:onMissionLoaded(mission)
    self.mission = mission
    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()

    Logging.info("[MyTodos %s] mission loaded - server=%s client=%s",
        self.VERSION, tostring(self.isServer), tostring(self.isClient))
end

-- Map-gebundene Caches invalidieren. Das Script laedt nur einmal pro
-- Spielprozess, onMapLoaded feuert aber bei jedem Save-/Map-Wechsel --
-- Density-Map-Sampler, PF-Map-Refs, fillType-Indizes und Icon-Overlays
-- gelten nur fuer die jeweils geladene Map (+ Mod-Set) und wuerden sonst
-- auf tote Handles der vorherigen Map zeigen.
function MyTodos:resetPerMapCaches()
    -- Field-Sampler (MyTodosFields.lua); *SamplerReady = nil triggert Re-Init
    self.windrowSamplerReady = nil
    self.windrowMod = nil
    self.windrowHeightMod = nil
    self.windrowHeightFilter = nil
    self.windrowFilters = nil
    self.stoneSamplerReady = nil
    self.stoneMod = nil
    self.stoneFilters = nil
    self.weedSamplerReady = nil
    self.weedMod = nil
    self.weedFilters = nil
    self.weedFactors = nil
    self.phSamplerReady = nil
    self.phMod = nil
    self.phMap = nil
    self.nSamplerReady = nil
    self.nMod = nil
    self.nMap = nil
    self.soilSamplerReady = nil
    self.soilMod = nil
    self.soilMap = nil
    self.soilFilters = nil
    self._pfPHMapCached = nil
    self._pfNMapCached = nil
    self.precisionFarming = nil
    -- Husbandry (MyTodosHusbandry.lua)
    self._tmrFillTypeIdxCached = nil
    -- HUD-Overlays: Engine-Handles explizit freigeben, nicht nur vergessen
    if self._iconOverlayCache ~= nil then
        for _, ov in pairs(self._iconOverlayCache) do
            if ov ~= false then pcall(delete, ov) end
        end
        self._iconOverlayCache = nil
    end
    if self.bgOverlay ~= nil then
        if type(self.bgOverlay.delete) == "function" then
            pcall(self.bgOverlay.delete, self.bgOverlay)
        end
        self.bgOverlay = nil
    end
end

function MyTodos:onMapLoaded()
    self:resetPerMapCaches()
    self.farmId = nil
    self.fieldTasks = {}
    self.fieldHistory = {}
    self.fieldOwnedCount = 0
    self.husbandryTasks = {}
    self.husbandryOwnedCount = 0
    self.scanWaited = 0
    self.timeSinceRescan = 0
    self.firstScanDone = false
    -- Auf Intervall vorinitialisiert, damit der allererste update()-Tick
    -- sofort pollt (kein kuenstlicher Delay beim ersten HUD).
    self.farmPollTimer = MyTodos.FARM_POLL_INTERVAL_MS
    self._farmWaitLogged = false

    self.settingsOpen = false
    self.settings = {}
    for _, def in ipairs(MyTodos.SETTING_DEFS) do
        self.settings[def.key] = def.default
    end

    -- Ignorierte Felder: pro (Savegame, FarmId)-Kombination eine Tabelle
    -- { [fieldId] = true }. Wird aus MyTodos.xml geladen, ueberlebt
    -- Save-Reload + neue Saves nebeneinander. saveKey wird lazy beim
    -- ersten Scan berechnet (braucht farmId).
    self.ignoredFieldsAllSaves = {}
    self.saveKey = nil

    self:loadSettings()
    self:checkL10n()
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
    if g_gui == nil or MyTodosSettingsMenu == nil or MyTodosOverviewDialog == nil then
        Logging.warning("[MyTodos] cannot setup GUI: g_gui or GUI classes missing")
        return
    end
    if g_gui.guis ~= nil and g_gui.guis.MyTodosSettingsMenu ~= nil then
        return
    end
    -- Custom-Profile MUESSEN vor loadGui geladen werden, damit die
    -- XML-Files sie auflösen koennen.
    g_gui:loadProfiles(MyTodos.MOD_DIR .. "config/gui/GUIProfiles.xml")
    MyTodosSettingsMenu.setupGui()
    MyTodosOverviewDialog.setupGui()
    Logging.info("[MyTodos] settings menu + overview dialog registered")
end

-- Update / scan -----------------------------------------------------

function MyTodos:update(dt)
    -- MyTodos ist reines Client-HUD. Auf einem Dedicated Server (kein lokaler
    -- Spieler -> isClient=false) gibt es keine lokale Farm und nichts zu
    -- zeichnen -> gar nicht erst pollen/scannen. (draw() ist genauso geschuetzt.)
    if not self.isClient then return end

    -- farmId laufend mit der Engine abgleichen statt nur einmal beim Start:
    --  - frisch beigetretene MP-Spieler bekommen erst spaeter eine Farm
    --  - Admins koennen zur Laufzeit zwischen Farms wechseln
    --  - jemand kann eine Farm verlassen (zurueck zu Spectator)
    -- Daher dauerhaft gedrosselt pollen, nie endgueltig aufgeben/removeUpdateable.
    self.farmPollTimer = (self.farmPollTimer or 0) + dt
    if self.farmPollTimer >= MyTodos.FARM_POLL_INTERVAL_MS then
        local elapsed = self.farmPollTimer
        self.farmPollTimer = 0
        self:reconcileFarmId(elapsed)
    end

    if self.farmId == nil then
        return
    end

    self.timeSinceRescan = self.timeSinceRescan + dt
    if self.timeSinceRescan >= MyTodos.RESCAN_INTERVAL_MS then
        self.timeSinceRescan = 0
        self:scanFields(false)
    end
end

-- Gleicht self.farmId mit der lebenden Engine-FarmId ab und reagiert auf
-- alle drei MP-Faelle. Wird gedrosselt aus update() gepollt (FARM_POLL_INTERVAL_MS).
-- elapsed = vergangene Zeit seit dem letzten Poll (fuer das Wartezeit-Logging).
function MyTodos:reconcileFarmId(elapsed)
    local spectatorId = FarmManager.SPECTATOR_FARM_ID
    local live = self:getLocalFarmId()
    local valid = live ~= nil and live ~= spectatorId

    if valid then
        if self.farmId ~= live then
            local previous = self.farmId
            self.farmId = live
            self.saveKey = nil          -- saveKey haengt an farmId -> neu berechnen
            self.fieldHistory = {}      -- History galt fuer die alte Farm
            self.scanWaited = 0
            self._farmWaitLogged = false
            self.timeSinceRescan = 0
            if previous == nil then
                Logging.info("[MyTodos] local farmId assigned (%s) - scanning",
                    tostring(live))
            else
                Logging.info("[MyTodos] local farmId changed %s -> %s - rescanning",
                    tostring(previous), tostring(live))
            end
            self:scanFields(true)
        end
        return
    end

    -- Keine gueltige Farm (Spectator / noch nicht zugewiesen).
    if self.farmId ~= nil then
        -- War zugewiesen, jetzt nicht mehr -> zurueck in den Warte-Zustand,
        -- alte Tasks raeumen damit das HUD nichts Stale zeigt.
        Logging.info("[MyTodos] local farm lost (spectator/none) - waiting for (re)assignment")
        self.farmId = nil
        self.saveKey = nil
        self.fieldTasks = {}
        self.husbandryTasks = {}
        self.fieldOwnedCount = 0
        self.husbandryOwnedCount = 0
        self.scanWaited = 0
        self._farmWaitLogged = false
    end

    -- Einmalig nach Ablauf des Timeouts informieren, dann ruhig weiterpollen.
    self.scanWaited = (self.scanWaited or 0) + (elapsed or 0)
    if not self._farmWaitLogged and self.scanWaited > MyTodos.SCAN_TIMEOUT_MS then
        self._farmWaitLogged = true
        Logging.info("[MyTodos] still no local farmId after %.0fs - will keep checking every %.0fs (normal until you're assigned to a farm)",
            self.scanWaited / 1000, MyTodos.FARM_POLL_INTERVAL_MS / 1000)
    end
end

function MyTodos:scanFields(verbose)
    -- PF-Detection bei jedem Scan, weil PF-Sprayer in der Welt erst
    -- spaeter spawnen koennten (z.B. Spieler kauft Streuer nach
    -- Spielstart -> Status wechselt von "loaded-inactive" zu "active").
    self.precisionFarming = self:detectPrecisionFarming()

    local owned = self:collectOwnedFields(self.farmId)
    self.fieldOwnedCount = #owned

    -- Aggregat erzwingen, damit fieldState nicht hinterherhinkt.
    for _, entry in ipairs(owned) do
        if type(entry.field.updateState) == "function" then
            pcall(entry.field.updateState, entry.field)
        end
    end

    -- History updaten + Tasks ableiten; passive Felder rausfiltern.
    -- Vom Spieler manuell ignorierte Felder werden komplett uebersprungen
    -- (siehe Settings -> Ignorierte Felder, oder mtIgnore-Console).
    local tasks = {}
    for _, entry in ipairs(owned) do
        if not self:isFieldIgnored(entry.fieldId) then
            local fs = entry.field.fieldState
            if fs ~= nil then
                self:updateFieldHistory(entry.fieldId, fs)
            end
            local task, primary, parallel, actionable =
                self:deriveFieldTask(entry.field, entry.fieldId)
            if task ~= nil then
                local iconFile = nil
                if fs ~= nil then
                    iconFile = self:_fruitIconFile(fs.fruitTypeIndex)
                end
                table.insert(tasks, { fieldId = entry.fieldId, task = task,
                    primary = primary or task, parallel = parallel or {},
                    actionable = actionable == true,
                    iconFile = iconFile })
            end
        end
    end
    -- Paddies/Perennials (Reis/Trauben/Oliven auf eigenen Grundstuecken OHNE
    -- Field-Objekt -- siehe MyTodosPaddies.lua). Gleiches Eintrags-Schema, wird
    -- hier vor dem Sortieren gemerged, damit sie inline mit den Feldern nach
    -- Nummer einsortiert werden. paddyOwnedCount fliesst in die "owned"-Zaehlung
    -- ein, damit die HUD-"keine eigenen Felder"-Meldung korrekt bleibt.
    local paddyTasks = self:scanPaddies(verbose)
    for _, pt in ipairs(paddyTasks) do
        table.insert(tasks, pt)
    end
    self.fieldOwnedCount = self.fieldOwnedCount + (self.paddyOwnedCount or 0)

    -- Sortierung: zwei Gruppen nach Dringlichkeit. Felder mit echter
    -- Hauptaufgabe (Ernten/Siliergut/Verwelkt/Prep -> actionable=true) zuerst,
    -- danach die nur-wachsenden Felder (die nur wegen Nebenaufgaben wie Duengen/
    -- Unkraut sichtbar sind). Innerhalb jeder Gruppe nach Feldnummer.
    table.sort(tasks, function(a, b)
        if a.actionable ~= b.actionable then
            return a.actionable
        end
        local an = tonumber(a.fieldId) or math.huge
        local bn = tonumber(b.fieldId) or math.huge
        if an ~= bn then return an < bn end
        return tostring(a.fieldId) < tostring(b.fieldId)
    end)
    self.fieldTasks = tasks

    if verbose then
        Logging.info("[MyTodos] save key for ignore list: %s",
            tostring(self:getSaveKey()))
        local pf = self.precisionFarming
        local pfMsg = pf or "no"
        if pf == "loaded-inactive" then
            pfMsg = "loaded-inactive (PF-Mod registriert, aber kein Sprayer mit PF-Spec gefunden -- Verhalten wie Vanilla)"
        elseif pf == "active" then
            pfMsg = "active (pHMap-Ref via Sprayer-Spec gefunden)"
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
    registerSilent("MYTODOS_TOGGLE_OVERVIEW", MyTodos.onActionToggleOverview)
end

function MyTodos:onActionToggleSettings()
    if g_gui == nil then return end
    -- Wenn das Menue gerade aktiv ist -> zumachen, sonst auf-event publishen.
    -- Subscriber in MyTodosSettingsMenu ruft dann g_gui:showGui auf.
    if g_gui.currentGuiName == "MyTodosSettingsMenu" then
        g_gui:showGui("")
        return
    end
    if g_gui.currentGui ~= nil then
        -- Ein anderes Menue ist offen (z.B. ESC, Shop) -- Alt+M dort ignorieren
        -- damit man sich keinen Stack baut.
        return
    end
    if g_messageCenter ~= nil and MessageType.GUI_MYTODOS_OPEN ~= nil then
        g_messageCenter:publishDelayed(MessageType.GUI_MYTODOS_OPEN)
    end
end

function MyTodos:onActionToggleHud()
    self:setSetting("hudVisible", not (self.settings.hudVisible == true))
end

-- Komplettuebersicht (alle Felder/Tiere ohne Zeilen-Caps) als Dialog
-- oeffnen. Waehrend der Dialog offen ist gehoert der Input-Context der
-- GUI -- diese Action feuert dann normalerweise nicht; geschlossen wird
-- regulaer per ESC / Controller-B (MENU_BACK am Back-Button). Der
-- Toggle-Zweig hier ist nur Absicherung falls die Action doch durchkommt.
function MyTodos:onActionToggleOverview()
    if g_gui == nil then return end
    if g_gui.currentGuiName == "MyTodosOverviewDialog" then
        if type(g_gui.closeDialogByName) == "function" then
            g_gui:closeDialogByName("MyTodosOverviewDialog")
        end
        return
    end
    if g_gui.currentGui ~= nil then
        -- Ein anderes Menue/Dialog ist offen -- nicht drueberstapeln.
        return
    end
    g_gui:showDialog("MyTodosOverviewDialog")
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

-- Ignorierte Felder ------------------------------------------------
--
-- Pro (Savegame, FarmId)-Paar eine eigene Liste. Saves nebeneinander
-- bleiben sauber getrennt; in MP hat jeder Client (= jede FarmId) seine
-- eigene Sicht. Persistiert in MyTodos.xml als flache <ignored>-Liste,
-- jeder Eintrag traegt save/farmId/id auf einmal.

function MyTodos:_getSavegameName()
    local mi = g_currentMission and g_currentMission.missionInfo
    if mi == nil then return "default" end
    -- savegameIndex ist die Save-Slot-Nummer und damit eindeutig pro
    -- Save -- bevorzugt. savegameName ist user-renamable und kann leer
    -- bzw. ueber zwei Saves identisch sein, daher unzuverlaessig als
    -- Schluessel. savegameDirectory als zweite Sicherung.
    if type(mi.savegameIndex) == "number" then
        return "savegame" .. tostring(mi.savegameIndex)
    end
    if type(mi.savegameDirectory) == "string" and mi.savegameDirectory ~= "" then
        local base = mi.savegameDirectory:match("([^/\\]+)$")
        if base ~= nil then return base end
    end
    if type(mi.savegameName) == "string" and mi.savegameName ~= "" then
        return mi.savegameName
    end
    return "default"
end

function MyTodos:getSaveKey()
    if self.saveKey ~= nil then return self.saveKey end
    if self.farmId == nil then return nil end
    self.saveKey = self:_getSavegameName() .. "|" .. tostring(self.farmId)
    return self.saveKey
end

-- Bucket fuer aktuelle (Savegame, FarmId)-Kombination; legt leeren Bucket
-- an wenn noch keiner existiert. nil bis farmId bekannt ist.
function MyTodos:_currentIgnoreBucket()
    local key = self:getSaveKey()
    if key == nil then return nil end
    if self.ignoredFieldsAllSaves[key] == nil then
        self.ignoredFieldsAllSaves[key] = {}
    end
    return self.ignoredFieldsAllSaves[key]
end

function MyTodos:isFieldIgnored(fieldId)
    local b = self:_currentIgnoreBucket()
    if b == nil then return false end
    return b[fieldId] == true
end

function MyTodos:setFieldIgnored(fieldId, ignored)
    local b = self:_currentIgnoreBucket()
    if b == nil then return false end
    b[fieldId] = ignored and true or nil
    self:saveSettings()
    -- Sofortiger silent rescan damit das HUD nicht erst beim naechsten
    -- 5s-Tick aktualisiert. Auf Server kein farmId-Reset noetig.
    if self.farmId ~= nil then
        self:scanFields(false)
    end
    return true
end

function MyTodos:toggleFieldIgnored(fieldId)
    return self:setFieldIgnored(fieldId, not self:isFieldIgnored(fieldId))
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

-- True wenn irgendein Menue/Dialog/Pause-Screen offen ist und wir dem HUD
-- den Weg frei machen sollten. Drei Layer:
--   1. g_gui.currentGui != nil -- ein voller Screen (showGui-Style) ist
--      aktiv, z.B. unser eigenes Settings-Menue oder das ESC-Pausemenue.
--   2. Giants' eigene "ist ein Dialog ueber den Screen gelegt"-API, falls
--      verfuegbar -- catches showDialog-Style (z.B. FarmlandOverview).
--   3. Fallback: Mauszeiger sichtbar = mit hoher Wahrscheinlichkeit ist
--      irgendein interaktives Menue offen. In normalem Gameplay (ohne
--      Menue) versteckt FS25 den Cursor.
function MyTodos:_isAnyGuiOpen()
    if g_gui ~= nil then
        if g_gui.currentGui ~= nil then return true end
        if type(g_gui.getIsDialogVisible) == "function" then
            local ok, visible = pcall(g_gui.getIsDialogVisible, g_gui)
            if ok and visible then return true end
        end
    end
    if g_inputBinding ~= nil
            and type(g_inputBinding.getShowMouseCursor) == "function" then
        local ok, shown = pcall(g_inputBinding.getShowMouseCursor, g_inputBinding)
        if ok and shown then return true end
    end
    return false
end

function MyTodos:draw()
    if not self.isClient then return end
    if self:_isAnyGuiOpen() then return end
    if self.fieldTasks == nil then return end
    if self.settings.hudVisible == false then return end

    self:drawHud()
end

function MyTodos:drawHud()
    -- Anker + Schriftgroesse beide aus Giants' InputHelp-Geometrie.
    local anchorX, anchorY, size = self:getHudMetrics()
    self:_drawTaskPanel({
        anchorX = anchorX,
        anchorY = anchorY,
        size = size,
        title = self:t("myTodos_hud_title"),
        showHeader = self.settings.hudShowHeader ~= false,
        maxFieldLines = self:_lineBudget("maxFieldLines", MyTodos.HUD_MAX_FIELD_LINES),
        maxHusbLines = self:_lineBudget("maxHusbLines", MyTodos.HUD_MAX_HUSB_LINES),
    })
end

-- Zeilen-Budget einer HUD-Sektion aus den Settings, geclampt auf 1..30.
function MyTodos:_lineBudget(key, fallback)
    local v = tonumber(self.settings and self.settings[key]) or fallback
    return math.max(1, math.min(30, math.floor(v)))
end

-- HUD-Panel-Renderer (am InputHelp-Anker). opts: anchorX, anchorY, size,
-- title, showHeader, maxFieldLines, maxHusbLines.
function MyTodos:_drawTaskPanel(opts)
    local size = opts.size
    local titleSize = size * MyTodos.HUD_TITLE_SCALE
    local lineH = size * MyTodos.HUD_LINE_SPACING
    local padX = MyTodos.HUD_PAD_X
    local padY = MyTodos.HUD_PAD_Y
    -- Icon links neben Feld-/Tier-Zeilen: leicht groesser als die
    -- Texthoehe, vertikal zentriert. iconSize ist die HOEHE; die Breite
    -- (iconW) muss per Screen-Aspect korrigiert werden, sonst wird das
    -- Icon in die Breite gezogen (HUD-Koords 0..1 sind nicht quadratisch).
    local iconSize = size * 1.2
    local iconGap = size * 0.35
    local screenAspect = 16 / 9
    if g_screenWidth ~= nil and g_screenHeight ~= nil
            and g_screenHeight > 0 then
        screenAspect = g_screenWidth / g_screenHeight
    end
    local iconW = iconSize / screenAspect

    local showHeader = opts.showHeader ~= false
    local titleText = opts.title
    local maxW = 0
    if showHeader then
        setTextBold(true)
        maxW = getTextWidth(titleSize, titleText)
        setTextBold(false)
    end

    local fTasks = self.fieldTasks or {}
    local hTasks = self.husbandryTasks or {}
    local hasField = #fTasks > 0
    local hasHusb = #hTasks > 0
    local fieldOwned = self.fieldOwnedCount or 0
    local husbOwned = self.husbandryOwnedCount or 0
    local showSubHeaders = hasField and hasHusb

    local rows = {}
    local function addRow(text, color, isHeader, iconFile)
        table.insert(rows, { text = text, color = color, isHeader = isHeader,
            iconFile = iconFile })
        local w = getTextWidth(size, text)
        if iconFile ~= nil then w = w + iconW + iconGap end
        maxW = math.max(maxW, w)
    end

    -- Schreibt bis maxLines Tasks aus `tasks` (formatiert via fmt) ins
    -- rows-Array. Wenn ueberlaeuft, eine "(+N weitere)"-Zeile am Ende.
    local emitSection = function(tasks, maxLines, fmt, iconFn)
        local shown = 0
        for _, t in ipairs(tasks) do
            if shown >= maxLines then
                addRow(self:t("myTodos_hud_more", #tasks - shown),
                    MyTodos.HUD_DIM_COLOR, false)
                return
            end
            addRow(fmt(t), MyTodos.HUD_TEXT_COLOR, false,
                iconFn ~= nil and iconFn(t) or nil)
            shown = shown + 1
        end
    end

    if not hasField and not hasHusb then
        local s
        if fieldOwned == 0 and husbOwned == 0 then
            s = self:t("myTodos_hud_no_owned")
        else
            s = self:t("myTodos_hud_nothing_to_do")
        end
        addRow(s, MyTodos.HUD_DIM_COLOR, false)
    else
        if hasField then
            if showSubHeaders then
                addRow(string.upper(self:t("myTodos_section_fields")),
                    MyTodos.HUD_DIM_COLOR, true)
            end
            emitSection(fTasks, opts.maxFieldLines, function(t)
                return self:t("myTodos_hud_field_row", tostring(t.fieldId), t.task)
            end, function(t) return t.iconFile end)
        end

        if hasHusb then
            if showSubHeaders then
                addRow(string.upper(self:t("myTodos_section_animals")),
                    MyTodos.HUD_DIM_COLOR, true)
            end
            emitSection(hTasks, opts.maxHusbLines, function(t)
                return t.task
            end, function(t) return t.iconFile end)
        end
    end

    local panelW = math.max(MyTodos.HUD_MIN_WIDTH, maxW + 2 * padX)
    local headerH = showHeader and (titleSize + 2 * padY) or 0
    local bodyH = padY + #rows * lineH + padY
    local totalH = headerH + bodyH

    local panelLeft = opts.anchorX
    local panelTop = opts.anchorY
    local panelBottom = panelTop - totalH

    if showHeader then
        self:drawPanel(panelLeft, panelTop - headerH, panelW, headerH, MyTodos.HUD_HEADER_COLOR)
    end
    self:drawPanel(panelLeft, panelBottom, panelW, bodyH, MyTodos.HUD_BG_COLOR)

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)

    local textLeft = panelLeft + padX

    if showHeader then
        setTextBold(true)
        setTextColor(MyTodos.HUD_HEADER_TEXT[1], MyTodos.HUD_HEADER_TEXT[2],
                     MyTodos.HUD_HEADER_TEXT[3], MyTodos.HUD_HEADER_TEXT[4])
        renderText(textLeft, panelTop - padY, titleSize, titleText)
        setTextBold(false)
    end

    local y = panelTop - headerH - padY
    for _, row in ipairs(rows) do
        if row.isHeader then
            -- duenne Trennlinie ueber dem Header, setzt die Sektion
            -- sichtbar von den Aufgaben darueber ab.
            local sepH = size * 0.12
            self:drawPanel(textLeft, y + size * 0.2 - sepH * 0.5,
                panelW - 2 * padX, sepH, MyTodos.HUD_SEP_COLOR)
        end
        local c = row.color
        setTextColor(c[1], c[2], c[3], c[4])
        if row.isHeader then setTextBold(true) end
        local rowTextLeft = textLeft
        if row.iconFile ~= nil then
            local ov = self:_getIconOverlay(row.iconFile)
            if ov ~= nil then
                setOverlayColor(ov, 1, 1, 1, 1)
                renderOverlay(ov, textLeft, y - size * 0.5 - iconSize * 0.5,
                    iconW, iconSize)
            end
            rowTextLeft = textLeft + iconW + iconGap
        end
        renderText(rowTextLeft, y, size, row.text)
        if row.isHeader then setTextBold(false) end
        y = y - lineH
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
    setTextColor(1, 1, 1, 1)
end

-- Icon-Helfer (HUD-Frucht-Icons) -------------------------------------

-- Aufloesung fruitTypeIndex (am Feld) -> Icon-Pfad des zugehoerigen
-- fillTypes. Kette per mtProbeIcons bestaetigt:
-- getFillTypeIndexByFruitTypeIndex -> fillType.hudOverlayFilename.
function MyTodos:_fruitIconFile(fruitTypeIndex)
    if type(fruitTypeIndex) ~= "number" or fruitTypeIndex <= 0 then
        return nil
    end
    if g_fruitTypeManager == nil or g_fillTypeManager == nil then
        return nil
    end
    local ok, fillIdx = pcall(g_fruitTypeManager.getFillTypeIndexByFruitTypeIndex,
        g_fruitTypeManager, fruitTypeIndex)
    if not ok or type(fillIdx) ~= "number" then return nil end
    local ft = g_fillTypeManager:getFillTypeByIndex(fillIdx)
    if ft == nil or type(ft.hudOverlayFilename) ~= "string"
            or ft.hudOverlayFilename == "" then
        return nil
    end
    return ft.hudOverlayFilename
end

-- Aufloesung einer Tier-Husbandry -> Icon-Pfad. Jeder Animal-SubType
-- traegt einen fillTypeIndex; dessen fillType hat das hudOverlayFilename
-- (z.B. hud_fill_cow.png). Wir nehmen den ersten SubType der zum
-- animalType der Husbandry passt -- alle SubTypes einer Tierart teilen
-- sich dasselbe Icon. Kette per mtProbeIcons bestaetigt.
function MyTodos:_animalIconFile(p)
    if p == nil then return nil end
    local anim = p.spec_husbandryAnimals
    local at = anim ~= nil and anim.animalType or nil
    if at == nil or at.typeIndex == nil then return nil end
    if g_currentMission == nil or g_currentMission.animalSystem == nil
            or g_fillTypeManager == nil then
        return nil
    end
    local subTypes = g_currentMission.animalSystem.subTypes
    if type(subTypes) ~= "table" then return nil end
    for _, st in ipairs(subTypes) do
        if type(st) == "table" and st.typeIndex == at.typeIndex
                and type(st.fillTypeIndex) == "number" then
            local ft = g_fillTypeManager:getFillTypeByIndex(st.fillTypeIndex)
            if ft ~= nil and type(ft.hudOverlayFilename) == "string"
                    and ft.hudOverlayFilename ~= "" then
                return ft.hudOverlayFilename
            end
        end
    end
    return nil
end

-- Cached Overlay-Handle fuer einen Icon-Pfad. createImageOverlay nur
-- einmal pro Datei (Overlays leben die Session). false = Pfad kaputt.
function MyTodos:_getIconOverlay(filename)
    if type(filename) ~= "string" then return nil end
    if self._iconOverlayCache == nil then self._iconOverlayCache = {} end
    local cached = self._iconOverlayCache[filename]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local ok, ov = pcall(createImageOverlay, filename)
    if ok and ov ~= nil and ov ~= 0 then
        self._iconOverlayCache[filename] = ov
        return ov
    end
    self._iconOverlayCache[filename] = false
    return nil
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
        elseif typ == "percent" or typ == "count" then
            local v = getXMLInt(xmlFile, p)
            if v ~= nil then self.settings[def.key] = v end
        elseif typ == "select" then
            local v = getXMLFloat(xmlFile, p)
            if v ~= nil then self.settings[def.key] = v end
        end
    end

    -- Ignorierte Felder: flache <ignored save="..." farmId="..." id="..."/>
    -- Liste, gruppiert nach (save, farmId) in self.ignoredFieldsAllSaves.
    -- Eintraege fuer Saves die der Spieler aktuell nicht spielt bleiben
    -- erhalten -- sind nur "schlafend" und werden bei naechstem saveSettings
    -- mit zurueckgeschrieben.
    local count = 0
    local idx = 0
    while true do
        local base = string.format("myTodos.ignored(%d)", idx)
        local save = getXMLString(xmlFile, base .. "#save")
        if save == nil then break end
        local farmIdStr = getXMLString(xmlFile, base .. "#farmId")
        local idStr = getXMLString(xmlFile, base .. "#id")
        if farmIdStr ~= nil and idStr ~= nil then
            local key = save .. "|" .. farmIdStr
            if self.ignoredFieldsAllSaves[key] == nil then
                self.ignoredFieldsAllSaves[key] = {}
            end
            local fid = tonumber(idStr) or idStr
            self.ignoredFieldsAllSaves[key][fid] = true
            count = count + 1
        end
        idx = idx + 1
    end

    delete(xmlFile)
    Logging.info("[MyTodos] loaded settings: hudVisible=%s, %d ignored-field entries",
        tostring(self.settings.hudVisible), count)
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
        elseif typ == "percent" or typ == "count" then
            setXMLInt(xmlFile, p,
                math.floor(tonumber(self.settings[def.key]) or def.default or 0))
        elseif typ == "select" then
            setXMLFloat(xmlFile, p,
                tonumber(self.settings[def.key]) or def.default or 0)
        end
    end

    -- Ignorierte Felder: alle Saves zurueckschreiben (auch die wo wir
    -- gerade nicht drinhocken), damit der Spieler beim Wechsel zwischen
    -- Saves seine Liste nicht verliert. Key-Format: "<savename>|<farmId>".
    local outIdx = 0
    for saveKey, bucket in pairs(self.ignoredFieldsAllSaves) do
        local sep = saveKey:find("|", 1, true)
        if sep ~= nil then
            local saveName = saveKey:sub(1, sep - 1)
            local farmIdStr = saveKey:sub(sep + 1)
            for fieldId, _ in pairs(bucket) do
                local base = string.format("myTodos.ignored(%d)", outIdx)
                setXMLString(xmlFile, base .. "#save", saveName)
                setXMLString(xmlFile, base .. "#farmId", farmIdStr)
                setXMLString(xmlFile, base .. "#id", tostring(fieldId))
                outIdx = outIdx + 1
            end
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
