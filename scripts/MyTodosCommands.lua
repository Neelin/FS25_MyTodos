--
-- MyTodos / Commands
--
-- Alle mt*-Konsolenbefehle. Tooling fuer Live-Diagnose im Spiel:
-- Settings, Rescan, fieldState-Dump, Density-Map-Probes, neuer
-- Husbandry-Probe.
--

-- Loest das arg eines mt*-Befehls auf die User-facing Feldnummer auf.
-- Quelle ist field.farmland.name (das ist die Zahl die der Spieler auf
-- der Karte sieht; siehe CLAUDE.md "Field-Discovery"). Tabellen-Key von
-- g_fieldManager:getFields() ist eine interne ID und stimmt mit der
-- User-Sicht NICHT zwingend ueberein -- darum wird der hier bewusst NICHT
-- als Fallback genommen, damit die Eingabe immer das tut was der Nutzer
-- erwartet.
function MyTodos:resolveFieldByUserNumber(arg)
    if g_fieldManager == nil then return nil end
    local fields = g_fieldManager:getFields()
    if fields == nil then return nil end
    local argStr = tostring(arg)
    local argNum = tonumber(arg)
    for _, field in pairs(fields) do
        local fname = field.farmland and field.farmland.name
        if fname ~= nil then
            local fnameStr = tostring(fname)
            if argStr == fnameStr or (argNum ~= nil and argNum == tonumber(fnameStr)) then
                return field
            end
        end
    end
    return nil
end

addConsoleCommand("mtSettings", "Toggle MyTodos settings panel",
    "consoleSettingsCmd", MyTodos)
function MyTodos:consoleSettingsCmd()
    self:onActionToggleSettings()
    return string.format("MyTodos settings: %s", tostring(self.settingsOpen))
end

-- Hilfsfunktion fuer mtIgnore/mtUnignore: nimmt user-input, sucht das Feld,
-- liefert die kanonische fieldId (number wenn farmland.name numerisch ist,
-- sonst string -- analog collectOwnedFields).
function MyTodos:_resolveIgnoreFieldId(arg)
    local field = self:resolveFieldByUserNumber(arg)
    if field == nil then
        -- Kein Field gefunden: koennte ein Paddy/Perennial-Grundstueck sein
        -- (owned Farmland OHNE Field-Objekt -- siehe MyTodosPaddies.lua). Die
        -- HUD-/Ignore-ID solcher Eintraege ist die farmland.id direkt.
        local n = tonumber(arg)
        if n ~= nil and g_farmlandManager ~= nil
                and type(g_farmlandManager.farmlands) == "table"
                and g_farmlandManager.farmlands[n] ~= nil
                and g_farmlandManager:getFarmlandOwner(n) == self.farmId then
            return n
        end
        return nil
    end
    local fname = field.farmland and field.farmland.name
    if type(fname) == "string" and fname ~= "" then
        return tonumber(fname) or fname
    end
    return tonumber(arg) or tostring(arg)
end

addConsoleCommand("mtIgnore",
    "Mark a field as ignored (no tasks in HUD). Usage: mtIgnore <fieldNumber>",
    "consoleIgnoreCmd", MyTodos)
function MyTodos:consoleIgnoreCmd(arg)
    if arg == nil or arg == "" then return "Usage: mtIgnore <fieldNumber>" end
    if self.farmId == nil then return "MyTodos: not ready (no farmId yet)" end
    local fid = self:_resolveIgnoreFieldId(arg)
    if fid == nil then
        return string.format("Field %s not found", tostring(arg))
    end
    self:setFieldIgnored(fid, true)
    return string.format("MyTodos: field %s ignored", tostring(fid))
end

addConsoleCommand("mtUnignore",
    "Un-ignore a field. Usage: mtUnignore <fieldNumber>",
    "consoleUnignoreCmd", MyTodos)
function MyTodos:consoleUnignoreCmd(arg)
    if arg == nil or arg == "" then return "Usage: mtUnignore <fieldNumber>" end
    if self.farmId == nil then return "MyTodos: not ready (no farmId yet)" end
    local fid = self:_resolveIgnoreFieldId(arg)
    if fid == nil then
        return string.format("Field %s not found", tostring(arg))
    end
    self:setFieldIgnored(fid, false)
    return string.format("MyTodos: field %s un-ignored", tostring(fid))
end

addConsoleCommand("mtRescan", "Force MyTodos to rescan fields now",
    "consoleRescanCmd", MyTodos)
function MyTodos:consoleRescanCmd()
    if self.farmId == nil then
        return "MyTodos: not ready (no farmId yet)"
    end
    self:scanFields(true)
    return string.format("MyTodos: rescanned %d field(s)", #self.fieldTasks)
end

addConsoleCommand("mtDump", "Dump fieldState of a specific field. Usage: mtDump <fieldNumber>",
    "consoleDumpCmd", MyTodos)
function MyTodos:consoleDumpCmd(arg)
    if arg == nil or arg == "" then
        return "Usage: mtDump <fieldNumber> (the number you see on the map)"
    end
    if g_fieldManager == nil then
        return "g_fieldManager not available"
    end
    local field = self:resolveFieldByUserNumber(arg)
    if field == nil then
        return string.format("Field %s not found (matched against field.farmland.name)", tostring(arg))
    end
    self:dumpKeys(string.format("field.%s.fieldState", tostring(arg)), field.fieldState)
    if field.fieldState ~= nil
            and (field.fieldState.fruitTypeIndex or 0) > 0
            and g_fruitTypeManager ~= nil then
        local fruit = g_fruitTypeManager:getFruitTypeByIndex(field.fieldState.fruitTypeIndex)
        if fruit ~= nil then
            local label = string.format("fruit.%s", tostring(fruit.name))
            self:dumpKeys(label, fruit)
            if type(fruit.growthStateToName) == "table" then
                self:dumpKeys(label .. ".growthStateToName", fruit.growthStateToName)
            end
            if type(fruit.cutStates) == "table" then
                self:dumpKeys(label .. ".cutStates", fruit.cutStates)
            end
        end
    end
    return string.format("Dumped field %s to log", tostring(arg))
end

addConsoleCommand("mtForceUpdate", "Run field:updateState() and dump before/after. Usage: mtForceUpdate <fieldNumber>",
    "consoleForceUpdateCmd", MyTodos)
function MyTodos:consoleForceUpdateCmd(arg)
    if arg == nil or arg == "" then return "Usage: mtForceUpdate <fieldNumber>" end
    if g_fieldManager == nil then return "g_fieldManager not available" end
    local field = self:resolveFieldByUserNumber(arg)
    if field == nil then return string.format("Field %s not found", tostring(arg)) end

    Logging.info("[MyTodos] BEFORE field:updateState():")
    self:dumpKeys(string.format("  field.%s.fieldState", tostring(arg)), field.fieldState)

    if type(field.updateState) ~= "function" then
        return "field:updateState() not available"
    end
    field:updateState()

    Logging.info("[MyTodos] AFTER field:updateState():")
    self:dumpKeys(string.format("  field.%s.fieldState", tostring(arg)), field.fieldState)

    return string.format("Force-updated field %s - check log", tostring(arg))
end

addConsoleCommand("mtProbe", "Probe FS25 field API surface. Usage: mtProbe [fieldNumber]",
    "consoleProbeCmd", MyTodos)
function MyTodos:consoleProbeCmd(arg)
    self:dumpKeys("FieldUtil", FieldUtil)
    self:dumpKeys("FSDensityMapUtil", FSDensityMapUtil)
    self:dumpKeys("FieldDensityMap", FieldDensityMap)
    self:dumpKeys("DensityMapModifier", DensityMapModifier)

    if g_currentMission ~= nil then
        self:dumpKeys("g_currentMission.fieldGroundSystem", g_currentMission.fieldGroundSystem)
    end
    if g_fieldManager ~= nil then
        self:dumpKeys("g_fieldManager", g_fieldManager)
    end

    if arg == nil or arg == "" then
        return "Globals probed. Pass <fieldNumber> to also probe field instance."
    end

    if g_fieldManager == nil then
        return "g_fieldManager not available"
    end
    local field = self:resolveFieldByUserNumber(arg)
    if field == nil then
        return string.format("Field %s not found", tostring(arg))
    end

    -- Felder haben Methoden ueber die Field-Klasse (Metatable)
    local mt = getmetatable(field)
    if mt ~= nil and mt.__index ~= nil then
        self:dumpKeys("field metatable.__index (Field class)", mt.__index)
    end

    -- Versuche bekannte Methoden direkt aufzurufen
    local candidates = {
        "getId", "getOwnerFarmId", "getFarmlandId", "getCenterOfFieldWorldPosition",
        "getFieldStatus", "getStatus", "updateFieldState", "updateState",
    }
    for _, m in ipairs(candidates) do
        if type(field[m]) == "function" then
            local ok, result = pcall(field[m], field)
            Logging.info("[MyTodos] field:%s() ok=%s type=%s value=%s",
                m, tostring(ok), type(result), tostring(result))
        end
    end

    return string.format("Probed field %s - check log", tostring(arg))
end

addConsoleCommand("mtProbeWindrow", "Probe FS25 windrow / fillType API",
    "consoleProbeWindrowCmd", MyTodos)
function MyTodos:consoleProbeWindrowCmd()
    -- 1. FillType global (Konstanten)
    if FillType ~= nil then
        Logging.info("[MyTodos] FillType.STRAW=%s, FillType.GRASS_WINDROW=%s, FillType.DRYGRASS_WINDROW=%s, FillType.HAY=%s",
            tostring(FillType.STRAW),
            tostring(FillType.GRASS_WINDROW),
            tostring(FillType.DRYGRASS_WINDROW),
            tostring(FillType.HAY))
    else
        Logging.info("[MyTodos] FillType global: nil")
    end

    -- 2. fillTypeManager
    if g_fillTypeManager ~= nil then
        self:dumpKeys("g_fillTypeManager", g_fillTypeManager)
        local mt = getmetatable(g_fillTypeManager)
        if mt ~= nil and mt.__index ~= nil then
            self:dumpKeys("g_fillTypeManager.metatable.__index", mt.__index)
        end
        for _, name in ipairs({"STRAW", "GRASS_WINDROW", "DRYGRASS_WINDROW", "HAY"}) do
            local ok, result = pcall(function()
                return g_fillTypeManager:getFillTypeByName(name)
            end)
            if ok and result ~= nil then
                self:dumpKeys("fillType." .. name, result)
            else
                Logging.info("[MyTodos] fillType.%s: nil (ok=%s)", name, tostring(ok))
            end
        end
    else
        Logging.info("[MyTodos] g_fillTypeManager: nil")
    end

    -- 3. densityMapHeightTypeManager (typischer Ort fuer Schuett/Schwad-Daten)
    if g_densityMapHeightTypeManager ~= nil then
        self:dumpKeys("g_densityMapHeightTypeManager", g_densityMapHeightTypeManager)
        local mt = getmetatable(g_densityMapHeightTypeManager)
        if mt ~= nil and mt.__index ~= nil then
            self:dumpKeys("g_densityMapHeightTypeManager.metatable.__index", mt.__index)
        end
        for _, name in ipairs({"STRAW", "GRASS_WINDROW", "DRYGRASS_WINDROW", "HAY"}) do
            local ok, result = pcall(function()
                return g_densityMapHeightTypeManager:getDensityMapHeightTypeByName(name)
            end)
            if ok and result ~= nil then
                self:dumpKeys("heightType." .. name, result)
            else
                Logging.info("[MyTodos] heightType.%s: nil (ok=%s)", name, tostring(ok))
            end
        end
    else
        Logging.info("[MyTodos] g_densityMapHeightTypeManager: nil")
    end

    -- 4. DensityMapHeightUtil (Sampling-Funktionen)
    if DensityMapHeightUtil ~= nil then
        self:dumpKeys("DensityMapHeightUtil", DensityMapHeightUtil)
    else
        Logging.info("[MyTodos] DensityMapHeightUtil: nil")
    end

    -- 5. Alle schwad-faehigen fillTypes auflisten (textureArrayIndex ~= nil).
    --    Damit laesst sich der exakte Name eines modded Schwads (z.B. Luzerne/
    --    Alfalfa) auf der aktuellen Map finden, falls er vom Standard
    --    ALFALFA_WINDROW / DRYALFALFA_WINDROW abweicht. Den Namen dann in
    --    MyTodos.WINDROW_TYPES (MyTodosFields.lua) eintragen.
    if g_fillTypeManager ~= nil and type(g_fillTypeManager.fillTypes) == "table" then
        Logging.info("[MyTodos] --- schwad-faehige fillTypes (textureArrayIndex) ---")
        for _, ft in pairs(g_fillTypeManager.fillTypes) do
            if type(ft) == "table" and ft.textureArrayIndex ~= nil then
                Logging.info("[MyTodos]   %s (index=%s) -> textureArrayIndex=%s",
                    tostring(ft.name), tostring(ft.index), tostring(ft.textureArrayIndex))
            end
        end
    end

    return "Windrow API probe done - check log"
end

addConsoleCommand("mtProbeWindrowAt", "Sample windrow on a field. Usage: mtProbeWindrowAt <fieldNumber>",
    "consoleProbeWindrowAtCmd", MyTodos)
function MyTodos:consoleProbeWindrowAtCmd(arg)
    if arg == nil or arg == "" then return "Usage: mtProbeWindrowAt <fieldNumber>" end
    if g_fieldManager == nil then return "g_fieldManager nil" end
    local field = self:resolveFieldByUserNumber(arg)
    if field == nil then return string.format("Field %s not found", tostring(arg)) end
    if DensityMapHeightUtil == nil then return "DensityMapHeightUtil nil" end

    -- 1. Polygon-Knoten zu Welt-Koordinaten aufloesen
    local pp = field.polygonPoints
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    if type(pp) == "table" then
        Logging.info("[MyTodos] field.polygonPoints len=%d (Node-IDs)", #pp)
        for i, nodeId in ipairs(pp) do
            local x, y, z = getWorldTranslation(nodeId)
            if i <= 3 then
                Logging.info("[MyTodos]   node[%d]=%s -> (%.2f, %.2f, %.2f)",
                    i, tostring(nodeId), x, y, z)
            end
            if x < minX then minX = x end
            if x > maxX then maxX = x end
            if z < minZ then minZ = z end
            if z > maxZ then maxZ = z end
        end
    end
    Logging.info("[MyTodos] real bbox: x=[%.1f..%.1f] z=[%.1f..%.1f] dx=%.1f dz=%.1f",
        minX, maxX, minZ, maxZ, maxX - minX, maxZ - minZ)

    local sx, sz = minX, minZ
    local wx, wz = maxX - minX, 0
    local hx, hz = 0, maxZ - minZ
    local cx = (minX + maxX) / 2
    local cz = (minZ + maxZ) / 2

    -- Terrain-Hoehe am Feld-Mittelpunkt
    local terrainNode = g_currentMission and g_currentMission.terrainRootNode
    local cy = 0
    if terrainNode ~= nil then
        cy = getTerrainHeightAtWorldPos(terrainNode, cx, 0, cz)
    end
    Logging.info("[MyTodos] center=(%.1f, %.1f, %.1f) bbox dx=%.1f dz=%.1f",
        cx, cy, cz, maxX - minX, maxZ - minZ)

    -- 2. DensityMapModifier auf den Type-Channels von terrainDetailHeightId.
    --    Liefert Pixel-genaue Counts pro fillType im Feld-BBox.
    if DensityMapModifier ~= nil and terrainNode ~= nil
            and DensityMapHeightUtil.terrainDetailHeightId ~= nil then
        local mapId = DensityMapHeightUtil.terrainDetailHeightId
        local ok, mod = pcall(DensityMapModifier.new, mapId,
            DensityMapHeightUtil.typeFirstChannel,
            DensityMapHeightUtil.typeNumChannels,
            terrainNode)
        if ok and mod ~= nil then
            -- Polygon-Mode: Punkte aus polygonPoints
            mod:clearPolygonPoints()
            for _, nodeId in ipairs(field.polygonPoints) do
                local x, _, z = getWorldTranslation(nodeId)
                mod:addPolygonPointWorldCoords(x, z)
            end

            local total, area, totalArea = mod:executeGet()
            Logging.info("[MyTodos] type-mod (polygon) no-filter: total=%s area=%s totalArea=%s",
                tostring(total), tostring(area), tostring(totalArea))

            -- Height-Modifier nebenbei probieren
            local hOk, hMod = pcall(DensityMapModifier.new, mapId,
                DensityMapHeightUtil.heightFirstChannel,
                DensityMapHeightUtil.heightNumChannels,
                terrainNode)
            if hOk and hMod ~= nil then
                hMod:clearPolygonPoints()
                for _, nodeId in ipairs(field.polygonPoints) do
                    local x, _, z = getWorldTranslation(nodeId)
                    hMod:addPolygonPointWorldCoords(x, z)
                end
                local hTotal, hArea, hTotalArea = hMod:executeGet()
                Logging.info("[MyTodos] height-mod (polygon) no-filter: total=%s area=%s totalArea=%s",
                    tostring(hTotal), tostring(hArea), tostring(hTotalArea))
                if DensityMapFilter ~= nil then
                    local hf = DensityMapFilter.new(hMod)
                    hf:setValueCompareParams(DensityValueCompareType.GREATER, 0)
                    local hT, hA, hTA = hMod:executeGet(hf)
                    Logging.info("[MyTodos] height-mod GREATER 0: total=%s area=%s totalArea=%s",
                        tostring(hT), tostring(hA), tostring(hTA))
                end
            end

            -- Iteriere komplettes 6-bit-Spektrum (0..63) und logge nur Vorkommen.
            if DensityMapFilter ~= nil then
                for value = 0, 63 do
                    local filter = DensityMapFilter.new(mod)
                    filter:setValueCompareParams(DensityValueCompareType.EQUAL, value)
                    local t2, a2, _ = mod:executeGet(filter)
                    if (a2 or 0) > 0 then
                        Logging.info("[MyTodos] type value=%d: total=%s area=%s", value,
                            tostring(t2), tostring(a2))
                    end
                end
            end

            -- Auch FillType.STRAW-Eintrag dumpen, dort koennte ein interner Index drin sein
            if g_fillTypeManager ~= nil and FillType ~= nil and FillType.STRAW ~= nil then
                local strawFt = g_fillTypeManager.fillTypes[FillType.STRAW]
                if strawFt ~= nil then
                    local mt = getmetatable(strawFt)
                    if mt ~= nil and mt.__index ~= nil then
                        self:dumpKeys("FillType.STRAW.metatable.__index", mt.__index)
                    end
                end
            end
        else
            Logging.info("[MyTodos] DensityMapModifier.new failed: %s", tostring(mod))
        end
    end

    -- 4. getFillTypeAtArea -- liefert vermutlich (fillType, fillLevel) oder so
    if type(DensityMapHeightUtil.getFillTypeAtArea) == "function" then
        local ok, a, b, c, d = pcall(DensityMapHeightUtil.getFillTypeAtArea, sx, sz, wx, wz, hx, hz)
        Logging.info("[MyTodos] getFillTypeAtArea: ok=%s ret1=%s ret2=%s ret3=%s ret4=%s",
            tostring(ok), tostring(a), tostring(b), tostring(c), tostring(d))
    end

    -- 5. getFillLevelAtArea pro fillType
    if type(DensityMapHeightUtil.getFillLevelAtArea) == "function" and FillType ~= nil then
        for _, name in ipairs({"STRAW", "GRASS_WINDROW", "DRYGRASS_WINDROW"}) do
            local idx = FillType[name]
            if idx ~= nil then
                local ok, a, b, c = pcall(DensityMapHeightUtil.getFillLevelAtArea,
                    sx, sz, wx, wz, hx, hz, idx)
                Logging.info("[MyTodos] getFillLevelAtArea(%s=%d): ok=%s ret1=%s ret2=%s ret3=%s",
                    name, idx, tostring(ok), tostring(a), tostring(b), tostring(c))
            end
        end
    end

    return "Sampled - check log"
end

addConsoleCommand("mtProbeWeed", "Probe weed density on a field. Usage: mtProbeWeed <fieldNumber>",
    "consoleProbeWeedCmd", MyTodos)
function MyTodos:consoleProbeWeedCmd(arg)
    if arg == nil or arg == "" then return "Usage: mtProbeWeed <fieldNumber>" end
    if g_fieldManager == nil then return "g_fieldManager nil" end
    local field = self:resolveFieldByUserNumber(arg)
    if field == nil then return string.format("Field %s not found", tostring(arg)) end

    -- Bbox aus polygonPoints
    local pp = field.polygonPoints
    if type(pp) ~= "table" or #pp == 0 then
        return "field.polygonPoints empty"
    end
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for _, nodeId in ipairs(pp) do
        local x, _, z = getWorldTranslation(nodeId)
        if x < minX then minX = x end
        if x > maxX then maxX = x end
        if z < minZ then minZ = z end
        if z > maxZ then maxZ = z end
    end
    local sx, sz = minX, minZ
    local wx, wz = maxX - minX, 0
    local hx, hz = 0, maxZ - minZ
    Logging.info("[MyTodos] weed bbox: x=[%.1f..%.1f] z=[%.1f..%.1f]", minX, maxX, minZ, maxZ)

    -- 1. FSDensityMapUtil.getWeedFactor - Live-Faktor fuer die Feld-Bbox.
    --    NUR die volle 6-arg-Signatur (Parallelogramm sx,sz, wx,wz, hx,hz)!
    --    Die fruehere 4-arg-Variante warf unter Precision Farming einen
    --    'setParallelogramWorldCoords: Argument 5 nil'-Fehler (PF-Harvest-
    --    Extension ueberschreibt getWeedFactor und braucht das volle
    --    Parallelogramm) -- entfernt.
    if FSDensityMapUtil ~= nil and type(FSDensityMapUtil.getWeedFactor) == "function" then
        local ok, a, b, c = pcall(FSDensityMapUtil.getWeedFactor, sx, sz, wx, wz, hx, hz)
        Logging.info("[MyTodos] getWeedFactor(6arg): ok=%s ret1=%s ret2=%s ret3=%s",
            tostring(ok), tostring(a), tostring(b), tostring(c))
    end

    -- 2. globalCandidates fuer weed-Manager / -System
    local globalCandidates = {
        "g_weedSystem", "g_currentMission.weedSystem",
        "WeedSystem", "FSWeedSystem", "g_weedManager",
    }
    for _, name in ipairs(globalCandidates) do
        local val = _G[name]
        if val == nil and name:find("%.") then
            local first, rest = name:match("([^%.]+)%.(.+)")
            if first ~= nil and _G[first] ~= nil then
                val = _G[first][rest]
            end
        end
        Logging.info("[MyTodos] global %s: %s", name, tostring(val))
        if type(val) == "table" then
            self:dumpKeys("  " .. name, val)
        end
    end

    -- 3. Sweep ueber fieldGroundSystem.densityMaps - alle Eintraege deren key
    --    weed enthaelt
    if g_currentMission ~= nil and g_currentMission.fieldGroundSystem ~= nil then
        local dms = g_currentMission.fieldGroundSystem.densityMaps
        if type(dms) == "table" then
            for k, v in pairs(dms) do
                if type(v) == "table" and type(v.key) == "string"
                        and v.key:lower():find("weed") then
                    Logging.info("[MyTodos] weed densityMap found at key %s", tostring(k))
                    self:dumpKeys("  weed-dm", v)
                end
            end
        end
    end

    -- 4. Suche generell nach weed-related globals (ohne uns vorzugeben was)
    local terrainDetailId = nil
    if g_currentMission ~= nil and g_currentMission.fieldGroundSystem ~= nil then
        local dms = g_currentMission.fieldGroundSystem.densityMaps
        if type(dms) == "table" then
            for _, v in pairs(dms) do
                if type(v) == "table" and v.useTerrainDetailId and v.map ~= nil then
                    terrainDetailId = v.map
                    break
                end
            end
        end
    end
    Logging.info("[MyTodos] terrainDetailId guess: %s", tostring(terrainDetailId))

    -- 5. weedSystem direkt anzapfen
    local ws = g_currentMission and g_currentMission.weedSystem
    if ws == nil then
        return "Weed probe done (no weedSystem) - check log"
    end

    -- 5a: factors-Tabelle dumpen (vermutlich density-map-wert -> weedFactor)
    if type(ws.factors) == "table" then
        Logging.info("[MyTodos] weedSystem.factors:")
        for k, v in pairs(ws.factors) do
            Logging.info("[MyTodos]   factors[%s] = %s", tostring(k), tostring(v))
        end
    end

    -- 5b: Spot-Sample am Feld-Mittelpunkt
    local cx = (minX + maxX) / 2
    local cz = (minZ + maxZ) / 2
    local cy = 0
    if g_currentMission.terrainRootNode ~= nil then
        cy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, cx, 0, cz)
    end
    if type(WeedSystem) == "table" then
        if type(WeedSystem.getWeedStateAtWorldPos) == "function" then
            local ok, st = pcall(WeedSystem.getWeedStateAtWorldPos, ws, cx, cy, cz)
            Logging.info("[MyTodos] weedSystem:getWeedStateAtWorldPos(%.1f,%.1f,%.1f): ok=%s st=%s",
                cx, cy, cz, tostring(ok), tostring(st))
        end
        if type(WeedSystem.getWeedFactorAtWorldPos) == "function" then
            local ok, f = pcall(WeedSystem.getWeedFactorAtWorldPos, ws, cx, cy, cz)
            Logging.info("[MyTodos] weedSystem:getWeedFactorAtWorldPos(%.1f,%.1f,%.1f): ok=%s f=%s",
                cx, cy, cz, tostring(ok), tostring(f))
        end
    end

    -- 5c: DensityMapModifier auf weedSystem.densityMap mit Polygon, alle
    --     Werte 0..15 (numChannels=4) sweepen
    if DensityMapModifier ~= nil and DensityMapFilter ~= nil
            and ws.densityMap ~= nil and g_currentMission.terrainRootNode ~= nil then
        local mok, mod = pcall(DensityMapModifier.new, ws.densityMap,
            ws.firstChannel or 0, ws.numChannels or 4,
            g_currentMission.terrainRootNode)
        if mok and mod ~= nil then
            mod:clearPolygonPoints()
            for _, nodeId in ipairs(field.polygonPoints) do
                local x, _, z = getWorldTranslation(nodeId)
                mod:addPolygonPointWorldCoords(x, z)
            end
            local total, area, totalArea = mod:executeGet()
            Logging.info("[MyTodos] weed-mod (polygon) no-filter: total=%s area=%s totalArea=%s",
                tostring(total), tostring(area), tostring(totalArea))
            for value = 0, 15 do
                local f = DensityMapFilter.new(mod)
                f:setValueCompareParams(DensityValueCompareType.EQUAL, value)
                local t, a, _ = mod:executeGet(f)
                if (a or 0) > 0 then
                    Logging.info("[MyTodos] weed value=%d: total=%s area=%s",
                        value, tostring(t), tostring(a))
                end
            end
        else
            Logging.info("[MyTodos] DensityMapModifier.new on weedSystem.densityMap failed: %s",
                tostring(mod))
        end
    end

    return "Weed probe done - check log"
end

addConsoleCommand("mtProbeStones", "Probe stone density on a field. Usage: mtProbeStones <fieldNumber>",
    "consoleProbeStonesCmd", MyTodos)
function MyTodos:consoleProbeStonesCmd(arg)
    if arg == nil or arg == "" then return "Usage: mtProbeStones <fieldNumber>" end
    if g_fieldManager == nil then return "g_fieldManager nil" end
    local field = self:resolveFieldByUserNumber(arg)
    if field == nil then return string.format("Field %s not found", tostring(arg)) end
    if FSDensityMapUtil == nil or type(FSDensityMapUtil.getStoneArea) ~= "function" then
        return "FSDensityMapUtil.getStoneArea not available"
    end

    -- Bbox aus polygonPoints (Node-IDs!)
    local pp = field.polygonPoints
    if type(pp) ~= "table" or #pp == 0 then
        return "field.polygonPoints empty"
    end
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for _, nodeId in ipairs(pp) do
        local x, _, z = getWorldTranslation(nodeId)
        if x < minX then minX = x end
        if x > maxX then maxX = x end
        if z < minZ then minZ = z end
        if z > maxZ then maxZ = z end
    end
    local sx, sz = minX, minZ
    local wx, wz = maxX - minX, 0
    local hx, hz = 0, maxZ - minZ
    Logging.info("[MyTodos] stones bbox: x=[%.1f..%.1f] z=[%.1f..%.1f]", minX, maxX, minZ, maxZ)

    -- Standard-Signatur (sx,sz, wx,wz, hx,hz) liefert vermutlich
    -- area, totalArea analog zu getFruitArea.
    local ok, a, b, c, d = pcall(FSDensityMapUtil.getStoneArea, sx, sz, wx, wz, hx, hz)
    Logging.info("[MyTodos] getStoneArea(sx,sz,wx,wz,hx,hz): ok=%s ret1=%s ret2=%s ret3=%s ret4=%s",
        tostring(ok), tostring(a), tostring(b), tostring(c), tostring(d))

    -- Variante mit nur sx,sz,wx,wz fuer den Fall einer kleineren Signatur.
    local ok2, a2, b2, c2, d2 = pcall(FSDensityMapUtil.getStoneArea, sx, sz, wx, wz)
    Logging.info("[MyTodos] getStoneArea(sx,sz,wx,wz): ok=%s ret1=%s ret2=%s ret3=%s ret4=%s",
        tostring(ok2), tostring(a2), tostring(b2), tostring(c2), tostring(d2))

    -- Vergleich mit getFruitArea-Aufruf (kennen wir die Semantik) auf gleicher Bbox -
    -- nur als Sanity-Check ob die Bbox an sich brauchbar ist.
    if type(FSDensityMapUtil.getWeedFactor) == "function" then
        local okW, wa, wb = pcall(FSDensityMapUtil.getWeedFactor, sx, sz, wx, wz, hx, hz)
        Logging.info("[MyTodos] getWeedFactor (sanity): ok=%s ret1=%s ret2=%s",
            tostring(okW), tostring(wa), tostring(wb))
    end

    -- Schritt 2: fieldGroundSystem.densityMaps dumpen - hier sollten alle
    -- benannten Density-Maps drin sein, inklusive Stein-Map.
    if g_currentMission ~= nil and g_currentMission.fieldGroundSystem ~= nil then
        local dms = g_currentMission.fieldGroundSystem.densityMaps
        if type(dms) == "table" then
            Logging.info("[MyTodos] fieldGroundSystem.densityMaps keys:")
            for k, v in pairs(dms) do
                Logging.info("[MyTodos]   %s = <%s>", tostring(k), type(v))
                if type(v) == "table" then
                    self:dumpKeys(string.format("    densityMaps[%s]", tostring(k)), v)
                end
            end
        end
    end

    -- Schritt 3: stoneSystem direkt anzapfen
    local ss = g_currentMission ~= nil and g_currentMission.stoneSystem or nil
    if ss == nil then
        return "Stone probe done (no stoneSystem) - check log"
    end

    -- 3a: Spot-Sample am Feld-Mittelpunkt
    local cx = (minX + maxX) / 2
    local cz = (minZ + maxZ) / 2
    local cy = 0
    if g_currentMission.terrainRootNode ~= nil then
        cy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, cx, 0, cz)
    end
    if type(StoneSystem.getStoneLevelAtWorldPos) == "function" then
        local ok, lvl = pcall(StoneSystem.getStoneLevelAtWorldPos, ss, cx, cy, cz)
        Logging.info("[MyTodos] stoneSystem:getStoneLevelAtWorldPos(%.1f,%.1f,%.1f): ok=%s lvl=%s",
            cx, cy, cz, tostring(ok), tostring(lvl))
    end
    if type(StoneSystem.getStoneStateAtWorldPos) == "function" then
        local ok, st = pcall(StoneSystem.getStoneStateAtWorldPos, ss, cx, cy, cz)
        Logging.info("[MyTodos] stoneSystem:getStoneStateAtWorldPos(%.1f,%.1f,%.1f): ok=%s st=%s",
            cx, cy, cz, tostring(ok), tostring(st))
    end

    -- 3b: eigenen DensityMapModifier auf stoneSystem.densityMap mit Polygon,
    -- dann pro Wert 0..7 zaehlen wieviel Pixel auf dem Feld dieses Level haben.
    if DensityMapModifier ~= nil and DensityMapFilter ~= nil
            and ss.densityMap ~= nil and g_currentMission.terrainRootNode ~= nil then
        local mok, mod = pcall(DensityMapModifier.new, ss.densityMap,
            ss.firstChannel or 0, ss.numChannels or 3,
            g_currentMission.terrainRootNode)
        if mok and mod ~= nil then
            mod:clearPolygonPoints()
            for _, nodeId in ipairs(field.polygonPoints) do
                local x, _, z = getWorldTranslation(nodeId)
                mod:addPolygonPointWorldCoords(x, z)
            end
            local total, area, totalArea = mod:executeGet()
            Logging.info("[MyTodos] stone-mod (polygon) no-filter: total=%s area=%s totalArea=%s",
                tostring(total), tostring(area), tostring(totalArea))
            for value = 0, 7 do
                local f = DensityMapFilter.new(mod)
                f:setValueCompareParams(DensityValueCompareType.EQUAL, value)
                local t, a, _ = mod:executeGet(f)
                if (a or 0) > 0 then
                    Logging.info("[MyTodos] stone value=%d: total=%s area=%s",
                        value, tostring(t), tostring(a))
                end
            end
        else
            Logging.info("[MyTodos] DensityMapModifier.new on stoneSystem.densityMap failed: %s",
                tostring(mod))
        end
    end

    return "Stone probe done - check log"
end

-- Listet alle field-Instanzen die `farmland.name == <arg>` haben.
-- Auf modded Maps kann eine User-facing Feldnummer mehreren echten
-- field-Objekten entsprechen (eine Farmland traegt mehrere Polygons,
-- oder mehrere Farmlands haben zufaellig den gleichen Namen).
-- Liefert pro Treffer: FieldManager-Key, farmland.id, fruitTypeIndex,
-- growthState und Polygon-Punkt-Anzahl -- damit wir sehen welche
-- Instanz tatsaechlich die Frucht traegt.
addConsoleCommand("mtFindField",
    "List all field-instances with a given farmland.name. Usage: mtFindField <fieldNumber>",
    "consoleFindFieldCmd", MyTodos)
function MyTodos:consoleFindFieldCmd(arg)
    if arg == nil or arg == "" then return "Usage: mtFindField <fieldNumber>" end
    if g_fieldManager == nil then return "g_fieldManager nil" end
    local target = tostring(arg)
    local targetNum = tonumber(arg)
    local matches = 0
    for key, field in pairs(g_fieldManager:getFields()) do
        local fname = field.farmland and field.farmland.name
        local fnameStr = tostring(fname)
        if fnameStr == target
                or (targetNum ~= nil and targetNum == tonumber(fnameStr)) then
            matches = matches + 1
            local fs = field.fieldState or {}
            local ownerId = (field.farmland ~= nil and g_farmlandManager ~= nil)
                and g_farmlandManager:getFarmlandOwner(field.farmland.id) or nil
            Logging.info("[MyTodos] match for name=%s: fmKey=%s farmland.id=%s owner=%s fruitTypeIndex=%s growthState=%s polygon=%d",
                target, tostring(key),
                tostring(field.farmland and field.farmland.id),
                tostring(ownerId),
                tostring(fs.fruitTypeIndex),
                tostring(fs.growthState),
                (type(field.polygonPoints) == "table") and #field.polygonPoints or -1)
        end
    end
    return string.format("Found %d field-instance(s) with farmland.name=%s",
        matches, target)
end

-- Listet alle eigenen Felder mit ihrer tatsaechlichen Frucht und den
-- wichtigsten fieldState-Werten. Hilft die Engine-Sicht ("welche Frucht
-- liegt laut Aggregat auf welcher Farmland.name") mit dem Visuellen
-- abzugleichen. Wenn dein Weizen auf farmland.name=31 zu finden ist,
-- weisst du dass das "29"-Schild an der falschen Stelle steht.
addConsoleCommand("mtListOwned",
    "List all owned fields with their current fruit + state",
    "consoleListOwnedCmd", MyTodos)
function MyTodos:consoleListOwnedCmd()
    if g_fieldManager == nil then return "g_fieldManager nil" end
    if self.farmId == nil then return "MyTodos: no farmId yet" end
    Logging.info("[MyTodos] === owned fields with fruit ===")
    local rows = {}
    for fmKey, field in pairs(g_fieldManager:getFields()) do
        local fl = field.farmland
        if fl ~= nil and g_farmlandManager ~= nil
                and g_farmlandManager:getFarmlandOwner(fl.id) == self.farmId then
            local fs = field.fieldState or {}
            local fruit = "<empty>"
            if (fs.fruitTypeIndex or 0) > 0 and g_fruitTypeManager ~= nil then
                local ft = g_fruitTypeManager:getFruitTypeByIndex(fs.fruitTypeIndex)
                if ft ~= nil then fruit = ft.name end
            end
            table.insert(rows, {
                name = fl.name, fmKey = fmKey, flId = fl.id,
                fruit = fruit, fs = fs,
            })
        end
    end
    -- Sortiert nach farmland.name (numerisch wenn moeglich) damit man's
    -- mit der Map-Sicht abgleichen kann.
    table.sort(rows, function(a, b)
        local an, bn = tonumber(a.name), tonumber(b.name)
        if an ~= nil and bn ~= nil then return an < bn end
        return tostring(a.name) < tostring(b.name)
    end)
    for _, r in ipairs(rows) do
        Logging.info("[MyTodos] name=%s fmKey=%s farmland.id=%s fruit=%s growth=%s plow=%s spray=%s",
            tostring(r.name), tostring(r.fmKey), tostring(r.flId),
            r.fruit, tostring(r.fs.growthState),
            tostring(r.fs.plowLevel), tostring(r.fs.sprayLevel))
    end
    return string.format("Listed %d owned field(s) - check log", #rows)
end

-- "Was sehe ich hier?": nimmt die Position des controlled-vehicle (oder
-- des Spielers wenn zu Fuss) und fragt die Engine ab welche Farmland,
-- welche Field-Polygon-Instanz und welche Frucht an diesem Punkt liegen.
-- Direktester Weg um Visuelles und Engine-Sicht abzugleichen.
addConsoleCommand("mtWhereAmI",
    "Probe farmland / field / fruit at your current world position",
    "consoleWhereAmICmd", MyTodos)
function MyTodos:consoleWhereAmICmd()
    -- Position-Detection in FS25 ist unzuverlaessig -- Giants hat die
    -- APIs zwischen Versionen umgebaut. Wir probieren mehrere Quellen
    -- und nehmen den ersten plausiblen Treffer. Bonus: dumpen g_localPlayer
    -- damit wir bei Problemen direkt sehen welche Felder verfuegbar sind.
    local cm = g_currentMission
    local x, y, z, source

    local function trySource(label, getter)
        if x ~= nil then return end
        local ok, a, b, c = pcall(getter)
        if not ok then
            Logging.info("[MyTodos] pos probe '%s' err: %s", label, tostring(a))
            return
        end
        if type(a) ~= "number" or type(c) ~= "number" then
            Logging.info("[MyTodos] pos probe '%s' empty (a=%s c=%s)",
                label, tostring(a), tostring(c))
            return
        end
        -- (0, *, 0) sind sehr wahrscheinlich der "geparkte Player" wenn
        -- man im Fahrzeug sitzt -- nicht akzeptieren, weiterprobieren.
        if math.abs(a) < 0.01 and math.abs(c) < 0.01 then
            Logging.info("[MyTodos] pos probe '%s' skipped (origin-zero: x=%.2f z=%.2f -- player parked while in vehicle?)",
                label, a, c)
            return
        end
        Logging.info("[MyTodos] pos probe '%s' OK: x=%.2f y=%.2f z=%.2f",
            label, a, b or 0, c)
        x, y, z, source = a, b, c, label
    end

    -- 1. cm.controlledVehicle (legacy)
    if cm ~= nil and cm.controlledVehicle ~= nil
            and cm.controlledVehicle.rootNode ~= nil then
        local v = cm.controlledVehicle
        trySource("cm.controlledVehicle",
            function() return getWorldTranslation(v.rootNode) end)
    end
    -- 2. g_localPlayer.controlledVehicle (FS25-typisch)
    if _G.g_localPlayer ~= nil
            and _G.g_localPlayer.controlledVehicle ~= nil
            and _G.g_localPlayer.controlledVehicle.rootNode ~= nil then
        local v = _G.g_localPlayer.controlledVehicle
        trySource("g_localPlayer.controlledVehicle",
            function() return getWorldTranslation(v.rootNode) end)
    end
    -- 3. Methode cm:getControlledVehicle()
    if cm ~= nil and type(cm.getControlledVehicle) == "function" then
        local ok, gv = pcall(cm.getControlledVehicle, cm)
        if ok and gv ~= nil and gv.rootNode ~= nil then
            trySource("cm:getControlledVehicle()",
                function() return getWorldTranslation(gv.rootNode) end)
        end
    end
    -- 4. Scan vehicleSystem.vehicles nach "entered/controlled"-Flag.
    --    Bekannte Method-Kandidaten in FS25: getIsEntered, getIsControlled.
    if cm ~= nil and cm.vehicleSystem ~= nil
            and type(cm.vehicleSystem.vehicles) == "table" then
        for _, veh in ipairs(cm.vehicleSystem.vehicles) do
            if veh.rootNode ~= nil then
                local active = false
                for _, m in ipairs({"getIsEntered", "getIsControlled"}) do
                    if type(veh[m]) == "function" then
                        local ok, r = pcall(veh[m], veh)
                        if ok and r == true then active = true; break end
                    end
                end
                if not active and veh.isEntered == true then active = true end
                if not active and veh.isControlled == true then active = true end
                if active then
                    local vv = veh
                    trySource("vehicleSystem entered: " .. tostring(vv.typeName),
                        function() return getWorldTranslation(vv.rootNode) end)
                    if x ~= nil then break end
                end
            end
        end
    end
    -- 5. g_localPlayer.rootNode -- letzter Fallback. Wenn im Vehicle, ist
    --    das oft (0, ~-200, 0); der origin-zero-Filter in trySource
    --    blockiert das, sonst akzeptieren (Spieler zu Fuss).
    if _G.g_localPlayer ~= nil and _G.g_localPlayer.rootNode ~= nil then
        local p = _G.g_localPlayer
        trySource("g_localPlayer.rootNode",
            function() return getWorldTranslation(p.rootNode) end)
    end

    if x == nil then
        Logging.info("[MyTodos] no position source found. Diagnostic dump:")
        if _G.g_localPlayer ~= nil then
            self:dumpKeys("g_localPlayer", _G.g_localPlayer)
        end
        if cm ~= nil and cm.vehicleSystem ~= nil
                and type(cm.vehicleSystem.vehicles) == "table" then
            Logging.info("[MyTodos] vehicleSystem.vehicles: %d entries",
                #cm.vehicleSystem.vehicles)
        end
        return "no position source found -- diagnostic written to log"
    end
    Logging.info("[MyTodos] pos (%s): x=%.2f y=%.2f z=%.2f",
        source, x, y or 0, z)

    -- 1. Farmland-Lookup an der Position
    if g_farmlandManager ~= nil then
        local methods = { "getFarmlandIdAtWorldPosition", "getFarmlandAtWorldPosition" }
        for _, m in ipairs(methods) do
            if type(g_farmlandManager[m]) == "function" then
                local ok, ret = pcall(g_farmlandManager[m], g_farmlandManager, x, z)
                if ok then
                    Logging.info("[MyTodos] g_farmlandManager:%s -> %s",
                        m, tostring(ret))
                    if type(ret) == "number" then
                        local fl = g_farmlandManager.farmlands
                            and g_farmlandManager.farmlands[ret]
                        if fl ~= nil then
                            local owner = g_farmlandManager:getFarmlandOwner(ret)
                            Logging.info("[MyTodos]   -> farmland.name=%s owner=%s (your farmId=%s)",
                                tostring(fl.name), tostring(owner),
                                tostring(self.farmId))
                        end
                    end
                end
            end
        end
    end

    -- 2. Field-Polygon-Lookup: durchlaufen, point-in-polygon (ray casting)
    --    auf field.polygonPoints. Damit sehen wir welche field-Instanz
    --    diese Stelle als Teil ihres Polygons hat.
    if g_fieldManager ~= nil then
        for fmKey, field in pairs(g_fieldManager:getFields()) do
            local pts = field.polygonPoints
            if type(pts) == "table" and #pts >= 3 then
                local inside = false
                local n = #pts
                local px, _, pz = getWorldTranslation(pts[n])
                local lastX, lastZ = px, pz
                for i = 1, n do
                    local cx, _, cz = getWorldTranslation(pts[i])
                    if ((cz > z) ~= (lastZ > z))
                            and (x < (lastX - cx) * (z - cz) / (lastZ - cz) + cx) then
                        inside = not inside
                    end
                    lastX, lastZ = cx, cz
                end
                if inside then
                    local fl = field.farmland
                    Logging.info("[MyTodos] field-polygon contains pos: fmKey=%s farmland.name=%s farmland.id=%s",
                        tostring(fmKey),
                        tostring(fl and fl.name),
                        tostring(fl and fl.id))
                end
            end
        end
    end

    -- 3. Direkt-Sample der Frucht-Density-Map am Punkt. Probiere
    --    bekannte API-Kandidaten -- FSDensityMapUtil ist in FS25 ge-scrubbed,
    --    wir muessen Trial-and-Error machen.
    if FSDensityMapUtil ~= nil then
        local probeMethods = {
            "getFruitTypeIndexAtWorldPos",
            "getFruitAtWorldPos",
        }
        for _, m in ipairs(probeMethods) do
            if type(FSDensityMapUtil[m]) == "function" then
                local ok, a, b = pcall(FSDensityMapUtil[m], x, z)
                Logging.info("[MyTodos] FSDensityMapUtil.%s(x,z): ok=%s r1=%s r2=%s",
                    m, tostring(ok), tostring(a), tostring(b))
            end
        end
    end

    -- 4. Pro Frucht: getFruitArea ueber 1m^2-Box am Punkt -- wenn dieser
    --    Punkt von einem Frucht-Pixel bedeckt ist, area>0. So sehen wir
    --    welche Frucht physisch unter den Reifen ist.
    if FSDensityMapUtil ~= nil and type(FSDensityMapUtil.getFruitArea) == "function"
            and g_fruitTypeManager ~= nil then
        local sx, sz = x - 0.5, z - 0.5
        local wx, wz = 1, 0
        local hx, hz = 0, 1
        local fruits = g_fruitTypeManager:getFruitTypes()
        if type(fruits) == "table" then
            for idx, ft in pairs(fruits) do
                local ok, area, _, _ = pcall(FSDensityMapUtil.getFruitArea,
                    ft.index or idx, sx, sz, wx, wz, hx, hz)
                if ok and (area or 0) > 0 then
                    Logging.info("[MyTodos] fruit at pos: %s (area=%s)",
                        tostring(ft.name), tostring(area))
                end
            end
        end
    end

    return "Position probed - check log"
end

-- Sample alle bekannten Fruchtindizes 1..60 an der aktuellen Position
-- und logge jeden -- damit wir mit Gewissheit sehen welche Frucht laut
-- Density-Map auf diesem Punkt liegt. Behebt Unklarheit ob meine
-- getFruitTypes()-Iteration in mtWhereAmI Weizen evtl. ueberspringt.
addConsoleCommand("mtFruitHere",
    "Sample EVERY fruit index in the registry at current world pos",
    "consoleFruitHereCmd", MyTodos)
function MyTodos:consoleFruitHereCmd()
    -- Reuse position-finding (selber Block wie in mtWhereAmI, kompakt)
    local cm = g_currentMission
    local x, z
    if _G.g_localPlayer ~= nil and _G.g_localPlayer.controlledVehicle ~= nil
            and _G.g_localPlayer.controlledVehicle.rootNode ~= nil then
        x, _, z = getWorldTranslation(_G.g_localPlayer.controlledVehicle.rootNode)
    end
    if x == nil and cm ~= nil and cm.vehicleSystem ~= nil
            and type(cm.vehicleSystem.vehicles) == "table" then
        for _, veh in ipairs(cm.vehicleSystem.vehicles) do
            if veh.rootNode ~= nil then
                local active = false
                for _, m in ipairs({"getIsEntered", "getIsControlled"}) do
                    if type(veh[m]) == "function" then
                        local ok, r = pcall(veh[m], veh)
                        if ok and r == true then active = true; break end
                    end
                end
                if active then
                    x, _, z = getWorldTranslation(veh.rootNode)
                    break
                end
            end
        end
    end
    if x == nil then return "no vehicle position -- get in a tractor first" end
    Logging.info("[MyTodos] mtFruitHere at x=%.2f z=%.2f", x, z)

    if g_fruitTypeManager == nil or FSDensityMapUtil == nil
            or type(FSDensityMapUtil.getFruitArea) ~= "function" then
        return "g_fruitTypeManager or FSDensityMapUtil missing"
    end

    local sx, sz = x - 0.5, z - 0.5
    local wx, wz = 1, 0
    local hx, hz = 0, 1
    local hits = 0
    for i = 1, 60 do
        local ft = g_fruitTypeManager:getFruitTypeByIndex(i)
        if ft ~= nil then
            local ok, area, total = pcall(FSDensityMapUtil.getFruitArea,
                i, sx, sz, wx, wz, hx, hz)
            local areaNum = (ok and type(area) == "number") and area or 0
            local marker = ""
            if areaNum > 0 then
                marker = "  <-- PRESENT"
                hits = hits + 1
            end
            Logging.info("[MyTodos] idx=%2d name=%-22s area=%s total=%s%s",
                i, tostring(ft.name),
                tostring(area), tostring(total), marker)
        end
    end
    return string.format("Fruit-here probe done -- %d fruit(s) present at this point",
        hits)
end

addConsoleCommand("mtFields", "List all fields with ID/number/name candidates",
    "consoleFieldsCmd", MyTodos)
function MyTodos:consoleFieldsCmd()
    if g_fieldManager == nil then return "g_fieldManager nil" end
    Logging.info("[MyTodos] === fields probe ===")
    local fields = g_fieldManager:getFields()
    local seenMethodKeys = {}
    for key, field in pairs(fields) do
        local farmlandId = field.farmland and field.farmland.id or nil
        local farmlandName = field.farmland and field.farmland.name or nil
        Logging.info("[MyTodos] key=%s farmland.id=%s farmland.name=%s",
            tostring(key),
            tostring(farmlandId),
            tostring(farmlandName))
        -- Erste Iteration: alle direct keys
        if next(seenMethodKeys) == nil then
            local keys = {}
            for k, v in pairs(field) do
                local desc
                if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
                    desc = string.format("%s=%s", tostring(k), tostring(v))
                else
                    desc = string.format("%s=<%s>", tostring(k), type(v))
                end
                table.insert(keys, desc)
            end
            table.sort(keys)
            Logging.info("[MyTodos]   all field-instance keys: %s",
                table.concat(keys, ", "))
            -- Klassen-Methoden via Metatable, nur die relevanten
            local mt = getmetatable(field)
            if mt and mt.__index then
                local fns = {}
                for k, v in pairs(mt.__index) do
                    if type(v) == "function"
                            and (k:lower():find("name") or k:lower():find("number")
                                or k:lower():find("getid")) then
                        table.insert(fns, k)
                    end
                end
                table.sort(fns)
                Logging.info("[MyTodos]   id/name/number methods: %s",
                    table.concat(fns, ", "))
                -- Probiere die direkt aufzurufen
                for _, fn in ipairs(fns) do
                    local ok, ret = pcall(field[fn], field)
                    Logging.info("[MyTodos]     %s() -> ok=%s ret=%s",
                        fn, tostring(ok), tostring(ret))
                end
            end
            seenMethodKeys[1] = true
        end
    end
    return "Fields probed - check log"
end

addConsoleCommand("mtProbeHusbandry", "Probe FS25 husbandry placeable API",
    "consoleProbeHusbandryCmd", MyTodos)
function MyTodos:consoleProbeHusbandryCmd()
    return self:husbandryProbe()
end

addConsoleCommand("mtProbeHusbandryDeep", "Deep probe husbandry inner spec tables",
    "consoleProbeHusbandryDeepCmd", MyTodos)
function MyTodos:consoleProbeHusbandryDeepCmd()
    return self:husbandryProbeDeep()
end

-- Dumpt die PrecisionFarming-API-Surface (g_precisionFarming + Sub-Maps).
-- Optional mit Feldnummer: samplet pH/N/soilType am Mittelpunkt des Feldes
-- via diverser Methoden-Kandidaten -- so finden wir per Trial-and-Error
-- die Method-Signaturen die in DIESEM Spiel-Build verfuegbar sind, weil
-- ValueMap/PHMap-Klassen in _gameSource ge-scrubbed sind.
addConsoleCommand("mtProbePf",
    "Probe Precision Farming API. Usage: mtProbePf [fieldNumber]",
    "consoleProbePfCmd", MyTodos)
function MyTodos:consoleProbePfCmd(arg)
    -- Stage 1: PF-Instanz an verschiedenen moeglichen Stellen suchen.
    -- In FS25 gibt es kein verlaessliches Global -- die PF-Maps leben auf
    -- Sprayer-Specs, der Backref zur zentralen Instanz ist pHMap.pfModule.
    local function findPfInstance()
        if g_precisionFarming ~= nil then
            return g_precisionFarming, "_G.g_precisionFarming"
        end
        if g_currentMission ~= nil then
            if g_currentMission.precisionFarming ~= nil then
                return g_currentMission.precisionFarming, "g_currentMission.precisionFarming"
            end
        end
        -- Spec-Scan: irgendein PF-Sprayer auf der Map -> spec.pHMap.pfModule
        local vsys = g_currentMission and g_currentMission.vehicleSystem
        if vsys ~= nil and type(vsys.vehicles) == "table" then
            for _, veh in ipairs(vsys.vehicles) do
                if type(veh) == "table" then
                    for k, v in pairs(veh) do
                        if tostring(k):find("^spec_") and type(v) == "table"
                                and v.pHMap ~= nil and v.pHMap.pfModule ~= nil then
                            return v.pHMap.pfModule,
                                string.format("spec[%s].pHMap.pfModule", tostring(k))
                        end
                    end
                end
            end
        end
        -- Brute-force: scan top-level globals fuer was mit pHMap drin
        for k, v in pairs(_G) do
            if type(v) == "table" and rawget(v, "pHMap") ~= nil
                    and rawget(v, "nitrogenMap") ~= nil then
                return v, "_G." .. tostring(k)
            end
        end
        return nil, nil
    end

    local pf, pfLocation = findPfInstance()
    if pf == nil then
        Logging.info("[MyTodos] PF probe: instance not found in any known location.")
        Logging.info("[MyTodos] === Forensik: alle _G-Keys mit 'precision' oder 'PF' ===")
        for k, v in pairs(_G) do
            local ks = tostring(k):lower()
            if ks:find("precision") or ks:find("phmap") or ks:find("nitrogenmap")
                    or ks:find("soilmap") or ks == "valuemap" then
                Logging.info("[MyTodos]   _G.%s = <%s>", tostring(k), type(v))
                if type(v) == "table" then
                    self:dumpKeys("    " .. tostring(k), v)
                    local mt = getmetatable(v)
                    if mt ~= nil and mt.__index then
                        local fns = {}
                        for mk, mv in pairs(mt.__index) do
                            if type(mv) == "function" then table.insert(fns, mk) end
                        end
                        table.sort(fns)
                        Logging.info("[MyTodos]     %s metatable methods: %s",
                            tostring(k), table.concat(fns, ", "))
                    end
                end
            end
        end
        Logging.info("[MyTodos] === g_modManager state ===")
        if g_modManager ~= nil then
            self:dumpKeys("g_modManager", g_modManager)
            if g_modManager.mods ~= nil then
                local count = 0
                for k, _ in pairs(g_modManager.mods) do
                    count = count + 1
                    if tostring(k):lower():find("precision") then
                        Logging.info("[MyTodos] g_modManager.mods[%s] exists", tostring(k))
                    end
                end
                Logging.info("[MyTodos] g_modManager.mods has %d entries", count)
            end
        end
        Logging.info("[MyTodos] === Fahrzeug + angehaengte Implements Probe ===")
        local function probeVehicleForPfSpec(vehicle, label)
            if vehicle == nil or type(vehicle) ~= "table" then return end
            for k, v in pairs(vehicle) do
                local ks = tostring(k)
                if ks:find("^spec_") and type(v) == "table" then
                    -- Suche nach pHMap/nitrogenMap/soilMap direkt im Spec
                    local hits = {}
                    for sk, sv in pairs(v) do
                        local sks = tostring(sk)
                        if sks == "pHMap" or sks == "nitrogenMap" or sks == "soilMap"
                                or sks == "yieldMap" or sks == "coverMap" then
                            table.insert(hits, string.format("%s=<%s>", sks, type(sv)))
                        end
                    end
                    if #hits > 0 then
                        Logging.info("[MyTodos] [%s] %s has PF-attrs: %s",
                            label, ks, table.concat(hits, ", "))
                        -- Dump die ganze Spec-Keys + besonders pHMap-Metatable
                        self:dumpKeys("  spec keys", v)
                        if v.pHMap ~= nil then
                            self:dumpKeys("  spec.pHMap keys", v.pHMap)
                            local mt = getmetatable(v.pHMap)
                            if mt ~= nil and mt.__index then
                                local fns = {}
                                for mk, mv in pairs(mt.__index) do
                                    if type(mv) == "function" then table.insert(fns, mk) end
                                end
                                table.sort(fns)
                                Logging.info("[MyTodos]   pHMap methods: %s",
                                    table.concat(fns, ", "))
                            end
                        end
                    end
                end
            end
        end

        local controlled = g_currentMission and g_currentMission.controlledVehicle or nil
        if controlled == nil then
            Logging.info("[MyTodos] no controlledVehicle")
        else
            probeVehicleForPfSpec(controlled, "controlledVehicle")
            -- Angehaengte Implements via attacherJoints
            local aj = controlled.spec_attacherJoints
            if aj ~= nil and type(aj.attachedImplements) == "table" then
                Logging.info("[MyTodos] %d attached implement(s)", #aj.attachedImplements)
                for i, impl in ipairs(aj.attachedImplements) do
                    if impl.object ~= nil then
                        probeVehicleForPfSpec(impl.object,
                            string.format("attached[%d]", i))
                    end
                end
            else
                Logging.info("[MyTodos] no spec_attacherJoints / attachedImplements")
            end
        end

        -- Fallback: scan alle Fahrzeuge der Welt nach erstem PF-Sprayer.
        -- g_currentMission.vehicleSystem ist in FS25 die zentrale Liste.
        local vsys = g_currentMission and g_currentMission.vehicleSystem
        if vsys ~= nil and type(vsys.vehicles) == "table" then
            local n = #vsys.vehicles
            Logging.info("[MyTodos] g_currentMission.vehicleSystem.vehicles: %d entries -- scanning first 30 for PF-spec",
                n)
            local scanned = 0
            local found = 0
            for _, veh in ipairs(vsys.vehicles) do
                scanned = scanned + 1
                if scanned > 30 then break end
                for k, v in pairs(veh) do
                    local ks = tostring(k)
                    if ks:find("^spec_") and type(v) == "table" and v.pHMap ~= nil then
                        Logging.info("[MyTodos] vehicleSystem[%s] type %s has %s.pHMap",
                            tostring(scanned), tostring(veh.typeName or "?"), ks)
                        found = found + 1
                        if found == 1 then
                            self:dumpKeys("  first-hit spec.pHMap", v.pHMap)
                        end
                        break
                    end
                end
            end
            Logging.info("[MyTodos] scanned %d vehicles, %d had PF spec", scanned, found)
        end
        Logging.info("[MyTodos] g_modIsLoaded[FS25_precisionFarming] = %s",
            tostring(g_modIsLoaded and g_modIsLoaded["FS25_precisionFarming"]))
        return "PF instance not found - detailed forensic log written"
    end
    Logging.info("[MyTodos] PF probe: instance found at %s", tostring(pfLocation))

    -- 1. Top-level Keys
    self:dumpKeys("g_precisionFarming", pf)
    local pfMt = getmetatable(pf)
    if pfMt ~= nil and pfMt.__index then
        self:dumpKeys("g_precisionFarming.metatable.__index", pfMt.__index)
    end

    -- 2. Sub-Maps: Instance-Keys + Methoden via Metatable
    local subMaps = {
        "pHMap", "nitrogenMap", "soilMap", "yieldMap",
        "seedRateMap", "coverMap", "tramlineMap",
    }
    for _, mapName in ipairs(subMaps) do
        local m = pf[mapName]
        if m ~= nil then
            self:dumpKeys("g_precisionFarming." .. mapName, m)
            local mt = getmetatable(m)
            if mt ~= nil and mt.__index then
                -- Nur Methoden listen, sonst zerschiesst die Tabelle das Log
                local fns = {}
                for k, v in pairs(mt.__index) do
                    if type(v) == "function" then
                        table.insert(fns, k)
                    end
                end
                table.sort(fns)
                Logging.info("[MyTodos]   %s methods (%d): %s",
                    mapName, #fns, table.concat(fns, ", "))
            end
        else
            Logging.info("[MyTodos] g_precisionFarming.%s: nil", mapName)
        end
    end

    -- 2b. Tiefer-Dump bestimmter Lookup-Tabellen auf pHMap/nitrogenMap/soilMap
    -- damit wir die Target-Berechnung verstehen koennen.
    local function deepDump(label, t, maxDepth, depth)
        maxDepth = maxDepth or 3
        depth = depth or 0
        if t == nil then
            Logging.info("[MyTodos] %s: nil", label)
            return
        end
        if type(t) ~= "table" then
            Logging.info("[MyTodos] %s: %s = %s", label, type(t), tostring(t))
            return
        end
        local indent = string.rep("  ", depth)
        local count = 0
        for k, v in pairs(t) do
            count = count + 1
            local tv = type(v)
            if tv == "number" or tv == "boolean" or tv == "string" then
                Logging.info("[MyTodos] %s%s[%s] = %s",
                    indent, label, tostring(k), tostring(v))
            elseif tv == "table" then
                if depth + 1 < maxDepth then
                    Logging.info("[MyTodos] %s%s[%s] = <table>",
                        indent, label, tostring(k))
                    deepDump(label .. "[" .. tostring(k) .. "]", v, maxDepth, depth + 1)
                else
                    -- nur Key-Liste der inneren Tabelle
                    local keys = {}
                    for kk, _ in pairs(v) do
                        table.insert(keys, tostring(kk))
                        if #keys >= 20 then table.insert(keys, "..."); break end
                    end
                    table.sort(keys)
                    Logging.info("[MyTodos] %s%s[%s] = <table>{%s}",
                        indent, label, tostring(k), table.concat(keys, ", "))
                end
            else
                Logging.info("[MyTodos] %s%s[%s] = <%s>", indent, label, tostring(k), tv)
            end
            if count >= 50 then
                Logging.info("[MyTodos] %s%s ... (truncated at 50 entries)", indent, label)
                break
            end
        end
    end

    if pf.pHMap ~= nil then
        Logging.info("[MyTodos] === pHMap Lookup-Tabellen (fuer Target-Berechnung) ===")
        deepDump("pHMap.pHValues", pf.pHMap.pHValues, 3)
        deepDump("pHMap.pHValuesToDisplay", pf.pHMap.pHValuesToDisplay, 3)
        deepDump("pHMap.yieldCurve", pf.pHMap.yieldCurve, 3)
        deepDump("pHMap.valueTransformations", pf.pHMap.valueTransformations, 2)
        deepDump("pHMap.limeUsage", pf.pHMap.limeUsage, 2)
    end
    if pf.nitrogenMap ~= nil then
        Logging.info("[MyTodos] === nitrogenMap Lookup-Tabellen (fuer N-Target) ===")
        deepDump("nitrogenMap.fruitRequirements", pf.nitrogenMap.fruitRequirements, 4)
        deepDump("nitrogenMap.fruitTypeIndexToFruitRequirement",
            pf.nitrogenMap.fruitTypeIndexToFruitRequirement, 2)
        deepDump("nitrogenMap.nitrogenValues", pf.nitrogenMap.nitrogenValues, 2)
        deepDump("nitrogenMap.yieldCurve", pf.nitrogenMap.yieldCurve, 3)
        deepDump("nitrogenMap.applicationRates", pf.nitrogenMap.applicationRates, 3)
        deepDump("nitrogenMap.initialValues", pf.nitrogenMap.initialValues, 2)
        deepDump("nitrogenMap.initialSprayLevelBonus", pf.nitrogenMap.initialSprayLevelBonus, 2)
        deepDump("nitrogenMap.nOffsetIndexToOffset", pf.nitrogenMap.nOffsetIndexToOffset, 2)
        deepDump("nitrogenMap.fertilizerFillTypes", pf.nitrogenMap.fertilizerFillTypes, 2)
        deepDump("nitrogenMap.fertilizerUsage", pf.nitrogenMap.fertilizerUsage, 2)
        deepDump("nitrogenMap.cropSensorFruitTypes", pf.nitrogenMap.cropSensorFruitTypes, 2)
        deepDump("nitrogenMap.valueFilter", pf.nitrogenMap.valueFilter, 2)
        deepDump("nitrogenMap.valueFilterEnabled", pf.nitrogenMap.valueFilterEnabled, 2)
    end
    if pf.soilMap ~= nil then
        Logging.info("[MyTodos] === soilMap Bodenart-Infos ===")
        deepDump("soilMap.soilTypes", pf.soilMap.soilTypes, 2)
        deepDump("soilMap.soilTypeIndexToType", pf.soilMap.soilTypeIndexToType, 2)
        deepDump("soilMap.types", pf.soilMap.types, 2)
    end

    -- 3. Wenn Feldnummer gegeben: Spot-Sample am Feld-Mittelpunkt
    if arg == nil or arg == "" then
        return "PF top-level + sub-maps dumped. Pass <fieldNumber> for sampling."
    end
    local field = self:resolveFieldByUserNumber(arg)
    if field == nil then
        return string.format("Field %s not found", tostring(arg))
    end
    local pp = field.polygonPoints
    if type(pp) ~= "table" or #pp == 0 then
        return "Field has no polygonPoints"
    end

    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for _, nodeId in ipairs(pp) do
        local x, _, z = getWorldTranslation(nodeId)
        if x < minX then minX = x end
        if x > maxX then maxX = x end
        if z < minZ then minZ = z end
        if z > maxZ then maxZ = z end
    end
    local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
    local cy = 0
    if g_currentMission and g_currentMission.terrainRootNode ~= nil then
        cy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, cx, 0, cz)
    end
    Logging.info("[MyTodos] field %s center: (%.1f, %.1f, %.1f)",
        tostring(arg), cx, cy, cz)

    -- Helper: ruft `obj:method(arg1, arg2, ...)` via pcall und loggt
    -- Returns. Skipt wenn Methode nicht existiert.
    local function try(label, obj, method, ...)
        local fn = obj and obj[method]
        if type(fn) ~= "function" then
            Logging.info("[MyTodos]   %s: <no method>", label)
            return
        end
        local ok, r1, r2, r3, r4 = pcall(fn, obj, ...)
        Logging.info("[MyTodos]   %s: ok=%s r=(%s, %s, %s, %s)",
            label, tostring(ok),
            tostring(r1), tostring(r2), tostring(r3), tostring(r4))
    end

    -- pHMap: probiere mehrere worldPos-Sample-Signaturen
    if pf.pHMap ~= nil then
        Logging.info("[MyTodos] === pHMap probes ===")
        try("pHMap:getMinMaxValue()", pf.pHMap, "getMinMaxValue")
        try("pHMap:getPhValueFromChangedStates(1)", pf.pHMap, "getPhValueFromChangedStates", 1)
        try("pHMap:getPhValueFromInternalValue(0)", pf.pHMap, "getPhValueFromInternalValue", 0)
        try("pHMap:getPhValueAtWorldPos(cx,cz)", pf.pHMap, "getPhValueAtWorldPos", cx, cz)
        try("pHMap:getValueAtWorldPos(cx,cz)", pf.pHMap, "getValueAtWorldPos", cx, cz)
        try("pHMap:getInternalValueAtWorldPos(cx,cz)", pf.pHMap, "getInternalValueAtWorldPos", cx, cz)
    end

    -- nitrogenMap: analog
    if pf.nitrogenMap ~= nil then
        Logging.info("[MyTodos] === nitrogenMap probes ===")
        try("nitrogenMap:getMinMaxValue()", pf.nitrogenMap, "getMinMaxValue")
        try("nitrogenMap:getNitrogenValueFromInternalValue(0)", pf.nitrogenMap, "getNitrogenValueFromInternalValue", 0)
        try("nitrogenMap:getNitrogenFromChangedStates(1)", pf.nitrogenMap, "getNitrogenFromChangedStates", 1)
        try("nitrogenMap:getValueAtWorldPos(cx,cz)", pf.nitrogenMap, "getValueAtWorldPos", cx, cz)
        try("nitrogenMap:getNitrogenValueAtWorldPos(cx,cz)", pf.nitrogenMap, "getNitrogenValueAtWorldPos", cx, cz)
        try("nitrogenMap:getInternalValueAtWorldPos(cx,cz)", pf.nitrogenMap, "getInternalValueAtWorldPos", cx, cz)
    end

    -- soilMap: bodentyp + purchased-Check pro Farmland
    if pf.soilMap ~= nil then
        Logging.info("[MyTodos] === soilMap probes ===")
        try("soilMap:getTypeIndexAtWorldPos(cx,cz)", pf.soilMap, "getTypeIndexAtWorldPos", cx, cz)
        if field.farmland ~= nil then
            local fid = field.farmland.id
            try("soilMap:isSoilMapPurchased(farmland.id)", pf.soilMap, "isSoilMapPurchased", fid)
            try("soilMap:getIsSoilMapPurchased(farmland.id)", pf.soilMap, "getIsSoilMapPurchased", fid)
            try("soilMap:isPurchased(farmland.id)", pf.soilMap, "isPurchased", fid)
        end
    end

    -- 4. Direkter Density-Map-Zugriff probieren (fuer Polygon-Sampling spaeter)
    if pf.pHMap ~= nil then
        Logging.info("[MyTodos] === pHMap density-map attributes ===")
        for _, attr in ipairs({"densityMapId", "densityMap", "mapId",
                                "firstChannel", "numChannels",
                                "firstStateChannel", "numStateChannels",
                                "internalMinValue", "internalMaxValue",
                                "minValue", "maxValue"}) do
            Logging.info("[MyTodos]   pHMap.%s = %s",
                attr, tostring(pf.pHMap[attr]))
        end
    end

    return string.format("PF probed at field %s center - check log", tostring(arg))
end

-- Histogram-Diagnose pH/N pro Feld: gibt fuer jeden internal-state-Wert die
-- Pixel-Anzahl im Feld-Polygon aus. So sehen wir genau ob/wieviel
-- uninit-Pixel (value=0) den Average verfaelschen und ob der Filter wirkt.
addConsoleCommand("mtDebugPf",
    "Histogram of pH/N density-map values in field polygon. Usage: mtDebugPf <fieldNumber>",
    "consoleDebugPfCmd", MyTodos)
function MyTodos:consoleDebugPfCmd(arg)
    if arg == nil or arg == "" then
        return "Usage: mtDebugPf <fieldNumber>"
    end
    local field = self:resolveFieldByUserNumber(arg)
    if field == nil then return "field " .. tostring(arg) .. " not found" end
    if type(field.polygonPoints) ~= "table" or #field.polygonPoints == 0 then
        return "no polygonPoints"
    end
    local pHMap = self:findPfPHMap()
    if pHMap == nil then return "no PF pHMap available" end

    local function histo(label, map, firstCh, numCh, maxVal)
        if map == nil then
            Logging.info("[MyTodos] %s: density-map nil", label)
            return
        end
        local mod = DensityMapModifier.new(map, firstCh, numCh,
            g_currentMission.terrainRootNode)
        self:applyFieldPolygon(mod, field)
        local sumAll, areaAll, totalArea = mod:executeGet()
        Logging.info("[MyTodos] %s: no filter -> sum=%s pixelArea=%s totalArea=%s avgInternal=%.3f",
            label, tostring(sumAll), tostring(areaAll), tostring(totalArea),
            (areaAll and areaAll > 0) and (sumAll / areaAll) or -1)
        if DensityMapFilter ~= nil then
            local f = DensityMapFilter.new(mod)
            f:setValueCompareParams(DensityValueCompareType.GREATER, 0)
            local sumG, areaG, _ = mod:executeGet(f)
            Logging.info("[MyTodos] %s: GREATER 0  -> sum=%s pixelArea=%s avgInternal=%.3f",
                label, tostring(sumG), tostring(areaG),
                (areaG and areaG > 0) and (sumG / areaG) or -1)
            local fb = DensityMapFilter.new(mod)
            fb:setValueCompareParams(DensityValueCompareType.BETWEEN, 1, maxVal)
            local sumB, areaB, _ = mod:executeGet(fb)
            Logging.info("[MyTodos] %s: BETWEEN 1..%d -> sum=%s pixelArea=%s avgInternal=%.3f",
                label, maxVal, tostring(sumB), tostring(areaB),
                (areaB and areaB > 0) and (sumB / areaB) or -1)
        end
        -- Pro-Wert-Histogramm (nur wenn maxVal handlich). Bei Soil-Map auch
        -- die soilType-Namen ausgeben (Bitmap v=0..3 -> soilTypes[1..4]).
        local soilMap = pHMap.pfModule and pHMap.pfModule.soilMap
        local soilTypes = soilMap and soilMap.soilTypes
        for v = 0, maxVal do
            local fv = DensityMapFilter.new(mod)
            fv:setValueCompareParams(DensityValueCompareType.EQUAL, v)
            local _, areaV, _ = mod:executeGet(fv)
            if areaV ~= nil and areaV > 0 then
                local suffix = ""
                if label == "Soil" and soilTypes ~= nil and soilTypes[v + 1] ~= nil then
                    suffix = string.format(" (%s)", soilTypes[v + 1].name or "?")
                end
                Logging.info("[MyTodos]   %s[v=%d] = %d px%s", label, v, areaV, suffix)
            end
        end
    end

    Logging.info("[MyTodos] === mtDebugPf field %s ===", tostring(arg))
    histo("pH", pHMap.bitVectorMap, pHMap.firstChannel or 0,
        pHMap.numChannels or 5, pHMap.maxValue or 31)
    local nMap = pHMap.pfModule and pHMap.pfModule.nitrogenMap
    if nMap ~= nil then
        histo("N", nMap.bitVectorMap, nMap.firstChannel or 0,
            nMap.numChannels or 6, nMap.maxValue or 45)
    end
    local soilMap = pHMap.pfModule and pHMap.pfModule.soilMap
    if soilMap ~= nil then
        histo("Soil", soilMap.bitVectorMap, soilMap.typeFirstChannel or 0,
            soilMap.typeNumChannels or 2, MyTodos.SOIL_NUM_TYPES)
    end
    -- Init-Mask wenn vorhanden (separate Map mit "Bodenkarte gekauft" = 1)
    local initMap = pHMap.bitVectorMapPHInitMask
    if initMap ~= nil then
        Logging.info("[MyTodos] pHMap.bitVectorMapPHInitMask = %s (separate Map fuer 'gekauft'-Filter)",
            tostring(initMap))
    end
    return "mtDebugPf done - check log"
end

-- Diagnose: dumpt Icon-Pfade von fillTypes/fruitTypes/Tieren ins Log.
-- Ziel ist herauszufinden WIE das Icon-Pfad-Feld heisst, bevor wir es
-- im HUD verwenden (kein Raten -- siehe TMR-"FORAGE"-Lektion).
addConsoleCommand("mtProbeIcons",
    "Dump fillType/fruitType/animal icon paths to the log",
    "consoleProbeIconsCmd", MyTodos)
function MyTodos:consoleProbeIconsCmd()
    Logging.info("[MyTodos] === icon probe ===")

    -- 1. FillType-Descs einiger Fruechte. dumpKeys zeigt String-Felder
    --    inline (Wert sichtbar) -> daran sehen wir das Icon-Pfad-Feld.
    if g_fillTypeManager ~= nil and FillType ~= nil then
        local names = {"WHEAT", "BARLEY", "CANOLA", "MAIZE", "POTATO",
            "SUGARBEET", "SUNFLOWER", "GRASS_WINDROW", "FORAGE"}
        for _, n in ipairs(names) do
            local idx = FillType[n]
            local ft = idx ~= nil
                and g_fillTypeManager:getFillTypeByIndex(idx) or nil
            if ft ~= nil then
                self:dumpKeys(string.format("fillType.%s[%s]", n, tostring(idx)), ft)
            else
                Logging.info("[MyTodos] fillType.%s: not found", n)
            end
        end
    else
        Logging.info("[MyTodos] g_fillTypeManager / FillType: nil")
    end

    -- 2. FruitType -> FillType-Verknuepfung. Am Feld liegt fruitTypeIndex;
    --    fuers Icon brauchen wir den Weg zu einem fillType.
    if g_fruitTypeManager ~= nil then
        self:_listClassMethods("g_fruitTypeManager", g_fruitTypeManager)
        local fruit = g_fruitTypeManager:getFruitTypeByIndex(1)
        if fruit ~= nil then
            self:dumpKeys(string.format("fruitType[1] (%s)",
                tostring(fruit.name)), fruit)
        end
        if type(g_fruitTypeManager.getFillTypeIndexByFruitTypeIndex) == "function" then
            local ok, fillIdx = pcall(
                g_fruitTypeManager.getFillTypeIndexByFruitTypeIndex,
                g_fruitTypeManager, 1)
            Logging.info("[MyTodos] getFillTypeIndexByFruitTypeIndex(1) -> ok=%s val=%s",
                tostring(ok), tostring(fillIdx))
        end
    else
        Logging.info("[MyTodos] g_fruitTypeManager: nil")
    end

    -- 3. Tier-Icons: animalType selbst hat KEIN Icon-Feld. Kandidaten
    --    abklopfen: Placeable-storeItem, animalType.subTypes, der
    --    animalSystem-subType und ein evtl. daran haengender Tier-fillType.
    if self.farmId ~= nil then
        local owned = self:collectOwnedHusbandries(self.farmId)
        local p = owned and owned[1] and owned[1].placeable or nil
        if p ~= nil then
            if p.storeItem ~= nil then
                self:dumpKeys("placeable.storeItem", p.storeItem)
            else
                Logging.info("[MyTodos] placeable.storeItem: nil")
            end
            local at = p.spec_husbandryAnimals
                and p.spec_husbandryAnimals.animalType or nil
            if at ~= nil and type(at.subTypes) == "table" then
                for k, st in pairs(at.subTypes) do
                    if type(st) == "table" then
                        self:dumpKeys(string.format("animalType.subTypes[%s]",
                            tostring(k)), st)
                    end
                end
            end
        else
            Logging.info("[MyTodos] no owned husbandry found")
        end
    end
    if g_currentMission ~= nil and g_currentMission.animalSystem ~= nil
            and type(g_currentMission.animalSystem.subTypes) == "table" then
        local st = g_currentMission.animalSystem.subTypes[1]
        if type(st) == "table" then
            self:dumpKeys("animalSystem.subTypes[1]", st)
            local fti = st.fillTypeIndex
            if type(fti) == "number" and g_fillTypeManager ~= nil then
                local ft = g_fillTypeManager:getFillTypeByIndex(fti)
                if ft ~= nil then
                    self:dumpKeys(string.format("subType.fillType[%d]", fti), ft)
                end
            end
        end
    end

    return "Icon probe done - check log"
end

-- Diagnose: dumpt gueltige Overlay-Slice-IDs aus g_overlayManager. Zweck:
-- den korrekten Vanilla-Slice fuers Settings-Tab-Icon (Slider+Zahnrad)
-- finden OHNE zu raten -- die Slice-Config liegt gepackt in dataS.gar und
-- ist nur zur Laufzeit greifbar (g_overlayManager.textureConfigs[prefix].slices).
-- Ohne Argument: Settings-/Zahnrad-Kandidaten. Mit Argument: Substring-Filter.
--   mtDumpSlices            -> option/setting/gear/cog/... Kandidaten
--   mtDumpSlices options    -> alle Slices die "options" enthalten
addConsoleCommand("mtDumpSlices",
    "Dump g_overlayManager slice IDs (optional substring filter)",
    "consoleDumpSlicesCmd", MyTodos)
function MyTodos:consoleDumpSlicesCmd(filter)
    local om = g_overlayManager
    if om == nil or type(om.textureConfigs) ~= "table" then
        Logging.info("[MyTodos] g_overlayManager.textureConfigs not available")
        return "no overlay manager"
    end

    local keywords
    if filter ~= nil and filter ~= "" then
        keywords = { string.lower(tostring(filter)) }
    else
        keywords = { "option", "setting", "gear", "cog", "slider",
            "menu", "general", "config", "wrench", "tool", "gameplay" }
    end

    local function matchesId(id)
        local low = string.lower(id)
        for _, kw in ipairs(keywords) do
            if string.find(low, kw, 1, true) ~= nil then return true end
        end
        return false
    end

    Logging.info("[MyTodos] === mtDumpSlices (filter=%s) ===",
        (filter ~= nil and filter ~= "") and tostring(filter) or "settings-keywords")
    local total = 0
    for prefix, cfg in pairs(om.textureConfigs) do
        if type(cfg) == "table" and type(cfg.slices) == "table" then
            local ids = {}
            for id in pairs(cfg.slices) do
                if matchesId(id) then table.insert(ids, id) end
            end
            table.sort(ids)
            for _, id in ipairs(ids) do
                Logging.info("[MyTodos]   %s.%s", tostring(prefix), id)
                total = total + 1
            end
        end
    end
    Logging.info("[MyTodos] mtDumpSlices done (%d matched)", total)
    return "mtDumpSlices done - check log"
end

-- Paddy/Perennial-Diagnose. Hintergrund: Reisfelder auf Hutan Pantari
-- (mapAS) sind als fieldType=1 ("rice") aufs Terrain gemalt und werden von
-- FS25 NICHT als Field-Objekt angelegt -- sie sind owned Farmlands ohne
-- Eintrag in g_fieldManager:getFields(). Sehr wahrscheinlich gilt dasselbe
-- fuer Trauben (GRAPE) und Oliven (OLIVE): mehrjaehrige Kulturen, die auf ein
-- eigenes Grundstueck gepflanzt werden, ebenfalls ohne Field-Objekt. Der
-- ganze Mod kennt nur getFields(), darum sind all diese unsichtbar. Dieser
-- Probe sammelt die 4 Unbekannten die wir fuer ein eigenes Subsystem brauchen
-- (frucht-agnostisch -- funktioniert auf Reis, Trauben, Oliven gleichermassen):
--   A) Handle/Struktur des fieldType-Density-Layers (rice = value 1)
--   B) welche Farmlands dir gehoeren aber KEIN Field haben (= Kandidaten)
--   C) Frucht + Growth-State am aktuellen Standort + Box-Histogramm
--   D) FruitType-Definition (RICE/RICELONGGRAIN/GRAPE/OLIVE + was am Ort liegt)
-- Mit einem Fahrzeug mitten auf das jeweilige Grundstueck fahren, dann
-- ausfuehren -- bei mehreren Kultur-Typen je einmal pro Typ.
addConsoleCommand("mtProbePaddy",
    "Probe perennial-crop data model (rice/grape/olive on ownerless farmland). Stand on the plot.",
    "consoleProbePaddyCmd", MyTodos)
function MyTodos:consoleProbePaddyCmd()
    if g_currentMission == nil then return "g_currentMission nil" end
    Logging.info("[MyTodos] === mtProbePaddy ===")

    -- A) fieldType-Density-Layer ----------------------------------------
    -- Wir wollen das Handle finden, mit dem wir spaeter einen
    -- DensityMapModifier bauen koennen (rice = value 1). Erst die ganze
    -- densityMaps-Tabelle + fieldGroundSystem-Methoden dumpen, dann den
    -- fieldType-Eintrag explizit aufschluesseln.
    local fgs = g_currentMission.fieldGroundSystem
    local fieldTypeEntry = nil
    if fgs == nil then
        Logging.info("[MyTodos] (A) fieldGroundSystem: nil")
    else
        self:_listClassMethods("fieldGroundSystem", fgs)
        local dms = fgs.densityMaps
        if type(dms) == "table" then
            Logging.info("[MyTodos] (A) fieldGroundSystem.densityMaps:")
            for k, v in pairs(dms) do
                Logging.info("[MyTodos]   [%s] = <%s>", tostring(k), type(v))
                if type(v) == "table" then
                    self:dumpKeys(string.format("    densityMaps[%s]", tostring(k)), v)
                end
                -- fieldType-Eintrag per .key erkennen (Tabelle ist numerisch
                -- gekeyt 1..N, NICHT nach Layer-Name). Handle liegt auf .map.
                if type(v) == "table" and tostring(v.key):lower():find("fieldtype") then
                    fieldTypeEntry = v
                end
            end
        else
            Logging.info("[MyTodos] (A) fieldGroundSystem.densityMaps: <%s>", type(dms))
        end
        -- Direkte top-level keys des Systems (vielleicht liegt das fieldType-
        -- Handle dort als eigenes Feld, nicht unter densityMaps).
        self:dumpKeys("(A) fieldGroundSystem keys", fgs)
    end

    -- fieldType-Modifier einmal bauen (Handle = entry.map), wiederverwendbar
    -- in (B) pro Farmland-Box und in (C) am Standort. rice = value 1.
    local ftMod, ftRiceFilter
    if type(fieldTypeEntry) == "table" and fieldTypeEntry.map ~= nil
            and DensityMapModifier ~= nil and DensityMapFilter ~= nil
            and g_currentMission.terrainRootNode ~= nil then
        local fc = fieldTypeEntry.firstChannel or 0
        local nc = fieldTypeEntry.numChannels or 1
        local ok, m = pcall(DensityMapModifier.new, fieldTypeEntry.map, fc, nc,
            g_currentMission.terrainRootNode)
        if ok and m ~= nil then
            ftMod = m
            ftRiceFilter = DensityMapFilter.new(m)
            ftRiceFilter:setValueCompareParams(DensityValueCompareType.EQUAL, 1)
            Logging.info("[MyTodos] (A) fieldType modifier ready (map=%s fc=%d nc=%d, rice=value 1)",
                tostring(fieldTypeEntry.map), fc, nc)
        else
            Logging.info("[MyTodos] (A) fieldType modifier build failed: %s", tostring(m))
        end
    else
        Logging.info("[MyTodos] (A) no fieldType entry/map found -- cannot build modifier")
    end
    -- Box-Sampler: rice(v=1) vs total in einer quadratischen Box um (cx,cz).
    local function sampleFieldTypeBox(cx, cz, r)
        if ftMod == nil or cx == nil or cz == nil then return nil, nil end
        ftMod:clearPolygonPoints()
        ftMod:addPolygonPointWorldCoords(cx - r, cz - r)
        ftMod:addPolygonPointWorldCoords(cx + r, cz - r)
        ftMod:addPolygonPointWorldCoords(cx + r, cz + r)
        ftMod:addPolygonPointWorldCoords(cx - r, cz + r)
        local _, _, totalArea = ftMod:executeGet()
        local _, riceArea, _ = ftMod:executeGet(ftRiceFilter)
        return totalArea, riceArea
    end

    -- B) Owned Farmlands OHNE Field-Objekt = Paddy-Kandidaten -----------
    -- Set der Farmland-IDs die ein Field tragen.
    local fieldFarmlandIds = {}
    if g_fieldManager ~= nil then
        for _, field in pairs(g_fieldManager:getFields()) do
            if field.farmland ~= nil and field.farmland.id ~= nil then
                fieldFarmlandIds[field.farmland.id] = true
            end
        end
    end
    Logging.info("[MyTodos] (B) owned farmlands WITHOUT a Field (paddy candidates):")
    local candidateCount = 0
    if g_farmlandManager ~= nil and type(g_farmlandManager.farmlands) == "table" then
        -- nach id sortiert ausgeben
        local ids = {}
        for id in pairs(g_farmlandManager.farmlands) do
            if type(id) == "number" then table.insert(ids, id) end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local fl = g_farmlandManager.farmlands[id]
            local owner = g_farmlandManager:getFarmlandOwner(id)
            if owner == self.farmId and not fieldFarmlandIds[id] then
                candidateCount = candidateCount + 1
                Logging.info("[MyTodos]   farmland id=%s name=%s areaHa=%s npc=%s buyable=%s",
                    tostring(id), tostring(fl and fl.name),
                    tostring(fl and (fl.areaInHa or fl.areaHa)),
                    tostring(fl and fl.npcIndex),
                    tostring(fl and fl.isBuyable))
                if fl ~= nil then
                    self:dumpKeys(string.format("    farmland[%s]", tostring(id)), fl)
                    -- boundingBox-Struktur aufschluesseln (Geometrie-Quelle
                    -- fuer das Subsystem, da es kein polygonPoints gibt).
                    if type(fl.boundingBox) == "table" then
                        self:dumpKeys(string.format("    farmland[%s].boundingBox", tostring(id)),
                            fl.boundingBox)
                    end
                    -- fieldType ueber die Flaeche sampeln: Box ums Zentrum,
                    -- Kantenlaenge ~ aus areaInHa abgeleitet (+Puffer).
                    if ftMod ~= nil and fl.xWorldPos ~= nil and fl.zWorldPos ~= nil then
                        local side = math.sqrt(math.max(fl.areaInHa or 0.05, 0.01) * 10000)
                        local r = side * 0.7
                        local totalA, riceA = sampleFieldTypeBox(fl.xWorldPos, fl.zWorldPos, r)
                        Logging.info("[MyTodos]     -> fieldType box(center,r=%.0f): totalArea=%s rice(v=1)Area=%s",
                            r, tostring(totalA), tostring(riceA))
                    end
                end
            end
        end
    else
        Logging.info("[MyTodos]   g_farmlandManager.farmlands not a table")
    end
    Logging.info("[MyTodos] (B) -> %d candidate(s)", candidateCount)

    -- Position bestimmen (kompakter Finder wie in mtFruitHere) ----------
    local cm = g_currentMission
    local x, z
    if _G.g_localPlayer ~= nil and _G.g_localPlayer.controlledVehicle ~= nil
            and _G.g_localPlayer.controlledVehicle.rootNode ~= nil then
        x, _, z = getWorldTranslation(_G.g_localPlayer.controlledVehicle.rootNode)
    end
    if x == nil and cm.vehicleSystem ~= nil
            and type(cm.vehicleSystem.vehicles) == "table" then
        for _, veh in ipairs(cm.vehicleSystem.vehicles) do
            if veh.rootNode ~= nil then
                local active = false
                for _, m in ipairs({"getIsEntered", "getIsControlled"}) do
                    if type(veh[m]) == "function" then
                        local ok, r = pcall(veh[m], veh)
                        if ok and r == true then active = true; break end
                    end
                end
                if active then x, _, z = getWorldTranslation(veh.rootNode); break end
            end
        end
    end
    if x == nil then
        return string.format("Paddy probe (A/B) done -- %d candidate(s). Get in a vehicle on a paddy for C/D.",
            candidateCount)
    end

    -- C) Spot- + Box-Sampling am Standort -------------------------------
    Logging.info("[MyTodos] (C) sampling at x=%.2f z=%.2f", x, z)
    if g_farmlandManager ~= nil and type(g_farmlandManager.getFarmlandIdAtWorldPosition) == "function" then
        local ok, fid = pcall(g_farmlandManager.getFarmlandIdAtWorldPosition, g_farmlandManager, x, z)
        if ok then
            local owner = (type(fid) == "number") and g_farmlandManager:getFarmlandOwner(fid) or nil
            Logging.info("[MyTodos]   farmland here = %s (owner=%s, your farmId=%s, hasField=%s)",
                tostring(fid), tostring(owner), tostring(self.farmId),
                tostring(type(fid) == "number" and fieldFarmlandIds[fid] == true))
        end
    end
    -- Frucht + Growth-State am exakten Punkt: getFruitTypeIndexAtWorldPos
    -- liefert (fruitIndex, growthState) -- bestaetigt durch mtWhereAmI (r1=9 r2=5).
    if FSDensityMapUtil ~= nil and type(FSDensityMapUtil.getFruitTypeIndexAtWorldPos) == "function" then
        local ok, fi, gs = pcall(FSDensityMapUtil.getFruitTypeIndexAtWorldPos, x, z)
        Logging.info("[MyTodos]   getFruitTypeIndexAtWorldPos -> ok=%s fruitIndex=%s growthState=%s",
            tostring(ok), tostring(fi), tostring(gs))
    end

    -- fieldType-Wert in einer 40m-Box um den Standort (rice = value 1).
    do
        local totalA, riceA = sampleFieldTypeBox(x, z, 20)
        if totalA ~= nil then
            Logging.info("[MyTodos]   fieldType box(here,r=20): totalArea=%s rice(v=1)Area=%s",
                tostring(totalA), tostring(riceA))
        else
            Logging.info("[MyTodos]   fieldType sampler unavailable -- see (A)")
        end
    end

    -- Box-Grid-Histogramm der Growth-States ohne Frucht-Map-Handle:
    -- 7x7 Punkte ueber ~42m, je getFruitTypeIndexAtWorldPos, tallying.
    -- foundFruits sammelt welche Fruchtindizes hier liegen -> (D) dumpt
    -- deren Definition automatisch (deckt Reis genauso wie Trauben/Oliven ab).
    local foundFruits = {}
    if FSDensityMapUtil ~= nil and type(FSDensityMapUtil.getFruitTypeIndexAtWorldPos) == "function" then
        local tally = {}   -- key "fruitIdx:growth" -> count
        local R, N = 21, 7
        for i = 0, N - 1 do
            for j = 0, N - 1 do
                local px = x - R + (2 * R) * i / (N - 1)
                local pz = z - R + (2 * R) * j / (N - 1)
                local ok, fi, gs = pcall(FSDensityMapUtil.getFruitTypeIndexAtWorldPos, px, pz)
                if ok and type(fi) == "number" and fi > 0 then
                    local key = string.format("%d:%s", fi, tostring(gs))
                    tally[key] = (tally[key] or 0) + 1
                    foundFruits[fi] = true
                end
            end
        end
        Logging.info("[MyTodos] (C) grid histogram fruitIdx:growthState -> count (N=%d):", N * N)
        local keys = {}
        for k in pairs(tally) do table.insert(keys, k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local fi = tonumber(string.match(k, "^(%d+):"))
            local fname = (fi ~= nil and g_fruitTypeManager ~= nil)
                and (g_fruitTypeManager:getFruitTypeByIndex(fi) or {}).name or "?"
            Logging.info("[MyTodos]   %s (%s) -> %d px", k, tostring(fname), tally[k])
        end
    end

    -- D) FruitType-Definition (Task-Vokabular) --------------------------
    -- numGrowthStates, min/maxHarvestingGrowthState, witheredState,
    -- cutState(s), growthStateToName -- analog zu dem was derivePrimaryVanilla
    -- aus normalen Feldern liest. Wir dumpen die bekannten Mehrjahres-/
    -- Spezialfruechte (Reis, Trauben, Oliven -- werden alle auf eigene
    -- Grundstuecke ohne Field-Objekt gepflanzt) PLUS alles was das Grid
    -- gerade unter den Reifen gefunden hat (datengetrieben).
    if g_fruitTypeManager ~= nil then
        local wantIdx, order = {}, {}
        local function want(idx)
            if type(idx) == "number" and idx > 0 and not wantIdx[idx] then
                wantIdx[idx] = true
                table.insert(order, idx)
            end
        end
        for _, name in ipairs({"RICE", "RICELONGGRAIN", "GRAPE", "OLIVE"}) do
            local idx = nil
            if type(g_fruitTypeManager.getFruitTypeByName) == "function" then
                local ft = g_fruitTypeManager:getFruitTypeByName(name)
                idx = ft and ft.index
            end
            if idx == nil and FruitType ~= nil then idx = FruitType[name] end
            want(idx)
        end
        for fi in pairs(foundFruits) do want(fi) end

        for _, idx in ipairs(order) do
            local ft = g_fruitTypeManager:getFruitTypeByIndex(idx)
            if ft ~= nil then
                self:dumpKeys(string.format("(D) fruit[%d] %s", idx, tostring(ft.name)), ft)
                if type(ft.growthStateToName) == "table" then
                    self:dumpKeys(string.format("(D) fruit[%d].growthStateToName", idx),
                        ft.growthStateToName)
                end
                if type(ft.cutStates) == "table" then
                    self:dumpKeys(string.format("(D) fruit[%d].cutStates", idx), ft.cutStates)
                end
            else
                Logging.info("[MyTodos] (D) fruit idx=%s: not found", tostring(idx))
            end
        end
    end

    return string.format("Paddy probe done -- %d candidate(s). Check log for A/B/C/D.",
        candidateCount)
end
