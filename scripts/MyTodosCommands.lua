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

    -- 2. Spot-Sample am Feld-Zentrum mit Y
    if type(DensityMapHeightUtil.getHeightTypeDescAtWorldPos) == "function" then
        local ok, a, b, c, d = pcall(DensityMapHeightUtil.getHeightTypeDescAtWorldPos, cx, cy, cz)
        Logging.info("[MyTodos] getHeightTypeDescAtWorldPos(x,y,z): ok=%s a=%s b=%s c=%s d=%s",
            tostring(ok), tostring(a), tostring(b), tostring(c), tostring(d))
        if type(a) == "table" then
            self:dumpKeys("  desc", a)
        end
    end

    -- 3. DensityMapModifier auf den Type-Channels von terrainDetailHeightId.
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

    -- 1. FSDensityMapUtil.getWeedFactor - liefert vermutlich Live-Faktor
    if FSDensityMapUtil ~= nil and type(FSDensityMapUtil.getWeedFactor) == "function" then
        local ok, a, b, c = pcall(FSDensityMapUtil.getWeedFactor, sx, sz, wx, wz, hx, hz)
        Logging.info("[MyTodos] getWeedFactor(6arg): ok=%s ret1=%s ret2=%s ret3=%s",
            tostring(ok), tostring(a), tostring(b), tostring(c))
        local ok2, a2, b2 = pcall(FSDensityMapUtil.getWeedFactor, sx, sz, wx, wz)
        Logging.info("[MyTodos] getWeedFactor(4arg): ok=%s ret1=%s ret2=%s",
            tostring(ok2), tostring(a2), tostring(b2))
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
    -- Manche FS25-Setups parken die nicht in _G.g_precisionFarming sondern
    -- in g_currentMission, g_modManager.mods[...] o.ae.
    local function findPfInstance()
        if g_precisionFarming ~= nil then
            return g_precisionFarming, "_G.g_precisionFarming"
        end
        if g_currentMission ~= nil then
            if g_currentMission.precisionFarming ~= nil then
                return g_currentMission.precisionFarming, "g_currentMission.precisionFarming"
            end
            if g_currentMission.g_precisionFarming ~= nil then
                return g_currentMission.g_precisionFarming, "g_currentMission.g_precisionFarming"
            end
        end
        if g_modManager ~= nil and type(g_modManager.getMod) == "function" then
            for _, name in ipairs({"FS25_precisionFarming", "FS25_PrecisionFarming"}) do
                local ok, m = pcall(g_modManager.getMod, g_modManager, name)
                if ok and m ~= nil then
                    -- m ist meist ein ModDescriptor, suche darin nach PF-Instanz
                    if type(m) == "table" then
                        for k, v in pairs(m) do
                            if type(v) == "table" and v.pHMap ~= nil then
                                return v, "g_modManager.mods." .. name .. "." .. tostring(k)
                            end
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
