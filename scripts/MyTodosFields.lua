--
-- MyTodos / Fields
--
-- Field-Discovery, Task-Derivation und Density-Map-Sampler (Windrow,
-- Stones, Weed). Alles was mit eigenen Aeckern zu tun hat. Erweitert die
-- in MyTodos.lua angelegte MyTodos-Tabelle.
--

-- Sampler-Schwellen ------------------------------------------------

MyTodos.WINDROW_TYPES = {
    { name = "STRAW",            label = "Stroh aufnehmen" },
    { name = "GRASS_WINDROW",    label = "Gras-Schwad aufnehmen" },
    { name = "DRYGRASS_WINDROW", label = "Heu aufnehmen" },
}

-- Mindestens so viele Pixel muessen ein bestimmten Schwadtyp haben, sonst
-- wird's als vernachlaessigbarer Rest behandelt.
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
-- 2. Gewichteter Gesamt-Faktor >= 5% damit Label rausgegeben wird
-- Damit verschwinden Mikro-Befaelle (1-3% groß-Unkraut auf grossen Feldern).
MyTodos.WEED_MIN_PIXELS = 50
MyTodos.WEED_MIN_FRACTION = 0.01
MyTodos.WEED_TOTAL_MIN_FACTOR = 0.05

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
-- Mindest-Pixel + -Anteil damit eine Bodenart als "dominant" zaehlt.
-- Gleiche Konvention wie Stein-/Weed-Sampler.
MyTodos.SOIL_MIN_PIXELS = 50
MyTodos.SOIL_MIN_FRACTION = 0.05

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
                    label = def.label,
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
        math.floor(hTotalArea * MyTodos.WINDROW_MIN_FRACTION)
    )
    if hArea < threshold then
        return {}
    end

    -- Schritt 2: welche Type(n) sind ueber Threshold?
    local labels = {}
    for _, w in ipairs(self.windrowFilters) do
        local ok, _, area, _ = pcall(self.windrowMod.executeGet, self.windrowMod, w.filter)
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
        math.floor((totalArea or 0) * MyTodos.STONE_MIN_FRACTION)
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

-- Liefert {state, factor} fuer das hoechste actionable Stadium (1..6) auf
-- diesem Feld, oder nil wenn nichts ueber Threshold liegt.
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
    local weightedSum = 0
    for state = 1, 6 do
        local _, area, _ = self.weedMod:executeGet(self.weedFilters[state])
        local count = area or 0
        if count >= threshold and state > highestState then
            highestState = state
        end
        local f = self.weedFactors[state] or 0
        weightedSum = weightedSum + count * f
    end
    if highestState == 0 then return nil end
    local factor = weightedSum / totalArea
    if factor < MyTodos.WEED_TOTAL_MIN_FACTOR then return nil end
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
-- PF-Sprayer existiert von dem wir pHMap holen koennen).
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

-- Polygon-Average ueber das Feld. Liefert ein Tupel {realPh, internal}
-- oder nil. Internal-Repraesentation brauchen wir um mit den
-- valueTransformations-Schwellen vergleichen zu koennen (die sind
-- ebenfalls in internal-state-Einheiten).
function MyTodos:samplePhForField(field)
    if not self:initPhSampler() then return nil end
    if type(field.polygonPoints) ~= "table" or #field.polygonPoints == 0 then
        return nil
    end
    self:applyFieldPolygon(self.phMod, field)
    -- executeGet() ohne Filter: sum, pixelArea, totalArea
    local sum, pixelArea, _ = self.phMod:executeGet()
    if pixelArea == nil or pixelArea < 1 then return nil end
    local avgInternal = sum / pixelArea
    -- Sehr niedrige Averages = "Soil-Map nicht gekauft" (uninitialisierte
    -- Tiles haben internal=0). Schwellwert empirisch: bei gekauften Maps
    -- liegt der Average typisch bei 5-25 (entspricht pH 5-7.5).
    if avgInternal < 1 then return nil end
    local realPh = self:_phInternalToReal(avgInternal)
    if realPh == nil then return nil end
    return { real = realPh, internal = avgInternal }
end

-- Soil-Sampler (Precision Farming) ---------------------------------
--
-- Bestimmt die DOMINANTE Bodenart eines Feldes via Polygon-Sampling auf
-- soilMap.bitVectorMap. soilMap hat 3 Channels insgesamt
-- (typeFirstChannel=0, typeNumChannels=2 fuer den Typ-Anteil = 4 Werte,
-- der dritte Channel ist Cover/Sampling-State). Werte 1..4 mappen direkt
-- auf soilMap.soilTypes[1..4]. Value 0 = uninitialisiert.

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
    self.soilFilters = {}
    for v = 1, MyTodos.SOIL_NUM_TYPES do
        local f = DensityMapFilter.new(mod)
        f:setValueCompareParams(DensityValueCompareType.EQUAL, v)
        self.soilFilters[v] = f
    end
    Logging.info("[MyTodos] soil sampler ready (bitVectorMap=%s firstCh=%d numCh=%d)",
        tostring(soilMap.bitVectorMap), firstCh, numCh)
    return true
end

-- Liefert den dominanten Bodentyp-Index (1..N) oder nil.
function MyTodos:sampleDominantSoilType(field)
    if not self:initSoilSampler() then return nil end
    if type(field.polygonPoints) ~= "table" or #field.polygonPoints == 0 then
        return nil
    end
    self:applyFieldPolygon(self.soilMod, field)
    local _, _, totalArea = self.soilMod:executeGet()
    if totalArea == nil or totalArea < 1 then return nil end
    local threshold = math.max(
        MyTodos.SOIL_MIN_PIXELS,
        math.floor(totalArea * MyTodos.SOIL_MIN_FRACTION)
    )
    local bestIdx, bestArea = nil, 0
    for v = 1, MyTodos.SOIL_NUM_TYPES do
        local _, area, _ = self.soilMod:executeGet(self.soilFilters[v])
        if area ~= nil and area > bestArea and area >= threshold then
            bestArea = area
            bestIdx = v
        end
    end
    return bestIdx
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

-- Liefert "Kalk: pH X.X / Y.Y (Bodenname[, stark sauer])"-Label oder nil
-- wenn nichts zu tun (PF inaktiv, Soil-Map nicht gekauft, pH okay).
--
-- Trigger-Logik exakt wie PF's eigener Auto-Apply:
--   triggerInternal = optimalValue - regularOffset
--   wenn avg < trigger -> Kalk noetig
-- "stark sauer" wenn avg <= trigger - PH_HEAVY_GAP_STATES (~ 80% Yield).
function MyTodos:limeTaskPf(field)
    if not self:isPfActive() then return nil end
    local ph = self:samplePhForField(field)
    if ph == nil then return nil end
    local soilIdx = self:sampleDominantSoilType(field)
    if soilIdx == nil then return nil end
    local transform = self:lookupPhTransformForSoil(soilIdx)
    if transform == nil then return nil end
    local triggerInternal = transform.optimalValue - transform.regularOffset
    if ph.internal >= triggerInternal then return nil end
    local targetReal = self:_phInternalToReal(transform.optimalValue) or 0
    local soilName = self:soilTypeName(soilIdx) or "?"
    local extra = ""
    if ph.internal <= triggerInternal - MyTodos.PH_HEAVY_GAP_STATES then
        extra = ", stark sauer"
    end
    return string.format("Kalk: pH %.1f / %.1f (%s%s)",
        ph.real, targetReal, soilName, extra)
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

function MyTodos:deriveFieldTask(field, fieldId)
    local fs = field.fieldState
    if fs == nil then return "(kein fieldState)" end
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

    if #parallel == 0 then
        return primary
    end
    return string.format("%s  [+ %s]", primary, table.concat(parallel, ", "))
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
            return string.format("%s: Verwelkt", name), true
        end

        -- Regrowing-Fruechte (Gras, Sugarcane etc.): kein Pflug/Grubber/Saat-Pfad,
        -- der Wachstumszyklus laeuft automatisch.
        if fruit.regrows then
            if growth == cutState or growth == rolledCutState then
                return string.format("%s: gemäht", name), false
            end
            -- Erntefaehig:
            --   Mit Preparing-Stadium (Sugarcane: minPrep=8, maxHarvest=11):
            --     Range [minPrep..maxHarvest] - Spieler kann state 8 direkt
            --     ernten oder vorher Blaetter brennen -> state 11 (prepared)
            --     -> ernten. Beides ist actionable.
            --   Ohne Preparing (Gras):
            --     Nur bei vollem Yield als "Ernten" - frueher maehen geht aber
            --     bringt weniger Yield. Wir warten auf maxHarvest.
            local minPrep = fruit.minPreparingGrowthState
            local hasPrep = minPrep ~= nil and minPrep >= 1
            local inHarvestRange
            if hasPrep then
                inHarvestRange = maxHarvest ~= nil
                    and growth >= minPrep and growth <= maxHarvest
            else
                inHarvestRange = maxHarvest ~= nil and growth == maxHarvest
            end
            if inHarvestRange then
                return string.format("%s: Ernten", name), true
            end
            if fruit.plantsWeed ~= false then
                local label = self:weedLabel(field, fs, fieldId)
                if label ~= nil then
                    return string.format("%s: %s", name, label), true
                end
            end
            return string.format("%s: Wächst (%s/%s)",
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
                return string.format("%s: Wächst nach", name), false
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
            return string.format("%s: Forage", name), true
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
            return string.format("%s: Ernten", name), true
        end
        if fruit.plantsWeed ~= false then
            local label = self:weedLabel(field, fs, fieldId)
            if label ~= nil then
                return string.format("%s: %s", name, label), true
            end
        end
        return string.format("%s: Wächst (%s/%s)",
            name, tostring(growth), tostring(maxHarvest)), false
    end

    -- Kein fruitTypeIndex: leeres Feld -> Prep-Pfad
    return self:derivePrepTask(fs, plowReq)
end

-- weedState ist ein 0..9-Enum (FS25, empirisch via Cheat-Tool und in
-- weedSystem.factors bestaetigt):
--   0     = komplett sauber (Default oder nach Striegel/Spritze)
--   1, 2  = invisible / invisible dense (wachsend, noch nicht sichtbar)
--           -> "Unkraut wachsend" (Striegel jetzt verhindert sichtbares Wachstum)
--   3, 4  = klein, lebendig                            -> "Unkraut klein"
--   5     = gross, lebendig                            -> "Unkraut gross"
--   6     = klein dicht, gestriegelt aber lebt         -> "Unkraut klein"
--   7, 8, 9 = tot (mit Spritze behandelt)              -> nicht melden (verschwindet beim Cultivieren)
--
-- Quelle: bevorzugt weedSystem.densityMap polygon-sampling (siehe
-- sampleWeedForField). fs.weedState/fs.weedFactor sind Aggregate die nicht
-- zuverlaessig sind. Fallback auf Aggregat wenn Sampler nicht verfuegbar.
function MyTodos:weedLabel(field, fs, fieldId)
    local state, factor
    if field ~= nil and self:initWeedSampler() then
        local s = self:sampleWeedForField(field, fieldId)
        if s == nil then return nil end
        state, factor = s.state, s.factor
    else
        state = fs.weedState or 0
        factor = fs.weedFactor or 0
        if state == 0 or state >= 7 then return nil end
    end
    if state <= 2 then
        return "Unkraut wachsend"
    end
    local size = (state == 5) and "groß" or "klein"
    if factor > 0 then
        return string.format("Unkraut %s (%.0f%%)", size, factor * 100)
    end
    return string.format("Unkraut %s", size)
end

function MyTodos:derivePrepTask(fs, plowReq)
    if plowReq and (fs.plowLevel or 0) == 0 then
        return "Pflügen", true
    end
    if self:isSeedbedReady(fs) then
        return "Säen", true
    end
    return "Grubbern", true
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

        -- Düngen: klassische Spritze, nur fuer nicht-regrowing Fruechte
        if stillGrowing and not fruit.regrows
                and spray < sprayMax
                and not self:isFertLocked(fieldId, fs) then
            table.insert(out, string.format("Düngen %d/%d", spray, sprayMax))
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
                table.insert(out, "Walzen")
            end
        end
        -- Mulchen Stoppel: nur bei Fruechten mit echtem cutState (nicht regrowing)
        if not fruit.regrows and atCut and (fs.stubbleShredLevel or 0) == 0 then
            table.insert(out, "Mulchen")
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
        if self:isPfActive() then
            local pfTask = self:limeTaskPf(field)
            if pfTask ~= nil then
                table.insert(out, pfTask)
            end
        elseif (fs.limeLevel or 0) == 0 then
            table.insert(out, "Kalken")
        end
    end

    -- Steine: fs.stoneLevel taugt nicht (bleibt oft 0 trotz sichtbarer
    -- Steine) -> direkt auf stoneSystem.densityMap polygon-sampeln.
    if field ~= nil and self:fieldHasStones(field) then
        table.insert(out, "Steine")
    end

    -- Schwadläden auf dem Feld (Stroh, Gras, Heu) via Density-Map-Sampling
    if field ~= nil then
        local windrows = self:sampleWindrowsForField(field)
        for _, label in ipairs(windrows) do
            table.insert(out, label)
        end
    end

    return out
end
