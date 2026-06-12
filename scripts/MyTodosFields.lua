--
-- MyTodos / Fields
--
-- Field-Discovery, Task-Derivation und Density-Map-Sampler (Windrow,
-- Stones, Weed). Alles was mit eigenen Aeckern zu tun hat. Erweitert die
-- in MyTodos.lua angelegte MyTodos-Tabelle.
--

-- Sampler-Schwellen ------------------------------------------------

-- labelKey: l10n-Key, wird in initWindrowSampler aufgeloest (einmalig zur
-- Sampler-Init-Zeit). Spielsprache wechselt im laufenden Spiel nicht.
-- ALFALFA_WINDROW / DRYALFALFA_WINDROW sind keine Vanilla-fillTypes — Luzerne
-- kommt nur ueber Crop-/Map-Mods rein. Namen die auf der aktuellen Map nicht
-- existieren werden in initWindrowSampler still uebersprungen (FillType[name]
-- == nil), darum ist es ungefaehrlich sie generell mitzufuehren. Falls eine
-- Map abweichende Namen nutzt: mtProbeWindrow listet alle schwad-faehigen
-- fillTypes mit ihrem Namen.
MyTodos.WINDROW_TYPES = {
    { name = "STRAW",             labelKey = "myTodos_windrow_straw" },
    { name = "GRASS_WINDROW",     labelKey = "myTodos_windrow_grass" },
    { name = "DRYGRASS_WINDROW",  labelKey = "myTodos_windrow_hay" },
    { name = "ALFALFA_WINDROW",   labelKey = "myTodos_windrow_alfalfa" },
    { name = "DRYALFALFA_WINDROW", labelKey = "myTodos_windrow_alfalfa_hay" },
}

-- Mindestens so viele Pixel muessen ein bestimmten Schwadtyp haben, sonst
-- wird's als vernachlaessigbarer Rest behandelt. Die *_MIN_FRACTION- und
-- WEED_TOTAL_MIN_FACTOR-Werte hier sind nur noch DEFAULTS -- der Spieler
-- kann sie via Settings (Alt+M, Sektion "Felder": windrow/stones/
-- weedThreshold) uebersteuern; die Pixel-Floors bleiben immer aktiv.
MyTodos.WINDROW_MIN_PIXELS = 50
MyTodos.WINDROW_MIN_FRACTION = 0.005  -- 0.5% der Feldflaeche

-- Selbe Logik fuer Steine. fs.stoneLevel ist nutzlos -> direkt aus
-- g_currentMission.stoneSystem.densityMap sampeln.
MyTodos.STONE_MIN_PIXELS = 50
MyTodos.STONE_MIN_FRACTION = 0.005

-- Selbe Logik fuer Unkraut. fs.weedState/fs.weedFactor sind Aggregate
-- die haengen koennen oder ganz blind sein. Direkt aus
-- g_currentMission.weedSystem.densityMap sampeln. weedSystem.factors ist
-- ein Lookup density-map-Wert -> weedFactor und matcht 1:1 unsere
-- empirische Tabelle: 3=0.5, 4=0.75, 5=1.0, 6=0.5, 8=0.5, 9=0.75.
--
-- Zwei Schwellen, beide muessen erfuellt sein:
-- 1. Per-state >= 1% der Feldflaeche (oder 50 Pixel) damit der state
--    ueberhaupt als "vorhanden" zaehlt
-- 2. Gewichteter Gesamt-Faktor >= 2% damit Label rausgegeben wird
-- Damit verschwinden nur noch Mikro-Befaelle (<2% gewichtete Abdeckung). Von
-- urspruenglich 5% auf 2% gesenkt: Feld 53 (Witcombe, RYE) hatte 2,7%
-- Grossunkraut (3941/145997 Px, Faktor 1.0) und fiel sichtbar verunkrautet
-- durchs 5%-Gate -- per mtProbeWeed-Histogramm diagnostiziert.
MyTodos.WEED_MIN_PIXELS = 50
MyTodos.WEED_MIN_FRACTION = 0.01
MyTodos.WEED_TOTAL_MIN_FACTOR = 0.02

-- Precision-Farming "Kalk"-Schwellen. Mit PF ersetzen wir den
-- Vanilla-Kalken-Task. Target-pH haengt vom DOMINANTEN BODENTYP des
-- Feldes ab (NICHT von der Frucht -- die Frucht beeinflusst nur den
-- Yield via yieldCurve, nicht den optimalen pH).
--
-- Target-Werte kommen aus `pHMap.valueTransformations`:
--   Lehmiger Sand   -> internal 13 -> pH 6.00
--   Sandiger Lehm   -> internal 17 -> pH 6.50
--   Lehm            -> internal 19 -> pH 6.75
--   Schluffiger Ton -> internal 21 -> pH 7.00
-- plus `regularOffset` als Tolerenzbereich (1.5 internal = 0.19 pH bei
-- Sand/Sandiger Lehm; 0.5 internal = 0.06 pH bei Lehm/Schluffiger Ton).
-- Trigger fuer Task: aktueller avg-pH < (target - regularOffset).
--
-- Wenn die Differenz groesser als PH_HEAVY_GAP_STATES Internal-States
-- ist (-> ca. 80% Yield laut yieldCurve), schaerfen wir das Label auf
-- "stark sauer".
MyTodos.PH_HEAVY_GAP_STATES = 4
-- Anzahl Bodenarten (Stand FS25 2026: 4). soilMap.soilTypes hat genau
-- diese vielen Eintraege, Indizes 1..N.
MyTodos.SOIL_NUM_TYPES = 4
-- Mindest-Pixel + -Anteil damit eine Bodenart fuer Per-Soil-Tasks zaehlt.
-- 10% Mindestanteil filtert Rand-Patches raus (typischerweise 5-7% kleine
-- Eckbereiche, die der Spieler beim Spritzen sowieso nicht gezielt
-- erreicht). Empirisch noetig: Feld 6 mit Schluffiger Ton 5% (228 px)
-- triggerte Task wegen 15 kg/ha unter Target, obwohl Patch praktisch
-- unanfahrbar ist und alle dominanteren Boeden im Soll waren.
MyTodos.SOIL_MIN_PIXELS = 50
MyTodos.SOIL_MIN_FRACTION = 0.10

-- Precision-Farming "N"-Schwellen. Analog zu pH: Target haengt von
-- (Frucht, Bodenart) ab, NICHT vom Wachstumsstadium. Lookup ueber
-- nitrogenMap.fruitTypeIndexToFruitRequirement[fruitIdx].bySoilType[soilIdx].targetLevel.
--
-- Trigger fuer "N"-Task: primaer `entry.reduction` aus bySoilType (PF's
-- eigener "Auto-Apply re-fires hier"-Schwellwert; ueber dieser Schwelle
-- zeigt PF "grün" und appliziert nicht nach). Wenn `reduction` im
-- Eintrag fehlt, fallen wir auf `target - N_GAP_STATES` zurueck.
--
-- yieldCurve (nitrogenMap.yieldCurve, time = avgInternal - target):
--   time=0    -> 100% yield
--   time=-2   ->  95%
--   time=-4   ->  90%   <- Fallback-Trigger ohne reduction
--   time=-8   ->  82%
--   time=-12  ->  70%
-- 1 internal state = 5 kg/ha.
--
-- N_HEAVY_GAP_STATES: zusaetzlicher Abstand UNTER dem Trigger fuer
-- "N-Mangel"-Suffix. Typisch reduction = target-5, also Suffix bei
-- avg <= target-13 (= ca. 70% Yield).
MyTodos.N_GAP_STATES = 4
MyTodos.N_HEAVY_GAP_STATES = 8

-- Discovery --------------------------------------------------------

function MyTodos:getLocalFarmId()
    if g_currentMission == nil then return nil end
    if g_currentMission.getFarmId ~= nil then
        local id = g_currentMission:getFarmId()
        if id ~= nil then return id end
    end
    if g_currentMission.player ~= nil and g_currentMission.player.farmId ~= nil then
        return g_currentMission.player.farmId
    end
    return nil
end

function MyTodos:collectOwnedFields(farmId)
    local result = {}
    if g_fieldManager == nil or g_farmlandManager == nil then
        return result
    end

    for key, field in pairs(g_fieldManager:getFields()) do
        local farmlandId = nil
        if field.farmland ~= nil then
            farmlandId = field.farmland.id
        end
        if farmlandId ~= nil then
            local owner = g_farmlandManager:getFarmlandOwner(farmlandId)
            if owner == farmId then
                -- User-facing Feldnummer steht auf farmland.name (typisch
                -- ein Zahl-String wie "3", kann auf modded Maps auch ein
                -- echter Name sein). Bestaetigt via FS25_FarmlandOverview.
                -- Fallback auf farmland.id und Tabellen-Key.
                local fieldId
                local fname = field.farmland and field.farmland.name
                if type(fname) == "string" and fname ~= "" then
                    fieldId = tonumber(fname) or fname
                end
                if fieldId == nil then fieldId = farmlandId end
                if fieldId == nil then fieldId = key end
                table.insert(result, {
                    fieldId = fieldId,
                    farmlandId = farmlandId,
                    field = field,
                })
            end
        end
    end
    return result
end

-- Liefert einen der drei Zustaende:
--   "active"           -> PF-Sprayer in der Welt gefunden, Maps via Spec
--                         erreichbar. Volles PF-Behavior.
--   "loaded-inactive"  -> PF-Mod ist registriert aber kein Sprayer mit
--                         PF-Spec gefunden. Entweder noch keinen gekauft,
--                         oder Map hat keinen PF-Support.
--   nil                -> PF-Mod gar nicht installiert.
-- In FS25 gibt es kein verlaessliches Global `g_precisionFarming` mehr --
-- siehe `findPfPHMap()`.
function MyTodos:detectPrecisionFarming()
    if self:isPfActive() then
        return "active"
    end
    if g_modIsLoaded ~= nil then
        local candidates = {
            "FS25_precisionFarming",
            "FS25_PrecisionFarming",
            "FS22_precisionFarming",
            "pdlc_precisionFarmingPack",
        }
        for _, name in ipairs(candidates) do
            if g_modIsLoaded[name] then
                return "loaded-inactive"
            end
        end
    end
    return nil
end

-- Naming -----------------------------------------------------------

function MyTodos:fruitName(fruit)
    if fruit == nil then return "?" end
    -- Versuche lokalisierten Namen, sonst fallback auf .name (lowercase).
    local raw = fruit.name or "?"
    local localized = nil
    if g_i18n ~= nil and g_i18n.hasText ~= nil then
        local key = "fillType_" .. string.lower(raw)
        if g_i18n:hasText(key) then
            localized = g_i18n:getText(key)
        end
    end
    local s = localized or raw
    if s == raw then
        s = string.lower(s)
        s = s:sub(1, 1):upper() .. s:sub(2)
    end
    return s
end

-- Polygon-Helper (von allen 3 Samplern genutzt) --------------------

function MyTodos:applyFieldPolygon(mod, field)
    if mod == nil then return end
    if type(mod.clearPolygonPoints) == "function" then
        mod:clearPolygonPoints()
    end
    for _, nodeId in ipairs(field.polygonPoints) do
        local x, _, z = getWorldTranslation(nodeId)
        mod:addPolygonPointWorldCoords(x, z)
    end
end

-- Prozent-Setting -> Bruchteil [0..1]. defaultPct greift solange das
-- Setting fehlt oder kein numerischer Wert ist. Genutzt von den Sampler-
-- Schwellen (windrow/stones/weedThreshold, Settings-Sektion "Felder").
function MyTodos:_settingFraction(key, defaultPct)
    local v = self.settings and tonumber(self.settings[key])
    if v == nil then v = defaultPct end
    return v / 100
end

-- Windrow-Sampler --------------------------------------------------

function MyTodos:initWindrowSampler()
    if self.windrowSamplerReady then return self.windrowMod ~= nil end
    self.windrowSamplerReady = true
    if DensityMapHeightUtil == nil
            or DensityMapHeightUtil.terrainDetailHeightId == nil
            or DensityMapModifier == nil
            or DensityMapFilter == nil
            or g_currentMission == nil
            or g_currentMission.terrainRootNode == nil
            or g_fillTypeManager == nil
            or FillType == nil then
        Logging.info("[MyTodos] windrow sampler unavailable (missing globals)")
        return false
    end

    local terrain = g_currentMission.terrainRootNode
    local mapId = DensityMapHeightUtil.terrainDetailHeightId

    -- Modifier auf Type-Channels (welche fillType liegt da)
    local ok, mod = pcall(DensityMapModifier.new, mapId,
        DensityMapHeightUtil.typeFirstChannel,
        DensityMapHeightUtil.typeNumChannels, terrain)
    if not ok or mod == nil then
        Logging.warning("[MyTodos] DensityMapModifier.new (type) failed: %s", tostring(mod))
        return false
    end
    self.windrowMod = mod

    -- Modifier auf Height-Channels (wieviel liegt wirklich)
    local okH, hMod = pcall(DensityMapModifier.new, mapId,
        DensityMapHeightUtil.heightFirstChannel,
        DensityMapHeightUtil.heightNumChannels, terrain)
    if okH and hMod ~= nil then
        self.windrowHeightMod = hMod
        self.windrowHeightFilter = DensityMapFilter.new(hMod)
        self.windrowHeightFilter:setValueCompareParams(DensityValueCompareType.GREATER, 0)
    end

    self.windrowFilters = {}
    for _, def in ipairs(MyTodos.WINDROW_TYPES) do
        local fillIdx = FillType[def.name]
        if fillIdx ~= nil then
            local ft = g_fillTypeManager.fillTypes[fillIdx]
            if ft ~= nil and ft.textureArrayIndex ~= nil then
                local filter = DensityMapFilter.new(mod)
                filter:setValueCompareParams(DensityValueCompareType.EQUAL, ft.textureArrayIndex)
                table.insert(self.windrowFilters, {
                    label = self:t(def.labelKey),
                    filter = filter,
                    typeIdx = ft.textureArrayIndex,
                })
                Logging.info("[MyTodos] windrow filter: %s -> internal type %d",
                    def.name, ft.textureArrayIndex)
            end
        end
    end

    return true
end

function MyTodos:sampleWindrowsForField(field)
    if not self:initWindrowSampler() then return {} end
    if type(field.polygonPoints) ~= "table" or #field.polygonPoints == 0 then
        return {}
    end

    self:applyFieldPolygon(self.windrowMod, field)
    self:applyFieldPolygon(self.windrowHeightMod, field)

    -- Schritt 1: liegt ueberhaupt was auf dem Feld? (height > 0)
    local hArea, hTotalArea = 0, 0
    if self.windrowHeightMod ~= nil and self.windrowHeightFilter ~= nil then
        local hOk, _, area, totalArea = pcall(self.windrowHeightMod.executeGet,
            self.windrowHeightMod, self.windrowHeightFilter)
        if not hOk then return {} end
        hArea = area or 0
        hTotalArea = totalArea or 0
    end

    local threshold = math.max(
        MyTodos.WINDROW_MIN_PIXELS,
        math.floor(hTotalArea * self:_settingFraction("windrowThreshold",
            MyTodos.WINDROW_MIN_FRACTION * 100))
    )
    if hArea < threshold then
        return {}
    end

    -- Schritt 2: welche Type(n) sind ueber Threshold? Type- UND Height-
    -- Filter zusammen (executeGet AND-verknuepft mehrere Filter): nach dem
    -- Aufnehmen bleiben Type-Restpixel mit Height 0 zurueck, die sonst als
    -- false positive durchkommen sobald irgendein anderer Schwad das
    -- Height-Gate in Schritt 1 passiert.
    local labels = {}
    for _, w in ipairs(self.windrowFilters) do
        local ok, _, area, _ = pcall(self.windrowMod.executeGet, self.windrowMod,
            w.filter, self.windrowHeightFilter)
        if ok and (area or 0) >= threshold then
            table.insert(labels, w.label)
        end
    end
    return labels
end

-- Stein-Sampler ----------------------------------------------------

function MyTodos:initStoneSampler()
    if self.stoneSamplerReady then return self.stoneMod ~= nil end
    self.stoneSamplerReady = true

    local ss = g_currentMission and g_currentMission.stoneSystem
    if ss == nil or ss.densityMap == nil
            or DensityMapModifier == nil or DensityMapFilter == nil
            or g_currentMission.terrainRootNode == nil then
        Logging.info("[MyTodos] stone sampler unavailable")
        return false
    end

    local ok, mod = pcall(DensityMapModifier.new, ss.densityMap,
        ss.firstChannel or 0, ss.numChannels or 3,
        g_currentMission.terrainRootNode)
    if not ok or mod == nil then
        Logging.warning("[MyTodos] DensityMapModifier.new (stone) failed: %s", tostring(mod))
        return false
    end
    self.stoneMod = mod

    -- Werte minValue..maxValue sind aktive Stein-Levels (small/medium/big).
    -- pickedValue (=5) und 0 sind "kein Stein vorhanden". Pro Wert ein Filter,
    -- am Ende summieren.
    self.stoneFilters = {}
    local minV = ss.minValue or 2
    local maxV = ss.maxValue or 4
    for value = minV, maxV do
        local f = DensityMapFilter.new(mod)
        f:setValueCompareParams(DensityValueCompareType.EQUAL, value)
        table.insert(self.stoneFilters, f)
    end
    Logging.info("[MyTodos] stone sampler ready (values %d..%d)", minV, maxV)
    return true
end

function MyTodos:fieldHasStones(field)
    if not self:initStoneSampler() then return false end
    if type(field.polygonPoints) ~= "table" or #field.polygonPoints == 0 then
        return false
    end
    self:applyFieldPolygon(self.stoneMod, field)

    local _, _, totalArea = self.stoneMod:executeGet()
    local threshold = math.max(
        MyTodos.STONE_MIN_PIXELS,
        math.floor((totalArea or 0) * self:_settingFraction("stonesThreshold",
            MyTodos.STONE_MIN_FRACTION * 100))
    )

    local stoneArea = 0
    for _, f in ipairs(self.stoneFilters) do
        local _, area, _ = self.stoneMod:executeGet(f)
        stoneArea = stoneArea + (area or 0)
        if stoneArea >= threshold then
            return true
        end
    end
    return false
end

-- Weed-Sampler -----------------------------------------------------

function MyTodos:initWeedSampler()
    if self.weedSamplerReady then return self.weedMod ~= nil end
    self.weedSamplerReady = true

    local wsys = g_currentMission and g_currentMission.weedSystem
    if wsys == nil then
        Logging.info("[MyTodos] weed sampler: no weedSystem")
        return false
    end
    if wsys.densityMap == nil then
        Logging.info("[MyTodos] weed sampler: weedSystem has no densityMap")
        return false
    end
    if DensityMapModifier == nil or DensityMapFilter == nil then
        Logging.info("[MyTodos] weed sampler: DensityMapModifier/Filter missing")
        return false
    end
    if g_currentMission.terrainRootNode == nil then
        Logging.info("[MyTodos] weed sampler: terrainRootNode missing")
        return false
    end

    local ok, mod = pcall(DensityMapModifier.new, wsys.densityMap,
        wsys.firstChannel or 0, wsys.numChannels or 4,
        g_currentMission.terrainRootNode)
    if not ok or mod == nil then
        Logging.warning("[MyTodos] weed sampler: DensityMapModifier.new failed: %s",
            tostring(mod))
        return false
    end
    self.weedMod = mod
    self.weedFactors = wsys.factors or {}

    -- Filter pro state 1..6 (active weed: wachsend bzw. lebendig).
    -- States 7..9 sind tot (mit Spritze behandelt) - werden ignoriert.
    self.weedFilters = {}
    for state = 1, 6 do
        local f = DensityMapFilter.new(mod)
        f:setValueCompareParams(DensityValueCompareType.EQUAL, state)
        self.weedFilters[state] = f
    end
    Logging.info("[MyTodos] weed sampler ready (densityMap=%s firstCh=%s numCh=%s)",
        tostring(wsys.densityMap), tostring(wsys.firstChannel), tostring(wsys.numChannels))
    return true
end

-- Liefert {state, factor} fuer das relevanteste actionable Stadium (1..6)
-- auf diesem Feld, oder nil wenn nichts ueber Threshold liegt. Grossunkraut
-- (state 5) hat Vorrang vor allen "klein"-Stufen -- state 6 ("klein dicht")
-- ist numerisch hoeher, agronomisch aber kleiner.
function MyTodos:sampleWeedForField(field, fieldId)
    if not self:initWeedSampler() then return nil end
    if type(field.polygonPoints) ~= "table" or #field.polygonPoints == 0 then
        return nil
    end
    self:applyFieldPolygon(self.weedMod, field)

    local _, _, totalArea = self.weedMod:executeGet()
    totalArea = totalArea or 0
    if totalArea == 0 then return nil end

    local threshold = math.max(
        MyTodos.WEED_MIN_PIXELS,
        math.floor(totalArea * MyTodos.WEED_MIN_FRACTION)
    )

    local highestState = 0
    local hasLarge = false
    local weightedSum = 0
    for state = 1, 6 do
        local _, area, _ = self.weedMod:executeGet(self.weedFilters[state])
        local count = area or 0
        if count >= threshold then
            if state == 5 then hasLarge = true end
            if state > highestState then highestState = state end
        end
        local f = self.weedFactors[state] or 0
        weightedSum = weightedSum + count * f
    end
    if highestState == 0 then return nil end
    -- Gemischter Befall (5 und 6 beide ueber Schwelle): "gross" melden,
    -- das bekommt nur noch die Spritze weg.
    if hasLarge then highestState = 5 end
    local factor = weightedSum / totalArea
    if factor < self:_settingFraction("weedThreshold",
            MyTodos.WEED_TOTAL_MIN_FACTOR * 100) then
        return nil
    end
    return { state = highestState, factor = factor }
end

-- pH-Sampler (Precision Farming) -----------------------------------
--
-- In FS25 hat Giants den PF-Mod umgebaut: `g_precisionFarming` als
-- klassisches Global existiert nicht (mehr). Stattdessen leben pHMap,
-- nitrogenMap, soilMap auf jedem PF-Sprayer-Spec als Singleton-Referenz
-- (`vehicle["spec_FS25_precisionFarming.extendedSprayer"].pHMap`). Die
-- zentrale PF-Instanz erreichen wir indirekt via `pHMap.pfModule`.
--
-- Strategie: einmal alle Fahrzeuge in `g_currentMission.vehicleSystem.vehicles`
-- scannen, erste pHMap-Referenz schnappen, cachen. Polygon-Sampling per
-- DensityMapModifier auf `pHMap.bitVectorMap` mit den Channels die in
-- der Map-Instanz selbst stehen.
--
-- pHValue-Konvertierung: aus dem Engine-Dump empirisch belegt
--   real_pH = 4.50 + internalValue * 0.125  (range 4.50 - 8.25, max 31)
-- Bevorzugt verwenden wir aber `pHMap:getPhValueFromInternalValue(v)` wenn
-- verfuegbar.

-- Sucht in der Fahrzeug-Liste nach einem Sprayer mit PF-Spec und gibt
-- dessen pHMap-Referenz zurueck. Erfolg wird gecached. Im Negativ-Fall
-- nicht cachen, damit es spaeter (nach Sprayer-Spawn) nochmal versucht
-- wird.
function MyTodos:findPfPHMap()
    if self._pfPHMapCached ~= nil then return self._pfPHMapCached end
    local vsys = g_currentMission and g_currentMission.vehicleSystem
    if vsys == nil or type(vsys.vehicles) ~= "table" then return nil end
    for _, veh in ipairs(vsys.vehicles) do
        if type(veh) == "table" then
            for k, v in pairs(veh) do
                if tostring(k):find("^spec_") and type(v) == "table"
                        and v.pHMap ~= nil then
                    self._pfPHMapCached = v.pHMap
                    return v.pHMap
                end
            end
        end
    end
    return nil
end

-- Liefert true wenn PF in dieser Welt tatsaechlich aktiv ist (= ein
-- PF-Sprayer existiert von dem wir pHMap holen koennen). Achtung: im
-- Negativ-Fall scannt findPfPHMap jedes Mal die komplette Fahrzeugliste
-- (Negativ-Ergebnis wird bewusst nicht gecached, siehe dort). In der
-- Task-Derivation deshalb self.precisionFarming == "active" pruefen --
-- das aktualisiert scanFields einmal pro Scan-Tick.
function MyTodos:isPfActive()
    return self:findPfPHMap() ~= nil
end

function MyTodos:initPhSampler()
    if self.phSamplerReady ~= nil then return self.phMod ~= nil end
    local pHMap = self:findPfPHMap()
    if pHMap == nil then
        return false  -- nicht cachen, evtl. spawnt spaeter ein Sprayer
    end
    self.phSamplerReady = true
    self.phMod = nil
    self.phMap = pHMap

    if pHMap.bitVectorMap == nil then
        Logging.info("[MyTodos] pH sampler: pHMap.bitVectorMap nil")
        return false
    end
    if DensityMapModifier == nil or g_currentMission.terrainRootNode == nil then
        Logging.info("[MyTodos] pH sampler: DensityMapModifier oder terrainRootNode missing")
        return false
    end

    local ok, mod = pcall(DensityMapModifier.new, pHMap.bitVectorMap,
        pHMap.firstChannel or 0, pHMap.numChannels or 5,
        g_currentMission.terrainRootNode)
    if not ok or mod == nil then
        Logging.warning("[MyTodos] pH sampler: DensityMapModifier.new failed: %s", tostring(mod))
        return false
    end
    self.phMod = mod
    Logging.info("[MyTodos] pH sampler ready (bitVectorMap=%s firstCh=%s numCh=%s maxValue=%s pHValuePerState=%s)",
        tostring(pHMap.bitVectorMap), tostring(pHMap.firstChannel),
        tostring(pHMap.numChannels), tostring(pHMap.maxValue),
        tostring(pHMap.pHValuePerState))
    return true
end

-- Konvertiert internal pH-value -> real pH. Benutzt bevorzugt die
-- pHMap-Methode, sonst die empirische Formel aus dem Probe-Dump.
function MyTodos:_phInternalToReal(internalValue)
    local m = self.phMap
    if m == nil then return nil end
    if type(m.getPhValueFromInternalValue) == "function" then
        local ok, real = pcall(m.getPhValueFromInternalValue, m, internalValue)
        if ok and type(real) == "number" then return real end
    end
    local step = m.pHValuePerState or 0.125
    return 4.50 + internalValue * step
end

-- Polygon-Average der pH-Map AUFGESPALTET nach Bodentyp. Cross-map-Filter:
-- pH-Modifier liest die pH-Werte, Soil-Filter (auf soilMap) reduziert die
-- Pixelmenge auf die mit soil==v. Engine sum/area beziehen sich dann nur
-- auf Pixel mit diesem Bodentyp. Liefert table[soilIdx] = {avgInternal, pixelArea}
-- oder nil. Bodentypen ohne Pixel im Feld fehlen einfach in der Tabelle.
--
-- Hintergrund: das Feld kann mehrere Bodenarten enthalten. PF setzt
-- pro-Pixel-Targets ein, also muss jeder Bodentyp gegen sein eigenes
-- Target verglichen werden. Frueheres Pauschal-Average + dominant-soil
-- war fuer gemischte Felder grob daneben.
function MyTodos:samplePhPerSoil(field)
    if not self:initPhSampler() then return nil end
    if not self:initSoilSampler() then return nil end
    if type(field.polygonPoints) ~= "table" or #field.polygonPoints == 0 then
        return nil
    end
    self:applyFieldPolygon(self.phMod, field)
    local out = {}
    for soilIdx = 1, MyTodos.SOIL_NUM_TYPES do
        local soilFilter = self.soilFilters and self.soilFilters[soilIdx]
        if soilFilter ~= nil then
            local sum, pixelArea, _ = self.phMod:executeGet(soilFilter)
            if pixelArea ~= nil and pixelArea >= 1 then
                out[soilIdx] = {
                    avgInternal = sum / pixelArea,
                    pixelArea = pixelArea,
                }
            end
        end
    end
    return out
end

-- Soil-Sampler (Precision Farming) ---------------------------------
--
-- soilMap hat 3 Channels insgesamt (typeFirstChannel=0, typeNumChannels=2
-- fuer den Bodentyp -> Werte 0..3; coverChannel=2 fuer Sampling-State).
--
-- WICHTIG: Bitmap-Wert ist 0..3, mappt auf soilTypes[1..4] mit OFFSET +1.
-- D.h. bitmap=0 -> soilTypes[1] (Lehmiger Sand), bitmap=3 -> soilTypes[4]
-- (Schluffiger Ton). KEIN "uninit"-Wert in dieser Codierung; alle Pixel
-- haben einen Bodentyp. Die "Bodenkarte gekauft"-Info sitzt im
-- coverChannel separat.
-- Empirisch verifiziert via mtDebugPf auf Feld 2: Histogramm zeigte
-- bitmap-Werte 0..3 mit Anteilen 40/26/3/31% -- PF-HUD am Sprayer
-- berichtete Targets fuer Lehmiger Sand + Schluffiger Ton (die zwei
-- haeufigsten via +1-Mapping), nicht fuer Lehm.

function MyTodos:initSoilSampler()
    if self.soilSamplerReady ~= nil then return self.soilMod ~= nil end
    local pf
    local pHMap = self:findPfPHMap()
    if pHMap == nil then return false end
    pf = pHMap.pfModule
    local soilMap = pf and pf.soilMap
    if soilMap == nil then
        -- Fallback: pHMap hat eine Backref auf soilMap
        soilMap = pHMap.soilMap
    end
    if soilMap == nil then
        return false
    end
    self.soilSamplerReady = true
    self.soilMap = soilMap

    if soilMap.bitVectorMap == nil then
        Logging.info("[MyTodos] soil sampler: soilMap.bitVectorMap nil")
        return false
    end
    if DensityMapModifier == nil or DensityMapFilter == nil
            or g_currentMission.terrainRootNode == nil then
        return false
    end
    local firstCh = soilMap.typeFirstChannel or 0
    local numCh = soilMap.typeNumChannels or 2
    local ok, mod = pcall(DensityMapModifier.new, soilMap.bitVectorMap,
        firstCh, numCh, g_currentMission.terrainRootNode)
    if not ok or mod == nil then
        Logging.warning("[MyTodos] soil sampler: DensityMapModifier.new failed: %s", tostring(mod))
        return false
    end
    self.soilMod = mod
    -- Tabellen-Index = soilType-Index (1..4, matched soilTypes[i].name und
    -- bySoilType[i]). Filter compared gegen bitmap-Wert (soilType-Index - 1)
    -- weil bitmap nur 0..3 hat.
    self.soilFilters = {}
    for soilIdx = 1, MyTodos.SOIL_NUM_TYPES do
        local f = DensityMapFilter.new(mod)
        f:setValueCompareParams(DensityValueCompareType.EQUAL, soilIdx - 1)
        self.soilFilters[soilIdx] = f
    end
    Logging.info("[MyTodos] soil sampler ready (bitVectorMap=%s firstCh=%d numCh=%d, soilType[i] -> bitmap %d..%d)",
        tostring(soilMap.bitVectorMap), firstCh, numCh, 0, MyTodos.SOIL_NUM_TYPES - 1)
    return true
end

-- Sucht in pHMap.valueTransformations den Eintrag fuer einen Bodentyp-
-- Index. Liefert {optimalValue, regularOffset} oder nil.
function MyTodos:lookupPhTransformForSoil(soilIdx)
    if self.phMap == nil then return nil end
    local transforms = self.phMap.valueTransformations
    if type(transforms) ~= "table" then return nil end
    for _, t in ipairs(transforms) do
        if t.soilTypeIndex == soilIdx then
            return {
                optimalValue = t.optimalValue,
                regularOffset = t.regularOffset or 0,
            }
        end
    end
    return nil
end

function MyTodos:soilTypeName(soilIdx)
    local sm = self.soilMap
    if sm == nil or type(sm.soilTypes) ~= "table" then return nil end
    local entry = sm.soilTypes[soilIdx]
    if entry == nil then return nil end
    return entry.name
end

-- Liefert "Kalk: pH X.X / Y.Y (Bodenname[, stark sauer])"-Label oder nil.
--
-- Per-Soil-Logik: iteriert ueber alle Bodentypen im Feld, vergleicht jeden
-- gegen sein eigenes Target (PF setzt pro-Pixel-Targets ein, also muss
-- pro Boden gerechnet werden -- ein gemischtes Feld kann Lehmiger-Sand-
-- Pixel bei pH 6.0 (= deren Idealwert) haben waehrend Lehm-Pixel bei
-- pH 6.7 (= deren Idealwert) sind. Avg waere 6.4 was als Defizit fuer
-- den dominanten Boden angezeigt wird, obwohl PF "alles gruen" sagt).
--
-- Reportet wird der Bodentyp mit der GROESSTEN Luecke (optimalValue - avg).
-- Bodentypen unter SOIL_MIN_FRACTION/SOIL_MIN_PIXELS Anteil werden
-- ignoriert (Rand-Pixel anderer Bodenarten).
function MyTodos:limeTaskPf(field)
    if self.precisionFarming ~= "active" then return nil end
    local perSoil = self:samplePhPerSoil(field)
    if perSoil == nil then return nil end
    local totalPx = 0
    for _, s in pairs(perSoil) do totalPx = totalPx + s.pixelArea end
    if totalPx < 1 then return nil end
    local minPx = math.max(MyTodos.SOIL_MIN_PIXELS,
        math.floor(totalPx * MyTodos.SOIL_MIN_FRACTION))

    local worst = nil  -- { soilIdx, avg, transform, gap }
    for soilIdx, sample in pairs(perSoil) do
        if sample.pixelArea >= minPx then
            local transform = self:lookupPhTransformForSoil(soilIdx)
            if transform ~= nil then
                local trigger = transform.optimalValue - transform.regularOffset
                if sample.avgInternal < trigger then
                    local gap = transform.optimalValue - sample.avgInternal
                    if worst == nil or gap > worst.gap then
                        worst = {
                            soilIdx = soilIdx,
                            avg = sample.avgInternal,
                            transform = transform,
                            gap = gap,
                        }
                    end
                end
            end
        end
    end
    if worst == nil then return nil end
    local realPh = self:_phInternalToReal(worst.avg) or 0
    local targetReal = self:_phInternalToReal(worst.transform.optimalValue) or 0
    local soilName = self:soilTypeName(worst.soilIdx) or "?"
    local extra = ""
    -- "stark sauer" wenn Luecke groesser als regularOffset + PH_HEAVY_GAP_STATES.
    if worst.gap >= worst.transform.regularOffset + MyTodos.PH_HEAVY_GAP_STATES then
        extra = self:t("myTodos_pf_lime_strong_acid")
    end
    return self:t("myTodos_pf_lime_label", realPh, targetReal, soilName, extra)
end

-- N-Sampler (Precision Farming) ------------------------------------
--
-- Polygon-Average ueber nitrogenMap.bitVectorMap, exakt wie pH-Sampler.
-- Internal-Range 0..45 (numChannels=6), amountPerState=5 -> 0..225 kg/ha.
-- Konvertierung intern -> real via nitrogenMap:getNitrogenValueFromInternalValue
-- (oder Fallback: (internal-1)*5 mit max(0, ...) weil internal=0 und 1 beide
-- als 0 kg/ha behandelt werden).

function MyTodos:findPfNitrogenMap()
    if self._pfNMapCached ~= nil then return self._pfNMapCached end
    local pHMap = self:findPfPHMap()
    if pHMap == nil then return nil end
    local pf = pHMap.pfModule
    local nMap = pf and pf.nitrogenMap
    if nMap == nil then return nil end
    self._pfNMapCached = nMap
    return nMap
end

function MyTodos:initNSampler()
    if self.nSamplerReady ~= nil then return self.nMod ~= nil end
    local nMap = self:findPfNitrogenMap()
    if nMap == nil then return false end
    self.nSamplerReady = true
    self.nMap = nMap

    if nMap.bitVectorMap == nil then
        Logging.info("[MyTodos] N sampler: nitrogenMap.bitVectorMap nil")
        return false
    end
    if DensityMapModifier == nil or g_currentMission.terrainRootNode == nil then
        return false
    end
    local ok, mod = pcall(DensityMapModifier.new, nMap.bitVectorMap,
        nMap.firstChannel or 0, nMap.numChannels or 6,
        g_currentMission.terrainRootNode)
    if not ok or mod == nil then
        Logging.warning("[MyTodos] N sampler: DensityMapModifier.new failed: %s", tostring(mod))
        return false
    end
    self.nMod = mod
    Logging.info("[MyTodos] N sampler ready (bitVectorMap=%s firstCh=%s numCh=%s maxValue=%s amountPerState=%s)",
        tostring(nMap.bitVectorMap), tostring(nMap.firstChannel),
        tostring(nMap.numChannels), tostring(nMap.maxValue),
        tostring(nMap.amountPerState))
    return true
end

function MyTodos:_nInternalToReal(internalValue)
    local m = self.nMap
    if m == nil then return nil end
    if type(m.getNitrogenValueFromInternalValue) == "function" then
        local ok, real = pcall(m.getNitrogenValueFromInternalValue, m, internalValue)
        if ok and type(real) == "number" then return real end
    end
    local step = m.amountPerState or 5
    return math.max(0, (internalValue - 1) * step)
end

-- Polygon-Average der N-Map AUFGESPALTET nach Bodentyp. Cross-map-Filter:
-- N-Modifier liest die N-Werte, Soil-Filter reduziert auf Pixel mit soil==v.
-- Liefert table[soilIdx] = {avgInternal, pixelArea} oder nil.
-- Selbe Begruendung wie samplePhPerSoil: N-Target haengt vom Boden ab,
-- gemischte Felder muessen per-Soil bewertet werden.
function MyTodos:sampleNPerSoil(field)
    if not self:initNSampler() then return nil end
    if not self:initSoilSampler() then return nil end
    if type(field.polygonPoints) ~= "table" or #field.polygonPoints == 0 then
        return nil
    end
    self:applyFieldPolygon(self.nMod, field)
    local out = {}
    for soilIdx = 1, MyTodos.SOIL_NUM_TYPES do
        local soilFilter = self.soilFilters and self.soilFilters[soilIdx]
        if soilFilter ~= nil then
            local sum, pixelArea, _ = self.nMod:executeGet(soilFilter)
            if pixelArea ~= nil and pixelArea >= 1 then
                out[soilIdx] = {
                    avgInternal = sum / pixelArea,
                    pixelArea = pixelArea,
                }
            end
        end
    end
    return out
end

-- Lookup: (fruitTypeIndex, soilTypeIndex) -> { internal, real, reductionInternal }
-- oder nil. Liest nitrogenMap.fruitTypeIndexToFruitRequirement direkt.
--
-- `targetLevel` = "Regular Rate"-Auto-Apply-Zielwert (was PF anstrebt).
-- `reduction` = "Reduced Rate"-Zielwert, typisch 3-8 states unter target.
--   Das ist die Schwelle unter der PF auto-apply re-feuert. Ueber dieser
--   Schwelle sagt PF "grün" -> kein Re-Apply noetig. Diese Schwelle
--   nutzen wir als Trigger fuer die Task (matched PF-UX).
function MyTodos:lookupNTargetByFruitAndSoil(fruitIdx, soilIdx)
    local nMap = self.nMap or self:findPfNitrogenMap()
    if nMap == nil then return nil end
    local map = nMap.fruitTypeIndexToFruitRequirement
    if type(map) ~= "table" then return nil end
    local req = map[fruitIdx]
    if req == nil then return nil end
    if (req.averageTargetLevel or 0) <= 0 then return nil end
    local bySoil = req.bySoilType
    if type(bySoil) ~= "table" then return nil end
    local entry = bySoil[soilIdx]
    if entry == nil then return nil end
    local target = entry.targetLevel
    if target == nil or target <= 0 then return nil end
    local reduction = entry.reduction
    return {
        internal = target,
        real = self:_nInternalToReal(target) or 0,
        reductionInternal = (reduction ~= nil and reduction > 0) and reduction or nil,
    }
end

-- Liefert "N: 35/85 kg/ha (Weizen, Lehm[, N-Mangel])"-Label oder nil.
--
-- Per-Soil-Logik wie limeTaskPf: iteriert ueber alle Bodentypen im Feld,
-- vergleicht avg-N pro Boden gegen den jeweiligen targetLevel aus
-- nitrogenMap.fruitTypeIndexToFruitRequirement[fruit].bySoilType[soil].
-- Reportet wird der Boden mit der GROESSTEN Luecke.
function MyTodos:fertilizerTaskPf(field, fs, fruit)
    if self.precisionFarming ~= "active" then return nil end
    if fruit == nil or fruit.regrows then return nil end
    local perSoil = self:sampleNPerSoil(field)
    if perSoil == nil then return nil end
    local totalPx = 0
    for _, s in pairs(perSoil) do totalPx = totalPx + s.pixelArea end
    if totalPx < 1 then return nil end
    local minPx = math.max(MyTodos.SOIL_MIN_PIXELS,
        math.floor(totalPx * MyTodos.SOIL_MIN_FRACTION))

    local worst = nil  -- { soilIdx, avg, target, gap, trigger }
    for soilIdx, sample in pairs(perSoil) do
        if sample.pixelArea >= minPx then
            local target = self:lookupNTargetByFruitAndSoil(fruit.index, soilIdx)
            if target ~= nil then
                -- Trigger = reductionInternal wenn vorhanden (PF's eigener
                -- "noch nicht genug"-Schwellwert), sonst Fallback target-Gap.
                local trigger = target.reductionInternal
                    or (target.internal - MyTodos.N_GAP_STATES)
                if sample.avgInternal < trigger then
                    -- Ranking-Metrik: Abstand zum Trigger (nicht zum Target).
                    -- So gewinnt der Boden mit der echtesten Unterversorgung,
                    -- nicht der mit dem hoechsten absoluten Target.
                    local gap = trigger - sample.avgInternal
                    if worst == nil or gap > worst.gap then
                        worst = {
                            soilIdx = soilIdx,
                            avg = sample.avgInternal,
                            target = target,
                            trigger = trigger,
                            gap = gap,
                        }
                    end
                end
            end
        end
    end
    if worst == nil then return nil end
    local realKg = self:_nInternalToReal(worst.avg) or 0
    local soilName = self:soilTypeName(worst.soilIdx) or "?"
    -- "N-Mangel" wenn weitere N_HEAVY_GAP_STATES unter dem Trigger
    -- (= deutlich unter reduction).
    local extra = ""
    if worst.gap >= MyTodos.N_HEAVY_GAP_STATES then
        extra = self:t("myTodos_pf_n_deficit")
    end
    return self:t("myTodos_pf_n_label",
        math.floor(realKg + 0.5), math.floor(worst.target.real + 0.5),
        self:fruitName(fruit), soilName, extra)
end

-- Field history (Duengen-Lockout) ----------------------------------

function MyTodos:updateFieldHistory(fieldId, fs)
    local h = self.fieldHistory[fieldId]
    if h == nil then
        h = { sprayLevel = -1, sprayLockedAt = -1 }
        self.fieldHistory[fieldId] = h
    end
    local cur = fs.sprayLevel or 0
    local growth = fs.growthState or 0
    if h.sprayLevel >= 0 then
        if cur > h.sprayLevel then
            h.sprayLockedAt = growth
        elseif cur < h.sprayLevel then
            h.sprayLockedAt = -1
        end
    end
    h.sprayLevel = cur
end

function MyTodos:isFertLocked(fieldId, fs)
    local h = self.fieldHistory[fieldId]
    if h == nil then return false end
    if h.sprayLockedAt < 0 then return false end
    return h.sprayLockedAt == (fs.growthState or 0)
end

-- Task derivation --------------------------------------------------

-- Returns: task (fertig formatierter HUD-String), primary, parallel-Liste.
-- primary/parallel braucht die Komplettuebersicht fuer ihre Tabellenspalten.
function MyTodos:deriveFieldTask(field, fieldId)
    local fs = field.fieldState
    if fs == nil then
        local label = self:t("myTodos_task_no_fieldstate")
        return label, label, {}
    end
    return self:deriveTaskVanilla(fs, fieldId, field)
end

function MyTodos:deriveTaskVanilla(fs, fieldId, field)
    local fruit = nil
    if (fs.fruitTypeIndex or 0) > 0 and g_fruitTypeManager ~= nil then
        fruit = g_fruitTypeManager:getFruitTypeByIndex(fs.fruitTypeIndex)
    end

    local primary, actionable = self:derivePrimaryVanilla(fs, fruit, field, fieldId)
    local parallel = self:deriveParallelVanilla(fs, fruit, fieldId, field)

    -- Wenn Frucht still wächst und nichts paralleles offen ist: Feld ausblenden.
    if not actionable and #parallel == 0 then
        return nil
    end

    local task
    if #parallel == 0 then
        task = primary
    else
        task = string.format("%s  [+ %s]", primary, table.concat(parallel, ", "))
    end
    return task, primary, parallel
end

function MyTodos:isPlowingRequired()
    if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil then
        local v = g_currentMission.missionInfo.plowingRequiredEnabled
        if v ~= nil then return v end
    end
    if g_currentMission ~= nil and g_currentMission.getIsPlowingRequired ~= nil then
        return g_currentMission:getIsPlowingRequired()
    end
    return true  -- konservativer Default
end

-- Returns: text, actionable (boolean). actionable=false bedeutet "passiv,
-- waechst nur, ohne Parallel-Tasks ausblenden".
function MyTodos:derivePrimaryVanilla(fs, fruit, field, fieldId)
    local plowReq = self:isPlowingRequired()

    if fruit ~= nil then
        local name = self:fruitName(fruit)
        local minHarvest = fruit.minHarvestingGrowthState
        local maxHarvest = fruit.maxHarvestingGrowthState
        local withered = fruit.witheredState
        local cutState = fruit.cutState
        local rolledCutState = fruit.rolledCutState
        local growth = fs.growthState or 0

        if withered ~= nil and growth == withered then
            return self:t("myTodos_fruit_withered", name), true
        end

        -- Regrowing-Fruechte (Gras, Sugarcane etc.): kein Pflug/Grubber/Saat-Pfad,
        -- der Wachstumszyklus laeuft automatisch.
        if fruit.regrows then
            if growth == cutState or growth == rolledCutState then
                return self:t("myTodos_fruit_cut", name), false
            end
            -- Erntefaehig ueber das ganze Engine-Fenster [lowerBound..maxHarvest]
            -- = exakt die foliageStates mit isHarvestReady=true.
            --   Mit Preparing-Stadium (Sugarcane: minPrep=8, maxHarvest=11):
            --     lowerBound=minPrep - Spieler kann state 8 direkt ernten oder
            --     vorher Blaetter brennen -> state 11 (prepared) -> ernten.
            --   Ohne Preparing (Gras, Alfalfa): lowerBound=minHarvest.
            --     Alfalfa hat ein echtes Mehr-State-Fenster (greenMiddle=5
            --     yieldScale .6, greenMiddle2=6 .8, harvestReady=7 1.0) und
            --     parkt saisonal auf 6 (LATE_SPRING + Autumn-Knockback haben
            --     keinen 6->7 Uebergang), erreicht maxHarvest also nicht
            --     zuverlaessig. "Auf maxHarvest warten" war ein Yield-Opt-Hint
            --     (gegen die Tool-Philosophie) und verschluckte Alfalfa@6.
            --     Gras (min=3/max=4) zeigt damit ab greenMiddle - engine-korrekt.
            local minPrep = fruit.minPreparingGrowthState
            local lowerBound
            if minPrep ~= nil and minPrep >= 1 then
                lowerBound = minPrep
            else
                lowerBound = minHarvest
            end
            local inHarvestRange = maxHarvest ~= nil and lowerBound ~= nil
                and growth >= lowerBound and growth <= maxHarvest
            if inHarvestRange then
                return self:t("myTodos_fruit_harvest", name), true
            end
            -- Unkraut laeuft jetzt als eigenstaendiger Parallel-Task
            -- (deriveParallelVanilla), nicht mehr als Label an der Wachstums-
            -- phase -- sonst doppelt und nur waehrend Wachstum sichtbar.
            return self:t("myTodos_fruit_growing",
                name, tostring(growth), tostring(maxHarvest)), false
        end

        -- Cut-State Pfad: growth ist einer der cutStates der Frucht.
        --
        -- Mehrfach-erntbare Fruechte mit Regrowth (Spinat: cutStates={9,10},
        -- minHarvest=6, maxHarvest=7) haben einen Zwischen-Cut wo die Pflanze
        -- zur naechsten Erntestufe regrowt. Heuristik: minHarvest < maxHarvest
        -- bedeutet "echte" Erntestufen-Range -> Multi-Cut moeglich.
        --
        -- Mais hat zwar cutStates={9,10} (Forage-Cut + Koerner-Cut), aber
        -- minHarvest=maxHarvest=7 -> keine Range, beide cuts sind final.
        if type(fruit.cutStates) == "table" and fruit.cutStates[growth] then
            local minH = fruit.minHarvestingGrowthState or 0
            local maxH = fruit.maxHarvestingGrowthState or 0
            if minH < maxH and growth ~= cutState then
                return self:t("myTodos_fruit_regrowing", name), false
            end
            return self:derivePrepTask(fs, plowReq)
        end
        -- Forage (Haecksel-Ernte fuer Silage): zwischen minForageGrowthState
        -- und Beginn der Trockenernte. Mais 5..6 (vor minHarvest=7).
        --
        -- Heuristik `minForage + 1 < minHarvest` filtert nominell-gesetzte aber
        -- funktional tote Engine-Properties: Wheat (minForage=7, minHarvest=8)
        -- und Canola (minForage=8, minHarvest=9) lassen sich Vanilla nicht
        -- haeckseln, also kein Forage-Label. Mais hat mit Range [5..6]
        -- echte Forage-Phase und triggert.
        --
        -- maxForageGrowthState wird bewusst ignoriert - bei Mais sagt die
        -- Engine maxForage=5, growthStateName 6 ist aber noch
        -- "harvestReadyGreen2" und gehoert vom Spieler-Standpunkt zu Forage.
        local minForage = fruit.minForageGrowthState
        if minForage ~= nil and minForage >= 1
                and minHarvest ~= nil and minForage + 1 < minHarvest
                and growth >= minForage and growth < minHarvest then
            return self:t("myTodos_fruit_forage", name), true
        end

        -- Ernten: untere Grenze ist die frueheste actionable Stufe.
        -- minPreparingGrowthState (Wurzelfruechte mit Krautschlag wie
        -- Zuckerruebe, Zwiebel) zieht "Ernten" nach vorne; Spieler weiss
        -- selbst dass erst Krautschlag noetig ist.
        local effectiveMinHarvest = minHarvest
        local minPrep = fruit.minPreparingGrowthState
        if minPrep ~= nil and minPrep >= 1
                and (effectiveMinHarvest == nil or minPrep < effectiveMinHarvest) then
            effectiveMinHarvest = minPrep
        end
        if effectiveMinHarvest ~= nil and maxHarvest ~= nil
                and growth >= effectiveMinHarvest and growth <= maxHarvest then
            return self:t("myTodos_fruit_harvest", name), true
        end
        return self:t("myTodos_fruit_growing",
            name, tostring(growth), tostring(maxHarvest)), false
    end

    -- Kein fruitTypeIndex: leeres Feld -> Prep-Pfad
    return self:derivePrepTask(fs, plowReq)
end

-- Unkraut-Label fuer den Parallel-Task. Nur LEBENDES, sichtbares Unkraut
-- (Stufen 3..6) wird gemeldet -- unabhaengig von der Frucht-Phase, also auch
-- auf reifen/stehenden Fruechten (wo Jaeten nicht mehr geht, das Unkraut aber
-- da ist und erst nach Ernte + Grubbern verschwindet).
--
-- weedState-Enum (0..9, empirisch via Cheat-Tool + weedSystem.factors):
--   0       = sauber (Default oder nach Striegel/Spritze)
--   1, 2    = wachsend/unsichtbar      -> bewusst NICHT gemeldet (Rauschen)
--   3, 4    = klein, lebendig          -> "Unkraut klein"
--   5       = gross, lebendig          -> "Unkraut gross"
--   6       = klein dicht, lebendig    -> "Unkraut klein"
--   7, 8, 9 = tot (gespritzt)          -> NICHT gemeldet (verschwindet beim Grubbern)
--
-- Quelle: bevorzugt weedSystem.densityMap polygon-sampling (sampleWeedForField,
-- inkl. Schwelle). Fallback auf das fieldState-Aggregat wenn Sampler fehlt.
function MyTodos:weedParallelLabel(field, fs, fieldId)
    local state, factor
    if field ~= nil and self:initWeedSampler() then
        local s = self:sampleWeedForField(field, fieldId)
        if s == nil then return nil end
        state, factor = s.state, s.factor
    else
        state = fs.weedState or 0
        factor = fs.weedFactor or 0
    end
    -- nur lebendes, sichtbares Unkraut (3..6); 0/1/2 (wachsend) und 7..9 (tot) raus
    if state < 3 or state > 6 then return nil end
    local isLarge = (state == 5)
    if factor > 0 then
        local key = isLarge and "myTodos_weed_large_pct" or "myTodos_weed_small_pct"
        return self:t(key, factor * 100)
    end
    return self:t(isLarge and "myTodos_weed_large" or "myTodos_weed_small")
end

function MyTodos:derivePrepTask(fs, plowReq)
    if plowReq and (fs.plowLevel or 0) == 0 then
        return self:t("myTodos_task_plow"), true
    end
    if self:isSeedbedReady(fs) then
        return self:t("myTodos_task_seed"), true
    end
    return self:t("myTodos_task_cultivate"), true
end

function MyTodos:isSeedbedReady(fs)
    local fgs = g_currentMission and g_currentMission.fieldGroundSystem
    if fgs == nil then return false end
    local first = fgs.firstSowableValue or 1
    local last = fgs.lastSowableValue or 6
    local gt = fs.groundType or 0
    return gt >= first and gt <= last
end

function MyTodos:deriveParallelVanilla(fs, fruit, fieldId, field)
    local out = {}
    local sprayMax = (g_fieldManager and g_fieldManager.sprayLevelMaxValue) or 2

    if fruit ~= nil then
        local maxHarvest = fruit.maxHarvestingGrowthState
        local minHarvest = fruit.minHarvestingGrowthState
        local cutState = fruit.cutState
        local growth = fs.growthState or 0
        local spray = fs.sprayLevel or 0
        local roller = fs.rollerLevel or 0
        local atCut = cutState ~= nil and growth == cutState
        local stillGrowing = not atCut and maxHarvest ~= nil and growth >= 1
            and (minHarvest == nil or growth < minHarvest)

        -- Duengen: PF (N-aware via nitrogenMap) wenn aktiv, sonst vanilla
        -- Spray-Level mit Lockout-Heuristik. Misch-Modus bewusst nicht --
        -- unter PF ist sprayLevel zwar weiterhin vorhanden, aber die
        -- relevante Information sitzt in der N-Map.
        if stillGrowing and not fruit.regrows then
            if self.precisionFarming == "active" then
                local pfTask = self:fertilizerTaskPf(field, fs, fruit)
                if pfTask ~= nil then
                    table.insert(out, pfTask)
                end
            elseif spray < sprayMax and not self:isFertLocked(fieldId, fs) then
                table.insert(out, self:t("myTodos_task_fertilize", spray, sprayMax))
            end
        end
        -- Walzen: rollerLevel ist INVERTIERT. 1 = "muss gewalzt werden", 0 = erledigt.
        -- ABER: bei non-regrowing Fruechten ist Walzen nur direkt nach Saat
        -- (growth=1, invisible) gefahrlos - spaeter setzt es Wachstum zurueck
        -- oder zerstoert die Frucht. Bei regrowing (Gras) ist Walzen Teil des
        -- Lifecycle nach Maehen (growth=cutState -> rolledCutState).
        if fruit.needsRolling and roller > 0 then
            local rollSafe
            if fruit.regrows then
                rollSafe = (fruit.cutState ~= nil and growth == fruit.cutState)
            else
                rollSafe = (growth <= 1)
            end
            if rollSafe then
                table.insert(out, self:t("myTodos_task_roll"))
            end
        end
        -- Mulchen Stoppel: nur bei Fruechten mit echtem cutState (nicht regrowing)
        if not fruit.regrows and atCut and (fs.stubbleShredLevel or 0) == 0 then
            table.insert(out, self:t("myTodos_task_mulch"))
        end
    end

    -- Kalken: bei regrowing/non-consuming Fruechten ueberspringen
    -- (Gras profitiert nicht). Bei PF (Precision Farming) lesen wir den
    -- realen pH-Wert via pHMap-Polygon-Sample und triggern nur wenn unter
    -- Zielbereich. Ohne PF fallen wir zurueck auf Vanilla limeLevel==0.
    -- Bewusst kein Misch-Verhalten: wenn PF aktiv, kein Vanilla-Fallback,
    -- denn vanilla limeLevel hat unter PF andere Semantik.
    local limeBenefits = (fruit == nil) or (fruit.consumesLime ~= false)
    if limeBenefits then
        if self.precisionFarming == "active" then
            local pfTask = self:limeTaskPf(field)
            if pfTask ~= nil then
                table.insert(out, pfTask)
            end
        elseif (fs.limeLevel or 0) == 0 then
            table.insert(out, self:t("myTodos_task_lime"))
        end
    end

    -- Steine: fs.stoneLevel taugt nicht (bleibt oft 0 trotz sichtbarer
    -- Steine) -> direkt auf stoneSystem.densityMap polygon-sampeln.
    if field ~= nil and self:fieldHasStones(field) then
        table.insert(out, self:t("myTodos_task_stones"))
    end

    -- Schwadläden auf dem Feld (Stroh, Gras, Heu) via Density-Map-Sampling
    if field ~= nil then
        local windrows = self:sampleWindrowsForField(field)
        for _, label in ipairs(windrows) do
            table.insert(out, label)
        end
    end

    -- Unkraut: eigenstaendiger Parallel-Task (lebendes Unkraut Stufe 3..6 ueber
    -- Schwelle), unabhaengig von der Frucht-Phase -- erscheint also auch neben
    -- "Ernten" auf reifen Fruechten und auf Stoppel-/Leerfeldern.
    if field ~= nil then
        local weed = self:weedParallelLabel(field, fs, fieldId)
        if weed ~= nil then
            table.insert(out, weed)
        end
    end

    return out
end
