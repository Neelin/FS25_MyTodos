--
-- MyTodos / Paddies
--
-- Kulturen die auf einem eigenen Grundstueck (Farmland) wachsen, fuer das
-- FS25 KEIN Field-Objekt in g_fieldManager:getFields() anlegt:
--   - Reis-Paddies (Terrain mit fieldType=1 bemalt)
--   - mehrjaehrige Kulturen wie Trauben/Oliven (auf owned Farmland gepflanzt)
-- Die normale Field-Discovery (collectOwnedFields) sieht solche Flaechen
-- nicht. Dieses Modul findet sie ueber den FarmlandManager (owned Farmland
-- OHNE zugehoeriges Field) und leitet pro erkannter Kultur eine Aufgabe ab.
--
-- Tiefendoku im mempalace (Wing fs25_mytodos, Drawer "Reis/Trauben/Oliven-
-- Subsystem aufgeloeste API"). WICHTIG: Density-Map-Handles (entry.map) sind
-- Runtime-Node-IDs -- jede Session frisch ueber den densityMaps-Key aufloesen,
-- NIE cachen/persistieren (siehe mempalace-Gotcha-Drawer).
--

-- Kulturen die wir grundstuecks-basiert behandeln. Indizes werden zur Laufzeit
-- per Name aufgeloest (variieren je nach Map/Mod). Saebar vs. mehrjaehrig wird
-- aus fruit.isCultivationAllowed gelesen, nicht hier hartkodiert.
MyTodos.PADDY_CROP_NAMES = { "RICE", "RICELONGGRAIN", "GRAPE", "OLIVE" }

-- fieldType-Wert fuer Reis-Paddy-Boden (map fieldGround.xml: <rice value="1"/>).
MyTodos.PADDY_FIELDTYPE_RICE = 1

-- Schwellen gegen Rand-/Damm-Rauschen (z.B. das Gras auf den Paddy-Daemmen).
MyTodos.PADDY_MIN_GRID_POINTS = 6      -- absolute Mindest-Trefferzahl je Kultur
MyTodos.PADDY_MIN_FRACTION = 0.05      -- bzw. 5% der Grundstuecks-Sample-Punkte
MyTodos.PADDY_FIELDTYPE_MIN_AREA = 200 -- Pixel rice-Boden fuer "leere Paddy"-Task
MyTodos.PADDY_GRID_MAX = 24            -- max NxN Sample-Punkte je Grundstueck
-- Reihen-Kulturen (Trauben/Oliven): dichter sampeln (Reben stehen in schmalen
-- Reihen mit Luecken) und Ernte ueber Pixel-ANWESENHEIT statt dominanter Stufe.
MyTodos.PERENNIAL_GRID_MAX = 36
MyTodos.PERENNIAL_HARVEST_MIN_POINTS = 5
-- Duengen/Kalken bei Mehrjaehrigen: Anteil der Feldflaeche, der unterversorgt
-- sein muss (gegen Rand-Pixel-Rauschen). Wichtig weil das fieldState-Aggregat
-- bei gemischt gepflegten Feldern (Trauben ged., Oliven nicht) den dominanten
-- Wert meldet und die unterversorgte Haelfte verschluckt -> wir sampeln direkt.
MyTodos.PERENNIAL_SUPPLY_MIN_FRACTION = 0.10
-- Mindest-Rasterpunkte je Kultur, damit sie als eigene "Teilflaeche" zaehlt
-- (filtert winzige Patches/Rand-Rauschen bei der Per-Kultur-Aufteilung).
MyTodos.PERENNIAL_MIN_CROP_POINTS = 6

-- Aufloesung der Kultur-Namen -> { [fruitIndex] = {index, name, fruit, sowable} }.
function MyTodos:_resolvePaddyCrops()
    local crops = {}
    if g_fruitTypeManager == nil then return crops end
    for _, name in ipairs(MyTodos.PADDY_CROP_NAMES) do
        local ft = nil
        if type(g_fruitTypeManager.getFruitTypeByName) == "function" then
            ft = g_fruitTypeManager:getFruitTypeByName(name)
        end
        if ft == nil and FruitType ~= nil and FruitType[name] ~= nil then
            ft = g_fruitTypeManager:getFruitTypeByIndex(FruitType[name])
        end
        if ft ~= nil and ft.index ~= nil then
            crops[ft.index] = {
                index = ft.index, name = name, fruit = ft,
                sowable = ft.isCultivationAllowed == true,
            }
        end
    end
    return crops
end

-- Findet den fieldType-Density-Layer-Eintrag (rice=value 1) ueber seinen
-- .key. Handle steht auf .map (Runtime-ID!). Liefert den Eintrag oder nil.
function MyTodos:_findFieldTypeMap()
    local fgs = g_currentMission and g_currentMission.fieldGroundSystem
    if fgs == nil or type(fgs.densityMaps) ~= "table" then return nil end
    for _, v in pairs(fgs.densityMaps) do
        if type(v) == "table" and type(v.key) == "string"
                and v.key:lower():find("fieldtype") and v.map ~= nil then
            return v
        end
    end
    return nil
end

-- Baut den fieldType-Modifier + rice-Filter (jede Session frisch, Handle ist
-- Runtime). Liefert mod, filter -- oder nil, nil wenn nicht verfuegbar.
function MyTodos:_buildRiceGroundSampler()
    local entry = self:_findFieldTypeMap()
    if entry == nil or DensityMapModifier == nil or DensityMapFilter == nil
            or g_currentMission == nil or g_currentMission.terrainRootNode == nil then
        return nil, nil
    end
    local ok, mod = pcall(DensityMapModifier.new, entry.map,
        entry.firstChannel or 0, entry.numChannels or 1,
        g_currentMission.terrainRootNode)
    if not ok or mod == nil then
        Logging.info("[MyTodos] paddy: fieldType modifier build failed: %s", tostring(mod))
        return nil, nil
    end
    local filter = DensityMapFilter.new(mod)
    filter:setValueCompareParams(DensityValueCompareType.EQUAL, MyTodos.PADDY_FIELDTYPE_RICE)
    return mod, filter
end

-- Generischer DensityMapModifier auf einen fieldGround-Layer, gefunden ueber
-- einen Teilstring seines .key (z.B. "spraylevel", "limelevel"). Handle (.map)
-- ist Runtime -> jede Session frisch. Liefert mod, maxValue -- oder nil, 0.
function MyTodos:_buildGroundLayerSampler(keySubstr)
    local fgs = g_currentMission and g_currentMission.fieldGroundSystem
    if fgs == nil or type(fgs.densityMaps) ~= "table"
            or DensityMapModifier == nil or DensityMapFilter == nil
            or g_currentMission.terrainRootNode == nil then
        return nil, 0
    end
    for _, v in pairs(fgs.densityMaps) do
        if type(v) == "table" and type(v.key) == "string"
                and v.key:lower():find(keySubstr) and v.map ~= nil then
            local ok, mod = pcall(DensityMapModifier.new, v.map,
                v.firstChannel or 0, v.numChannels or 1, g_currentMission.terrainRootNode)
            if ok and mod ~= nil then return mod, v.maxValue or 0 end
            return nil, 0
        end
    end
    return nil, 0
end

-- rice-Boden-Flaeche (fieldType==1) im bbox eines Grundstuecks. Pixel-Einheit.
function MyTodos:_riceGroundArea(ftMod, ftFilter, bb)
    if ftMod == nil or ftFilter == nil then return 0 end
    ftMod:clearPolygonPoints()
    ftMod:addPolygonPointWorldCoords(bb.minX, bb.minZ)
    ftMod:addPolygonPointWorldCoords(bb.maxX, bb.minZ)
    ftMod:addPolygonPointWorldCoords(bb.maxX, bb.maxZ)
    ftMod:addPolygonPointWorldCoords(bb.minX, bb.maxZ)
    local _, area, _ = ftMod:executeGet(ftFilter)
    return area or 0
end

-- Owned Farmlands OHNE Field-Objekt mit brauchbarer boundingBox. Das schliesst
-- auch reine Hof-/Bau-Grundstuecke ein -- die filtern sich spaeter ueber die
-- Crop-Erkennung selbst raus (kein Crop -> keine Task).
function MyTodos:collectPaddyFarmlands(farmId)
    local out = {}
    if g_farmlandManager == nil or type(g_farmlandManager.farmlands) ~= "table" then
        return out
    end
    local fieldFarmlandIds = {}
    if g_fieldManager ~= nil then
        for _, field in pairs(g_fieldManager:getFields()) do
            if field.farmland ~= nil and field.farmland.id ~= nil then
                fieldFarmlandIds[field.farmland.id] = true
            end
        end
    end
    for id, fl in pairs(g_farmlandManager.farmlands) do
        if type(id) == "number" and not fieldFarmlandIds[id]
                and g_farmlandManager:getFarmlandOwner(id) == farmId then
            local bb = fl.boundingBox
            if type(bb) == "table" and bb.minX ~= nil and bb.maxX ~= nil
                    and bb.minZ ~= nil and bb.maxZ ~= nil then
                table.insert(out, { farmlandId = id, farmland = fl, bbox = bb })
            end
        end
    end
    return out
end

-- Grid-Sampling der Fruchtflaeche eines Grundstuecks. Nur Punkte die wirklich
-- auf DIESEM Grundstueck liegen werden gezaehlt (bbox kann Nachbarn ueber-
-- lappen). growthState 0 wird IGNORIERT -- das ist "keine Foliage an diesem
-- Pixel" (zwischen Reben-Reihen bei Trauben/Oliven, oder kahler Boden), sonst
-- dominiert bei Reihen-Kulturen die Luecke.
-- Liefert: detected = {{cropIndex, growth(dominant nonzero)}, ...} (Kulturen
-- ueber Flaechen-Schwelle), tally = {[cropIndex]={[growth]=count}} (roh, >0),
-- onPlot = Anzahl Sample-Punkte auf dem Grundstueck.
-- gridMax optional (Default PADDY_GRID_MAX) -- Reihen-Kulturen brauchen dichter.
function MyTodos:samplePaddyCrops(plot, crops, gridMax)
    if FSDensityMapUtil == nil
            or type(FSDensityMapUtil.getFruitTypeIndexAtWorldPos) ~= "function" then
        return {}, {}, 0
    end
    local bb = plot.bbox
    local fid = plot.farmlandId
    local spanX, spanZ = bb.maxX - bb.minX, bb.maxZ - bb.minZ
    local maxDim = math.max(spanX, spanZ, 1)
    local step = math.max(2, maxDim / (gridMax or MyTodos.PADDY_GRID_MAX))

    local canFarmland = g_farmlandManager ~= nil
        and type(g_farmlandManager.getFarmlandIdAtWorldPosition) == "function"

    local tally = {}     -- cropIndex -> { [growth]=count }
    local cropHits = {}  -- cropIndex -> total count (growth > 0)
    local onPlot = 0

    local x = bb.minX
    while x <= bb.maxX do
        local z = bb.minZ
        while z <= bb.maxZ do
            local here = true
            if canFarmland then
                local ok, pid = pcall(g_farmlandManager.getFarmlandIdAtWorldPosition,
                    g_farmlandManager, x, z)
                here = ok and pid == fid
            end
            if here then
                onPlot = onPlot + 1
                local ok, fi, gs = pcall(FSDensityMapUtil.getFruitTypeIndexAtWorldPos, x, z)
                if ok and type(fi) == "number" and crops[fi] ~= nil then
                    local g = gs or 0
                    if g > 0 then
                        tally[fi] = tally[fi] or {}
                        tally[fi][g] = (tally[fi][g] or 0) + 1
                        cropHits[fi] = (cropHits[fi] or 0) + 1
                    end
                end
            end
            z = z + step
        end
        x = x + step
    end

    local minPoints = math.max(MyTodos.PADDY_MIN_GRID_POINTS,
        math.floor(onPlot * MyTodos.PADDY_MIN_FRACTION))
    local detected = {}
    for ci, growths in pairs(tally) do
        if (cropHits[ci] or 0) >= minPoints then
            local bestG, bestC = 0, -1
            for g, c in pairs(growths) do
                if c > bestC then bestC = c; bestG = g end
            end
            table.insert(detected, { cropIndex = ci, growth = bestG })
        end
    end
    return detected, tally, onPlot
end

-- Task pro erkannter Kultur. Wiederverwendet die l10n-Keys der Field-Logik.
-- Liefert text, actionable -- oder nil (passiv: nur wachsend, ausblenden).
function MyTodos:derivePaddyTask(crop, growth)
    local fruit = crop.fruit
    local name = self:fruitName(fruit)
    local g = growth or 0
    local minHarvest = fruit.minHarvestingGrowthState
    local maxHarvest = fruit.maxHarvestingGrowthState
    local withered = fruit.witheredState

    if withered ~= nil and g == withered then
        return self:t("myTodos_fruit_withered", name), true
    end
    if minHarvest ~= nil and maxHarvest ~= nil and g >= minHarvest and g <= maxHarvest then
        return self:t("myTodos_fruit_harvest", name), true
    end
    -- Abgeerntet (cutState): saebare Kulturen (Reis) -> neu saeen; mehrjaehrige
    -- (Trauben/Oliven) regrowen selbst -> passiv, ausblenden.
    if type(fruit.cutStates) == "table" and fruit.cutStates[g] then
        if crop.sowable then
            return self:t("myTodos_fruit_sow", name), true
        end
        return nil
    end
    -- wachsend -> passiv
    return nil
end

-- Crop-Aufloesung gecacht (FruitType-Indizes sind pro Session stabil). Wird
-- haeufig aufgerufen (pro Feld in deriveFieldTask) -> nicht jedes Mal neu
-- per Name aufloesen. Cache erst setzen wenn g_fruitTypeManager Ergebnisse
-- liefert (sonst frueh ein leerer Cache).
function MyTodos:_paddyCropsCached()
    if self._paddyCropsCache ~= nil then return self._paddyCropsCache end
    local c = self:_resolvePaddyCrops()
    if next(c) ~= nil then self._paddyCropsCache = c end
    return c
end

-- Ist diese Frucht eine mehrjaehrige Kultur, die das Perennial-Subsystem auf
-- ECHTEN Feldern per Density-Sampling behandelt (Trauben/Oliven)? Erkennung:
-- in unserer Crop-Liste UND nicht saebar (isCultivationAllowed=false). Reis
-- (saebar) und andere non-cultivatable Fruechte (z.B. Pappel) bleiben beim
-- normalen Aggregat-Pfad.
function MyTodos:_isPerennialFieldCrop(fruitIndex)
    if type(fruitIndex) ~= "number" or fruitIndex <= 0 then return false end
    local c = self:_paddyCropsCached()[fruitIndex]
    return c ~= nil and c.sowable == false
end

-- Ist dieses Feld (per fieldState) ein Reben-/Oliven-Feld? Robust gegen das
-- Problem, dass nach der Ernte / bei Reihen-Luecken fruitTypeIndex auf 0 faellt:
-- dann zieht lastFruitTypeIndex (bleibt auf der mehrjaehrigen Kultur stehen).
-- Prioritaet: aktueller Crop wenn bekannt (>0) -- so wird ein Feld, das wirklich
-- auf eine einjaehrige Frucht umgestellt wurde, NICHT faelschlich als Reben-Feld
-- behandelt; nur bei leerem Aggregat faellt es auf den letzten Crop zurueck.
function MyTodos:_fieldIsPerennial(fs)
    if fs == nil then return false end
    local cur = fs.fruitTypeIndex or 0
    if cur > 0 then
        return self:_isPerennialFieldCrop(cur)
    end
    return self:_isPerennialFieldCrop(fs.lastFruitTypeIndex or 0)
end

-- bbox {minX,minZ,maxX,maxZ} aus den Feld-Polygon-Knoten (Engine-Node-IDs ->
-- Weltkoords). Nil wenn kein Polygon.
function MyTodos:_fieldBBox(field)
    local pp = field.polygonPoints
    if type(pp) ~= "table" or #pp == 0 then return nil end
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for _, nodeId in ipairs(pp) do
        local x, _, z = getWorldTranslation(nodeId)
        if x < minX then minX = x end
        if x > maxX then maxX = x end
        if z < minZ then minZ = z end
        if z > maxZ then maxZ = z end
    end
    if minX > maxX then return nil end
    return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

-- Liest den ~Wert eines fieldGround-Layers (sprayLevel/limeLevel) an einem
-- Weltpunkt ueber eine kleine Box. Liefert den Durchschnitts-Level oder nil.
-- Fuer die Per-Punkt-Klassifikation "ist dieser Pixel gepflegt".
function MyTodos:_readGroundLevelAt(mod, x, z)
    if mod == nil then return nil end
    local r = 0.5
    mod:clearPolygonPoints()
    mod:addPolygonPointWorldCoords(x - r, z - r)
    mod:addPolygonPointWorldCoords(x + r, z - r)
    mod:addPolygonPointWorldCoords(x + r, z + r)
    mod:addPolygonPointWorldCoords(x - r, z + r)
    local sum, area = mod:executeGet()
    if area == nil or area == 0 then return nil end
    return sum / area
end

-- Scannt ein mehrjaehriges Feld PRO KULTUR. Raster ueber das Feld-bbox (auf das
-- Grundstueck begrenzt); je Punkt Frucht+Growth UND -- bei Vanilla -- Spray-/
-- Kalk-Level am selben Punkt. Jede Kultur (Trauben/Oliven) wird so als eigene
-- Teilflaeche behandelt: eigene Ernte + eigenes Duengen/Kalken, auch wenn
-- mehrere auf EINER Feld-ID liegen. Liefert HUD-Eintraege (eine Zeile je Kultur
-- mit offener Aufgabe), Label crop-praefixiert ("Trauben: ...", "Oliven: ...").
-- Unter PF: Ernte per Raster, Duengen/Kalken feldweit via fertilizerTaskPf/
-- limeTaskPf (N-Ziel je Kultur; pH einmal an die erste Zeile).
function MyTodos:_scanPerennialField(field, fid, crops, samplers, verbose)
    local out = {}
    local bbox = self:_fieldBBox(field)
    if bbox == nil then return out end
    if FSDensityMapUtil == nil
            or type(FSDensityMapUtil.getFruitTypeIndexAtWorldPos) ~= "function" then
        return out
    end
    local flId = field.farmland.id
    local fs = field.fieldState
    local pfActive = self.precisionFarming == "active"
    local canFarmland = g_farmlandManager ~= nil
        and type(g_farmlandManager.getFarmlandIdAtWorldPosition) == "function"
    local sprayMod = samplers.sprayMod
    local limeMod = samplers.limeMod
    local sprayMax = samplers.sprayMax or 2

    -- Raster -> Per-Kultur-Statistik.
    local stat = {}  -- [ci] = { total, gh = {growth=count}, sprayZero, limeZero }
    local step = math.max(2,
        math.max(bbox.maxX - bbox.minX, bbox.maxZ - bbox.minZ, 1) / MyTodos.PERENNIAL_GRID_MAX)
    local x = bbox.minX
    while x <= bbox.maxX do
        local z = bbox.minZ
        while z <= bbox.maxZ do
            local here = true
            if canFarmland then
                local ok, pid = pcall(g_farmlandManager.getFarmlandIdAtWorldPosition,
                    g_farmlandManager, x, z)
                here = ok and pid == flId
            end
            if here then
                local ok, fi, gs = pcall(FSDensityMapUtil.getFruitTypeIndexAtWorldPos, x, z)
                if ok and type(fi) == "number" and crops[fi] ~= nil and (gs or 0) > 0 then
                    local s = stat[fi]
                    if s == nil then
                        s = { total = 0, gh = {}, sprayHist = {}, sprayReads = 0,
                              limeHist = {}, limeReads = 0 }
                        stat[fi] = s
                    end
                    s.total = s.total + 1
                    s.gh[gs] = (s.gh[gs] or 0) + 1
                    -- Spray-/Kalk-Level am selben Punkt (nur auf der Crop-Flaeche
                    -- -> Reihen-Luecken/Headlands fliessen NICHT ein).
                    if not pfActive then
                        local sv = self:_readGroundLevelAt(sprayMod, x, z)
                        if sv ~= nil then
                            local lvl = math.floor(sv + 0.5)
                            s.sprayHist[lvl] = (s.sprayHist[lvl] or 0) + 1
                            s.sprayReads = s.sprayReads + 1
                        end
                        local lv = self:_readGroundLevelAt(limeMod, x, z)
                        if lv ~= nil then
                            local lvl = math.floor(lv + 0.5)
                            s.limeHist[lvl] = (s.limeHist[lvl] or 0) + 1
                            s.limeReads = s.limeReads + 1
                        end
                    end
                end
            end
            z = z + step
        end
        x = x + step
    end

    if next(stat) == nil then
        if verbose then
            Logging.info("[MyTodos]   perennial field %s: no crop foliage sampled", tostring(fid))
        end
        return out
    end
    if self:isFieldIgnored(fid) then return out end

    local frac = MyTodos.PERENNIAL_SUPPLY_MIN_FRACTION
    local pfLime = pfActive and self:limeTaskPf(field) or nil
    local firstEmitted = true

    -- stabile Reihenfolge nach Fruchtindex
    local cis = {}
    for ci in pairs(stat) do table.insert(cis, ci) end
    table.sort(cis)

    for _, ci in ipairs(cis) do
        local s = stat[ci]
        if s.total >= MyTodos.PERENNIAL_MIN_CROP_POINTS then
            local crop = crops[ci]
            local name = self:fruitName(crop.fruit)
            local minH, maxH = crop.fruit.minHarvestingGrowthState, crop.fruit.maxHarvestingGrowthState
            local harvestPx = 0
            if minH ~= nil and maxH ~= nil then
                for g, c in pairs(s.gh) do
                    if g >= minH and g <= maxH then harvestPx = harvestPx + c end
                end
            end

            -- Spray-Verteilung dieser Kultur auswerten: Anteil unter Max
            -- (Duengen, bis voll) + niedrigste vorhandene Stufe fuers Label.
            local sprayUnder, sprayMin = 0, nil
            for lvl, c in pairs(s.sprayHist) do
                if sprayMin == nil or lvl < sprayMin then sprayMin = lvl end
                if lvl < sprayMax then sprayUnder = sprayUnder + c end
            end
            local limeZero = s.limeHist[0] or 0

            -- Pflege-Fragmente (ohne Crop-Name; der kommt ans primary).
            local care = {}
            if pfActive then
                local fert = self:fertilizerTaskPf(field, fs, crop.fruit)
                if fert ~= nil then table.insert(care, fert) end
                if firstEmitted and pfLime ~= nil then table.insert(care, pfLime) end
            else
                if s.sprayReads > 0 and sprayUnder / s.sprayReads >= frac then
                    table.insert(care, self:t("myTodos_task_fertilize", sprayMin or 0, sprayMax))
                end
                if s.limeReads > 0 and limeZero / s.limeReads >= frac then
                    table.insert(care, self:t("myTodos_task_lime"))
                end
            end

            if verbose then
                local function histStr(h)
                    local ks = {}
                    for k in pairs(h) do table.insert(ks, k) end
                    table.sort(ks)
                    local parts = {}
                    for _, k in ipairs(ks) do table.insert(parts, string.format("%d:%d", k, h[k])) end
                    return #parts > 0 and table.concat(parts, " ") or "-"
                end
                Logging.info("[MyTodos]   perennial %s/%s: total=%d harvestPx=%d spray[%s] lime[%s]",
                    tostring(fid), name, s.total, harvestPx,
                    histStr(s.sprayHist), histStr(s.limeHist))
            end

            -- Zeile bauen: Ernten hat Vorrang als primary, sonst erste Pflege.
            -- Label immer crop-praefixiert, damit die Kulturen getrennt lesbar
            -- sind (mehrere Zeilen auf derselben Feld-ID).
            local primary, actionable, parallel
            if harvestPx >= MyTodos.PERENNIAL_HARVEST_MIN_POINTS then
                primary = self:t("myTodos_fruit_harvest", name)  -- "Trauben: Ernten"
                actionable = true
                parallel = care
            elseif #care > 0 then
                primary = string.format("%s: %s", name, care[1])
                actionable = false
                parallel = {}
                for k = 2, #care do table.insert(parallel, care[k]) end
            end

            if primary ~= nil then
                local task = primary
                if #parallel > 0 then
                    task = string.format("%s  [+ %s]", primary, table.concat(parallel, ", "))
                end
                table.insert(out, {
                    fieldId = fid, task = task, primary = primary,
                    parallel = parallel, actionable = actionable,
                    iconFile = self:_fruitIconFile(ci),
                })
                firstEmitted = false
            end
        end
    end
    return out
end

-- Scan-Einstieg. Liefert eine Liste von HUD-Eintraegen im selben Schema wie
-- scanFields ({fieldId, task, primary, parallel, actionable, iconFile}).
-- Wird aus scanFields aufgerufen und in self.fieldTasks gemerged.
function MyTodos:scanPaddies(verbose)
    self.paddyOwnedCount = 0
    local out = {}
    if self.farmId == nil then return out end

    local crops = self:_paddyCropsCached()
    if next(crops) == nil then return out end
    local riceIndex = nil
    for ci, c in pairs(crops) do
        if c.name == "RICE" then riceIndex = ci end
    end

    local ftMod, ftFilter = self:_buildRiceGroundSampler()
    local plots = self:collectPaddyFarmlands(self.farmId)
    local realPaddies = 0
    local plotIds = {}

    for _, plot in ipairs(plots) do
        local fid = plot.farmlandId
        -- Sampling IMMER (auch fuer ignorierte Plots), damit echte Paddies in
        -- der Settings-Liste auftauchen und wieder einblendbar sind. Reine Hof-/
        -- Bau-Grundstuecke (kein Crop, kein rice-Boden) fallen hier raus.
        local detected = self:samplePaddyCrops(plot, crops)
        local riceGround = self:_riceGroundArea(ftMod, ftFilter, plot.bbox)
        local hasCropOrGround = (#detected > 0)
            or (riceIndex ~= nil and riceGround >= MyTodos.PADDY_FIELDTYPE_MIN_AREA)

        if hasCropOrGround then
            realPaddies = realPaddies + 1
            table.insert(plotIds, fid)
        end

        if hasCropOrGround and not self:isFieldIgnored(fid) then
            local sawRice = false
            for _, d in ipairs(detected) do
                if d.cropIndex == riceIndex then sawRice = true end
                local primary, actionable = self:derivePaddyTask(crops[d.cropIndex], d.growth)
                if primary ~= nil then
                    table.insert(out, {
                        fieldId = fid, task = primary, primary = primary,
                        parallel = {}, actionable = actionable == true,
                        iconFile = self:_fruitIconFile(d.cropIndex),
                    })
                end
            end
            -- Leere/abgegrubberte Reis-Paddy: rice-Boden da, aber keine Reis-
            -- Frucht gesampelt -> "Reis saeen".
            if not sawRice and riceIndex ~= nil
                    and riceGround >= MyTodos.PADDY_FIELDTYPE_MIN_AREA then
                local name = self:fruitName(crops[riceIndex].fruit)
                local label = self:t("myTodos_fruit_sow", name)
                table.insert(out, {
                    fieldId = fid, task = label, primary = label,
                    parallel = {}, actionable = true,
                    iconFile = self:_fruitIconFile(riceIndex),
                })
            end
        end
    end

    self.paddyOwnedCount = realPaddies
    self.paddyPlotIds = plotIds

    -- Mehrjaehrige Kulturen (Trauben/Oliven) auf ECHTEN Feldern. Das fieldState-
    -- Aggregat ist hier unbrauchbar (sieht nur EINE Frucht + nur einen spray/
    -- lime-Wert, verschluckt gemischte/teil-gepflegte Flaechen). Daher
    -- _scanPerennialField: Raster PRO KULTUR (Frucht + Spray/Kalk je Punkt) ->
    -- jede Kultur als eigene Teilflaeche mit eigenem Ernten/Duengen/Kalken, auch
    -- wenn mehrere auf EINER Feld-ID liegen. Diese Felder werden im normalen Pfad
    -- uebersprungen (deriveFieldTask perennial-check) -> kein Doppel. Ignore +
    -- Settings-Liste laufen schon ueber den normalen Field-Pfad (echte Felder).
    local perennialFields = 0
    if g_fieldManager ~= nil and g_farmlandManager ~= nil then
        -- Spray-/Kalk-Density-Sampler einmal bauen (Handles runtime). Fuer
        -- Duengen/Kalken direkt im Feld-Polygon, statt dem truegerischen Aggregat.
        local sprayMod, sprayMax = self:_buildGroundLayerSampler("spraylevel")
        local limeMod = self:_buildGroundLayerSampler("limelevel")
        local careSamplers = { sprayMod = sprayMod, sprayMax = sprayMax, limeMod = limeMod }
        for _, field in pairs(g_fieldManager:getFields()) do
            local fs = field.fieldState
            local fl = field.farmland
            if fs ~= nil and fl ~= nil and fl.id ~= nil
                    and self:_fieldIsPerennial(fs)
                    and g_farmlandManager:getFarmlandOwner(fl.id) == self.farmId then
                -- Anzeige-Nummer wie collectOwnedFields: farmland.name -> id.
                local fid
                local fname = fl.name
                if type(fname) == "string" and fname ~= "" then
                    fid = tonumber(fname) or fname
                end
                if fid == nil then fid = fl.id end

                perennialFields = perennialFields + 1
                local entries = self:_scanPerennialField(
                    field, fid, crops, careSamplers, verbose)
                for _, e in ipairs(entries) do
                    table.insert(out, e)
                end
            end
        end
    end

    if verbose then
        Logging.info("[MyTodos] paddies: %d plot(s), %d real; perennial fields: %d; %d task-entries",
            #plots, realPaddies, perennialFields, #out)
        for _, t in ipairs(out) do
            Logging.info("[MyTodos]   -> %s: %s", tostring(t.fieldId), t.task)
        end
    end
    return out
end
