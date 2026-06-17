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
-- lappen). Liefert detected = { {cropIndex, growth}, ... } -- pro Kultur ueber
-- Schwelle mit ihrer dominanten Growth-Stufe.
function MyTodos:samplePaddyCrops(plot, crops)
    if FSDensityMapUtil == nil
            or type(FSDensityMapUtil.getFruitTypeIndexAtWorldPos) ~= "function" then
        return {}
    end
    local bb = plot.bbox
    local fid = plot.farmlandId
    local spanX, spanZ = bb.maxX - bb.minX, bb.maxZ - bb.minZ
    local maxDim = math.max(spanX, spanZ, 1)
    local step = math.max(4, maxDim / MyTodos.PADDY_GRID_MAX)

    local canFarmland = g_farmlandManager ~= nil
        and type(g_farmlandManager.getFarmlandIdAtWorldPosition) == "function"

    local tally = {}     -- cropIndex -> { [growth]=count }
    local cropHits = {}  -- cropIndex -> total count
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
                    tally[fi] = tally[fi] or {}
                    tally[fi][g] = (tally[fi][g] or 0) + 1
                    cropHits[fi] = (cropHits[fi] or 0) + 1
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
    return detected
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

-- Scan-Einstieg. Liefert eine Liste von HUD-Eintraegen im selben Schema wie
-- scanFields ({fieldId, task, primary, parallel, actionable, iconFile}).
-- Wird aus scanFields aufgerufen und in self.fieldTasks gemerged.
function MyTodos:scanPaddies(verbose)
    self.paddyOwnedCount = 0
    local out = {}
    if self.farmId == nil then return out end

    local crops = self:_resolvePaddyCrops()
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
    if verbose then
        Logging.info("[MyTodos] paddies: %d plot(s) scanned, %d real paddy/orchard(s), %d task-entries",
            #plots, realPaddies, #out)
        for _, t in ipairs(out) do
            Logging.info("[MyTodos]   paddy %s -> %s", tostring(t.fieldId), t.task)
        end
    end
    return out
end
