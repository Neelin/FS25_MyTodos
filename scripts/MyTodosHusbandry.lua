--
-- MyTodos / Husbandry
--
-- Tier-Husbandries: Discovery + Task-Derivation. Probe-Befehle (mtProbeHusbandry,
-- mtProbeHusbandryDeep) sind in MyTodosCommands.lua, fuer Live-Diagnose.
--
-- API-Kanon (empirisch via Probe bestaetigt, FS25 Vanilla):
--   - g_currentMission.placeableSystem.placeables = flache Liste aller Placeables
--   - Husbandry-Erkennung: irgendein Key auf dem Placeable beginnt mit
--     "spec_husbandry"
--   - Owner: placeable:getOwnerFarmId()
--   - Liter pro fillType (kanonische API, aggregiert ueber alle
--     angeschlossenen Storages: husbandry-eigene + externe Tanks):
--       placeable:getHusbandryFillLevel(fillTypeIdx) -> Liter
--       placeable:getHusbandryCapacity(fillTypeIdx)
--       placeable:getHusbandryFreeCapacity(fillTypeIdx)
--     Bestaetigt durch Probe: bei der Milchkuh-Husbandry zeigt
--     storage.fillLevels[113]=0/cap=0 (kein eigener Mist-Storage), aber
--     getHusbandryFillLevel(113)=22183/cap=4000000 weil ein externer
--     User-platzierter Tank angeschlossen ist. Die API summiert.
--   - Tier-Anzahl: placeable:getNumOfAnimals()
--   - Specs am Placeable (kein zentrales Manager-Lookup):
--       spec_husbandryFood: capacity (gesamt), fillLevels (table fillType -> liter),
--                           supportedFillTypes (table fillType -> true)
--       spec_husbandryWater: automaticWaterSupply (boolean!), fillType
--       spec_husbandryStraw: inputFillType (Stroh-Konsum), outputFillType (Mist),
--                            isManureActive, manureFactor
--       spec_husbandryLiquidManure: fillType (Guelle), litersPerHour
--       spec_husbandryManure: fillType (eigene Mist-Spec, alternative zu Straw-Output)
--       spec_husbandryMilk: fillTypes (Liste), activeFillTypes, hasMilkProduction.
--                           Mehrere Milch-Typen moeglich (z.B. 39=Milch, 41=Bio).
--                           Levels via getHusbandryFillLevel(ft).
--       spec_husbandryPallets: currentPallets, maxNumPallets, palletLimitReached,
--                               activeFillTypes (siehe Pallet-Limitation unten)
--       spec_husbandryMeadow: fillLevels (per fruitType), capacities (per fruitType)
--       spec_husbandryAnimals: animalType (groupTitle, name), animalTypeIndex
--   - Welche Specs an einem Placeable haengen, haengt vom Husbandry-Typ ab:
--     Pasture-Cow hat z.B. kein Pallets-Spec, kein Manure-Spec; Sheep-Barn hat
--     Pallets aber keine Meadow. Discovery muss flexibel sein und nur Tasks
--     fuer tatsaechlich vorhandene Specs erzeugen.
--

-- Sweep alles auf der Placeable-Tabelle was nach husbandry-spec aussieht.
function MyTodos:_husbandrySpecKeys(p)
    local out = {}
    for k, _ in pairs(p) do
        if type(k) == "string" and k:sub(1, 14) == "spec_husbandry" then
            table.insert(out, k)
        end
    end
    table.sort(out)
    return out
end

function MyTodos:_isHusbandryPlaceable(p)
    if p == nil then return false end
    -- Schon eine spec_husbandry*-Tabelle = wir sind richtig.
    for k, _ in pairs(p) do
        if type(k) == "string" and k:sub(1, 14) == "spec_husbandry" then
            return true
        end
    end
    return false
end

function MyTodos:_placeableOwnerFarmId(p)
    if p == nil then return nil end
    if type(p.getOwnerFarmId) == "function" then
        local ok, id = pcall(p.getOwnerFarmId, p)
        if ok and id ~= nil then return id end
    end
    return p.ownerFarmId
end

function MyTodos:husbandryProbe()
    Logging.info("[MyTodos] === husbandry probe ===")

    -- 1. Globale Manager / Klassen
    local globals = {
        "g_animalSystem", "g_animalFoodManager", "g_animalManager",
        "AnimalSystem", "AnimalFoodManager",
        "PlaceableHusbandry", "PlaceableAnimalHusbandry",
        "HusbandryModuleFood", "HusbandryModuleWater",
        "HusbandryModuleStraw", "HusbandryModuleAnimals",
        "HusbandryModuleManure", "HusbandryModuleLiquidManure",
        "HusbandryModuleMilk", "HusbandryModulePallets",
        "HusbandryModuleFenceUpdate",
    }
    for _, name in ipairs(globals) do
        Logging.info("[MyTodos] %s = %s", name, tostring(_G[name]))
    end

    if g_currentMission == nil then
        return "no g_currentMission"
    end
    Logging.info("[MyTodos] g_currentMission.placeableSystem = %s",
        tostring(g_currentMission.placeableSystem))
    Logging.info("[MyTodos] g_currentMission.husbandrySystem = %s",
        tostring(g_currentMission.husbandrySystem))

    if g_currentMission.placeableSystem == nil then
        return "no placeableSystem"
    end
    local ps = g_currentMission.placeableSystem
    self:dumpKeys("placeableSystem", ps)

    local placeables = ps.placeables
    if type(placeables) ~= "table" then
        return "placeableSystem.placeables not a table"
    end
    Logging.info("[MyTodos] %d placeables total", #placeables)

    -- 2. Eigene Farm-ID
    local myFarmId = self.farmId or self:getLocalFarmId()
    Logging.info("[MyTodos] my farmId = %s", tostring(myFarmId))

    -- 3. Iterate, filter eigene Husbandries
    local husbandryCount = 0
    for i, p in ipairs(placeables) do
        if self:_isHusbandryPlaceable(p) then
            local ownerId = self:_placeableOwnerFarmId(p)
            local mine = (myFarmId ~= nil) and (ownerId == myFarmId)
            local typeName = p.typeName or "?"
            local cfg = p.configFileName or "?"
            Logging.info("[MyTodos] placeable[%d] husbandry type=%s owner=%s mine=%s cfg=%s",
                i, tostring(typeName), tostring(ownerId), tostring(mine), tostring(cfg))

            if mine then
                husbandryCount = husbandryCount + 1
                local specKeys = self:_husbandrySpecKeys(p)
                Logging.info("[MyTodos]   spec_husbandry* keys: %s",
                    table.concat(specKeys, ", "))
                for _, key in ipairs(specKeys) do
                    self:dumpKeys("    " .. key, p[key])
                end

                -- Wenn vorhanden: animals-Spec hat clusters/typeIndex usw.
                local animals = p.spec_husbandryAnimals
                if type(animals) == "table" then
                    if type(animals.clusters) == "table" then
                        Logging.info("[MyTodos]   animals.clusters (%d entries):",
                            #animals.clusters)
                        for ci, c in ipairs(animals.clusters) do
                            self:dumpKeys(string.format("      cluster[%d]", ci), c)
                        end
                    end
                    if type(animals.subTypeIndex) ~= "nil" then
                        Logging.info("[MyTodos]   animals.subTypeIndex = %s",
                            tostring(animals.subTypeIndex))
                    end
                end
            end
        end
    end
    Logging.info("[MyTodos] %d owned husbandries found", husbandryCount)
    return string.format("Husbandry probe done - %d owned husbandries (check log)",
        husbandryCount)
end

-- Tieferer Probe: dumpt die inneren Tabellen der Specs (fillLevels,
-- supportedFillTypes, clusters etc.) und listet relevante Methoden der
-- PlaceableHusbandry-Klasse via Metatable.
function MyTodos:_dumpKVTable(label, t)
    if type(t) ~= "table" then return end
    local entries = {}
    for k, v in pairs(t) do
        table.insert(entries, string.format("[%s]=%s", tostring(k), tostring(v)))
    end
    table.sort(entries)
    Logging.info("[MyTodos]     %s: %s", label, table.concat(entries, ", "))
end

function MyTodos:_listClassMethods(label, t)
    if type(t) ~= "table" then return end
    local mt = getmetatable(t)
    if mt == nil or mt.__index == nil then return end
    local fns = {}
    for k, v in pairs(mt.__index) do
        if type(v) == "function" then table.insert(fns, k) end
    end
    table.sort(fns)
    Logging.info("[MyTodos]   %s methods: %s", label, table.concat(fns, ", "))
end

function MyTodos:husbandryProbeDeep()
    Logging.info("[MyTodos] === husbandry deep probe ===")

    -- A. Klassen-Methoden auf PlaceableHusbandry global
    if type(PlaceableHusbandry) == "table" then
        local fns = {}
        for k, v in pairs(PlaceableHusbandry) do
            if type(v) == "function" then table.insert(fns, k) end
        end
        table.sort(fns)
        Logging.info("[MyTodos] PlaceableHusbandry static fns: %s",
            table.concat(fns, ", "))
    end

    -- B. AnimalSystem
    if type(AnimalSystem) == "table" then
        self:dumpKeys("AnimalSystem static", AnimalSystem)
    end
    if g_currentMission ~= nil and g_currentMission.animalSystem ~= nil then
        self:dumpKeys("g_currentMission.animalSystem", g_currentMission.animalSystem)
    end

    if g_currentMission == nil or g_currentMission.placeableSystem == nil then
        return "no placeableSystem"
    end
    local placeables = g_currentMission.placeableSystem.placeables
    local myFarmId = self.farmId or self:getLocalFarmId()

    for i, p in ipairs(placeables) do
        if self:_isHusbandryPlaceable(p) then
            local ownerId = self:_placeableOwnerFarmId(p)
            if ownerId == myFarmId then
                local typeName = p.typeName or "?"
                Logging.info("[MyTodos] === DEEP placeable[%d] type=%s ===", i, typeName)

                -- Klassen-Methoden via Metatable
                self:_listClassMethods("placeable", p)

                -- Probe gut bekannter direkt-getter
                local getterCandidates = {
                    "getNumOfAnimals", "getNumAnimals", "getNumberOfAnimals",
                    "getMaxNumAnimals", "getCapacity", "getFillLevel",
                    "getNumPallets", "getPalletLimitReached",
                }
                for _, m in ipairs(getterCandidates) do
                    if type(p[m]) == "function" then
                        local ok, ret = pcall(p[m], p)
                        Logging.info("[MyTodos]   %s -> ok=%s ret=%s",
                            m, tostring(ok), tostring(ret))
                    end
                end

                -- spec_husbandry top-level
                local h = p.spec_husbandry
                if h ~= nil then
                    Logging.info("[MyTodos]   --- spec_husbandry deep ---")
                    Logging.info("[MyTodos]     productionFactor=%s globalProductionFactor=%s threshold=%s",
                        tostring(h.productionFactor),
                        tostring(h.globalProductionFactor),
                        tostring(h.productionThreshold))
                    if type(h.targetStorages) == "table" then
                        local cnt = 0
                        for _ in pairs(h.targetStorages) do cnt = cnt + 1 end
                        Logging.info("[MyTodos]     targetStorages count=%d", cnt)
                    end
                    if type(h.storage) == "table" then
                        Logging.info("[MyTodos]     storage.capacity=%s",
                            tostring(h.storage.capacity))
                        self:_dumpKVTable("storage.fillLevels", h.storage.fillLevels)
                        self:_dumpKVTable("storage.capacities", h.storage.capacities)
                        self:_dumpKVTable("storage.fillTypes", h.storage.fillTypes)
                    end
                end

                -- spec_husbandryStraw (Stroh-Input + Mist-Output)
                local straw = p.spec_husbandryStraw
                if straw ~= nil then
                    Logging.info("[MyTodos]   --- spec_husbandryStraw deep ---")
                    Logging.info("[MyTodos]     inputFillType=%s outputFillType=%s manureFactor=%s isManureActive=%s",
                        tostring(straw.inputFillType), tostring(straw.outputFillType),
                        tostring(straw.manureFactor), tostring(straw.isManureActive))
                    Logging.info("[MyTodos]     inputLitersPerHour=%s outputLitersPerHour=%s",
                        tostring(straw.inputLitersPerHour), tostring(straw.outputLitersPerHour))
                    if straw.inputFillType ~= nil and type(p.getHusbandryFillLevel) == "function" then
                        local lOk, lvl = pcall(p.getHusbandryFillLevel, p, straw.inputFillType)
                        local cOk, cap = pcall(p.getHusbandryCapacity, p, straw.inputFillType)
                        Logging.info("[MyTodos]     getHusbandryFillLevel(input=%s)=%s cap=%s",
                            tostring(straw.inputFillType),
                            lOk and tostring(lvl) or "ERR",
                            cOk and tostring(cap) or "ERR")
                    end
                    if straw.outputFillType ~= nil and type(p.getHusbandryFillLevel) == "function" then
                        local lOk, lvl = pcall(p.getHusbandryFillLevel, p, straw.outputFillType)
                        local cOk, cap = pcall(p.getHusbandryCapacity, p, straw.outputFillType)
                        Logging.info("[MyTodos]     getHusbandryFillLevel(output=%s)=%s cap=%s",
                            tostring(straw.outputFillType),
                            lOk and tostring(lvl) or "ERR",
                            cOk and tostring(cap) or "ERR")
                    end
                end

                -- spec_husbandryManure (Mist als eigene Spec - kommt bei
                -- manchen Husbandries vor, statt als Output von Straw)
                local manure = p.spec_husbandryManure
                if manure ~= nil then
                    Logging.info("[MyTodos]   --- spec_husbandryManure deep ---")
                    self:dumpKeys("    manure", manure)
                    if manure.fillType ~= nil and type(p.getHusbandryFillLevel) == "function" then
                        local lOk, lvl = pcall(p.getHusbandryFillLevel, p, manure.fillType)
                        local cOk, cap = pcall(p.getHusbandryCapacity, p, manure.fillType)
                        Logging.info("[MyTodos]     getHusbandryFillLevel(%s)=%s cap=%s",
                            tostring(manure.fillType),
                            lOk and tostring(lvl) or "ERR",
                            cOk and tostring(cap) or "ERR")
                    end
                end

                -- spec_husbandryLiquidManure (Guelle)
                local lmanure = p.spec_husbandryLiquidManure
                if lmanure ~= nil then
                    Logging.info("[MyTodos]   --- spec_husbandryLiquidManure deep ---")
                    self:dumpKeys("    liquidManure", lmanure)
                    if lmanure.fillType ~= nil and type(p.getHusbandryFillLevel) == "function" then
                        local lOk, lvl = pcall(p.getHusbandryFillLevel, p, lmanure.fillType)
                        local cOk, cap = pcall(p.getHusbandryCapacity, p, lmanure.fillType)
                        Logging.info("[MyTodos]     getHusbandryFillLevel(%s)=%s cap=%s",
                            tostring(lmanure.fillType),
                            lOk and tostring(lvl) or "ERR",
                            cOk and tostring(cap) or "ERR")
                    end
                end

                -- spec_husbandryMilk (mehrere Milch-fillTypes moeglich)
                local milk = p.spec_husbandryMilk
                if milk ~= nil then
                    Logging.info("[MyTodos]   --- spec_husbandryMilk deep ---")
                    Logging.info("[MyTodos]     hasMilkProduction=%s",
                        tostring(milk.hasMilkProduction))
                    self:_dumpKVTable("milk.fillTypes", milk.fillTypes)
                    self:_dumpKVTable("milk.activeFillTypes", milk.activeFillTypes)
                    self:_dumpKVTable("milk.litersPerHour", milk.litersPerHour)
                    if type(milk.fillTypes) == "table"
                            and type(p.getHusbandryFillLevel) == "function" then
                        for _, ft in pairs(milk.fillTypes) do
                            local lOk, lvl = pcall(p.getHusbandryFillLevel, p, ft)
                            local cOk, cap = pcall(p.getHusbandryCapacity, p, ft)
                            Logging.info("[MyTodos]     getHusbandryFillLevel(milk=%s)=%s cap=%s",
                                tostring(ft),
                                lOk and tostring(lvl) or "ERR",
                                cOk and tostring(cap) or "ERR")
                        end
                    end
                end

                -- spec_husbandryFood deep
                local food = p.spec_husbandryFood
                if food ~= nil then
                    Logging.info("[MyTodos]   --- spec_husbandryFood deep ---")
                    Logging.info("[MyTodos]     capacity=%s litersPerHour=%s animalTypeIndex=%s",
                        tostring(food.capacity),
                        tostring(food.litersPerHour),
                        tostring(food.animalTypeIndex))
                    self:_dumpKVTable("fillLevels", food.fillLevels)
                    -- fillLevels mit aufgeloesten fillType-Namen: zeigt
                    -- welcher Index Gras / TMR / Heu etc. ist. Noetig fuer
                    -- den Kuh-TMR-Fix (Gras im Trog != Kuh gefuettert).
                    if type(food.fillLevels) == "table"
                            and g_fillTypeManager ~= nil then
                        for ft, lvl in pairs(food.fillLevels) do
                            local def = g_fillTypeManager:getFillTypeByIndex(ft)
                            Logging.info("[MyTodos]       food[%s] name=%s title=%s level=%s",
                                tostring(ft),
                                def and tostring(def.name) or "?",
                                def and tostring(def.title) or "?",
                                tostring(lvl))
                        end
                    end
                    self:_dumpKVTable("fillTypes", food.fillTypes)
                    self:_dumpKVTable("supportedFillTypes", food.supportedFillTypes)
                    if food.info ~= nil then
                        self:dumpKeys("    food.info", food.info)
                    end
                end

                -- spec_husbandryWater deep
                local water = p.spec_husbandryWater
                if water ~= nil then
                    Logging.info("[MyTodos]   --- spec_husbandryWater deep ---")
                    Logging.info("[MyTodos]     automaticWaterSupply=%s litersPerHour=%s fillType=%s",
                        tostring(water.automaticWaterSupply),
                        tostring(water.litersPerHour),
                        tostring(water.fillType))
                    -- Wasser-Specs in FS25 haben oft fillLevel direkt drauf,
                    -- nicht in Tabelle. Probe alle Felder.
                    self:dumpKeys("    water (all keys)", water)
                    if water.info ~= nil then
                        self:dumpKeys("    water.info", water.info)
                    end
                end

                -- spec_husbandryPallets deep
                local pal = p.spec_husbandryPallets
                if pal ~= nil then
                    Logging.info("[MyTodos]   --- spec_husbandryPallets deep ---")
                    Logging.info("[MyTodos]     palletLimitReached=%s",
                        tostring(pal.palletLimitReached))
                    self:_dumpKVTable("fillTypes", pal.fillTypes)
                    self:_dumpKVTable("activeFillTypes", pal.activeFillTypes)
                    self:_dumpKVTable("fillLevels (buffer?)", pal.fillLevels)
                    self:_dumpKVTable("capacities", pal.capacities)
                    self:_dumpKVTable("maxNumPallets", pal.maxNumPallets)
                    self:_dumpKVTable("litersPerHour", pal.litersPerHour)
                    -- Was sagt die Klassen-API? Vermutlich die gesamte
                    -- abholbare Menge (Buffer + draussen liegende Pallets).
                    if type(pal.fillTypes) == "table"
                            and type(p.getHusbandryFillLevel) == "function" then
                        for _, ft in pairs(pal.fillTypes) do
                            local lOk, lvl = pcall(p.getHusbandryFillLevel, p, ft)
                            local cOk, cap = pcall(p.getHusbandryCapacity, p, ft)
                            Logging.info("[MyTodos]     getHusbandryFillLevel(%s)=%s capacity=%s",
                                tostring(ft),
                                lOk and tostring(lvl) or "ERR",
                                cOk and tostring(cap) or "ERR")
                        end
                    end
                    -- Network-Sync-Tabellen (alternative Quellen fuer Liter)
                    self:_dumpKVTable("pendingLiters", pal.pendingLiters)
                    self:_dumpKVTable("fillLevelsPending", pal.fillLevelsPending)
                    self:_dumpKVTable("capacitiesPending", pal.capacitiesPending)
                    self:_dumpKVTable("maxCapacitiesPending", pal.maxCapacitiesPending)
                    self:_dumpKVTable("fillLevelsSent", pal.fillLevelsSent)
                    self:_dumpKVTable("capacitiesSent", pal.capacitiesSent)
                    -- palletSpawner: vermutlich der Manager der Game-Objects.
                    if type(pal.palletSpawner) == "table" then
                        Logging.info("[MyTodos]     -- palletSpawner --")
                        self:dumpKeys("    palletSpawner", pal.palletSpawner)
                        self:_listClassMethods("    palletSpawner", pal.palletSpawner)
                        -- Bekannte Felder durchsuchen
                        for _, fn in ipairs({"spawnedPallets", "pallets", "trailerPallets"}) do
                            if type(pal.palletSpawner[fn]) == "table" then
                                local cnt = 0
                                for _ in pairs(pal.palletSpawner[fn]) do cnt = cnt + 1 end
                                Logging.info("[MyTodos]       palletSpawner.%s count=%d",
                                    fn, cnt)
                                for k, v in pairs(pal.palletSpawner[fn]) do
                                    Logging.info("[MyTodos]         [%s] type=%s val=%s",
                                        tostring(k), type(v), tostring(v))
                                    if type(v) == "table" then
                                        if type(v.getFillUnitFillLevel) == "function" then
                                            local ok, lvl = pcall(v.getFillUnitFillLevel, v, 1)
                                            Logging.info("[MyTodos]           getFillUnitFillLevel(1) ok=%s lvl=%s",
                                                tostring(ok), tostring(lvl))
                                        end
                                        if type(v.getFillUnitFillType) == "function" then
                                            local ok, ft = pcall(v.getFillUnitFillType, v, 1)
                                            Logging.info("[MyTodos]           getFillUnitFillType(1) ok=%s ft=%s",
                                                tostring(ok), tostring(ft))
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if type(pal.fillTypeIndexToPalletSpawner) == "table" then
                        for ftIdx, sp in pairs(pal.fillTypeIndexToPalletSpawner) do
                            Logging.info("[MyTodos]     fillTypeIndexToPalletSpawner[%s]:",
                                tostring(ftIdx))
                            if type(sp) == "table" then
                                self:dumpKeys("      ", sp)
                                for _, fn in ipairs({"spawnedPallets", "pallets"}) do
                                    if type(sp[fn]) == "table" then
                                        local cnt = 0
                                        for _ in pairs(sp[fn]) do cnt = cnt + 1 end
                                        Logging.info("[MyTodos]         %s count=%d",
                                            fn, cnt)
                                    end
                                end
                                -- spawnPlaces: physische Slots dieser
                                -- Husbandry. Wenn ein Slot belegt ist,
                                -- liegt dort eine Pallet.
                                if type(sp.spawnPlaces) == "table" then
                                    Logging.info("[MyTodos]         spawnPlaces:")
                                    for k, v in pairs(sp.spawnPlaces) do
                                        Logging.info("[MyTodos]           [%s] type=%s",
                                            tostring(k), type(v))
                                        if type(v) == "table" then
                                            self:dumpKeys("            keys", v)
                                            -- Probiere bekannte Properties
                                            for _, prop in ipairs({"currentPallet", "pallet", "object"}) do
                                                if v[prop] ~= nil then
                                                    Logging.info("[MyTodos]             %s=%s",
                                                        prop, tostring(v[prop]))
                                                    if type(v[prop]) == "table" then
                                                        if type(v[prop].getFillUnitFillLevel) == "function" then
                                                            local ok, lvl = pcall(v[prop].getFillUnitFillLevel, v[prop], 1)
                                                            local ok2, ft = pcall(v[prop].getFillUnitFillType, v[prop], 1)
                                                            Logging.info("[MyTodos]               getFillUnit(1) lvl=%s ft=%s",
                                                                tostring(lvl), tostring(ft))
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                                -- fillTypeToSpawnPlaces: pro fillType der Slot
                                if type(sp.fillTypeToSpawnPlaces) == "table" then
                                    Logging.info("[MyTodos]         fillTypeToSpawnPlaces:")
                                    for k, v in pairs(sp.fillTypeToSpawnPlaces) do
                                        Logging.info("[MyTodos]           [%s] type=%s",
                                            tostring(k), type(v))
                                    end
                                end
                                -- spawnQueue
                                if type(sp.spawnQueue) == "table" then
                                    local cnt = 0
                                    for _ in pairs(sp.spawnQueue) do cnt = cnt + 1 end
                                    Logging.info("[MyTodos]         spawnQueue count=%d", cnt)
                                end
                                -- Cache der getAllPallets-Methode
                                if type(sp.getAllPalletsFoundPallets) == "table" then
                                    local cnt = 0
                                    for _ in pairs(sp.getAllPalletsFoundPallets) do cnt = cnt + 1 end
                                    Logging.info("[MyTodos]         getAllPalletsFoundPallets count=%d (cached, last fillType=%s)",
                                        cnt, tostring(sp.getAllPalletsFiltype))
                                end
                            end
                        end
                    end
                    if type(pal.currentPallets) == "table" then
                        local cnt = 0
                        for _ in pairs(pal.currentPallets) do cnt = cnt + 1 end
                        Logging.info("[MyTodos]     currentPallets count=%d", cnt)
                        -- Pro Eintrag: Key, Typ, ggf. fillType. Damit wir
                        -- bei Multi-FillType-Husbandries (Schafe+Ziegen ->
                        -- Wolle + Ziegenmilch) pro fillType zaehlen koennen.
                        for k, v in pairs(pal.currentPallets) do
                            Logging.info("[MyTodos]       [%s] type=%s val=%s",
                                tostring(k), type(v), tostring(v))
                            if type(v) == "table" then
                                self:dumpKeys("        keys", v)
                            end
                        end
                    end
                    if type(pal.pallets) == "table" then
                        local cnt = 0
                        for _ in pairs(pal.pallets) do cnt = cnt + 1 end
                        Logging.info("[MyTodos]     pallets count=%d", cnt)
                        for k, v in pairs(pal.pallets) do
                            Logging.info("[MyTodos]       [%s] type=%s val=%s",
                                tostring(k), type(v), tostring(v))
                            if type(v) == "table" then
                                self:dumpKeys("        keys", v)
                                -- Wenn das Pallet-Object ein PlaceableType
                                -- ist, hat es spec_pallet etc. — zeigen wir
                                -- den fillType wenn auffindbar.
                                if v.spec_pallet ~= nil then
                                    self:dumpKeys("        spec_pallet", v.spec_pallet)
                                end
                                if type(v.getFillUnitFillType) == "function" then
                                    local ok, ft = pcall(v.getFillUnitFillType, v, 1)
                                    Logging.info("[MyTodos]        getFillUnitFillType(1) ok=%s ret=%s",
                                        tostring(ok), tostring(ft))
                                end
                            end
                        end
                    end
                end

                -- spec_husbandryAnimals deep
                local anim = p.spec_husbandryAnimals
                if anim ~= nil then
                    Logging.info("[MyTodos]   --- spec_husbandryAnimals deep ---")
                    Logging.info("[MyTodos]     animalTypeIndex=%s configMax=%s baseMax=%s maxNum=%s",
                        tostring(anim.animalTypeIndex),
                        tostring(anim.configMaxNumAnimals),
                        tostring(anim.baseMaxNumAnimals),
                        tostring(anim.maxNumAnimals))
                    if anim.animalType ~= nil then
                        self:dumpKeys("    animalType", anim.animalType)
                    end
                    if type(anim.clusterHusbandry) == "table" then
                        self:dumpKeys("    clusterHusbandry", anim.clusterHusbandry)
                        self:_listClassMethods("    clusterHusbandry", anim.clusterHusbandry)
                    end
                    if type(anim.clusterSystem) == "table" then
                        self:dumpKeys("    clusterSystem", anim.clusterSystem)
                        self:_listClassMethods("    clusterSystem", anim.clusterSystem)
                    end
                    if anim.infoNumAnimals ~= nil then
                        self:dumpKeys("    infoNumAnimals", anim.infoNumAnimals)
                    end
                    if anim.infoHealth ~= nil then
                        self:dumpKeys("    infoHealth", anim.infoHealth)
                    end
                end

                -- spec_husbandryMeadow deep (nur Pasture-Husbandries)
                local meadow = p.spec_husbandryMeadow
                if meadow ~= nil then
                    Logging.info("[MyTodos]   --- spec_husbandryMeadow deep ---")
                    Logging.info("[MyTodos]     eatFilterMaxValue=%s productionWeight=%s",
                        tostring(meadow.eatFilterMaxValue),
                        tostring(meadow.productionWeight))
                    self:_dumpKVTable("fillLevels", meadow.fillLevels)
                    self:_dumpKVTable("capacities", meadow.capacities)
                    if type(meadow.fruitTypeInfos) == "table" then
                        self:dumpKeys("    fruitTypeInfos", meadow.fruitTypeInfos)
                    end
                    if type(meadow.fruitTypeEatFilters) == "table" then
                        self:dumpKeys("    fruitTypeEatFilters", meadow.fruitTypeEatFilters)
                    end
                    if meadow.foodInfo ~= nil then
                        self:dumpKeys("    foodInfo", meadow.foodInfo)
                    end
                end
            end
        end
    end
    return "Husbandry deep probe done - check log"
end

-- Discovery + Task-Derivation ---------------------------------------

function MyTodos:_husbandryName(p)
    local fallback = self:t("myTodos_husb_default_name")
    local anim = p.spec_husbandryAnimals
    if anim == nil or anim.animalType == nil then return fallback end
    local at = anim.animalType
    return at.groupTitle or at.name or fallback
end

function MyTodos:_husbandryNumAnimals(p)
    if type(p.getNumOfAnimals) ~= "function" then return 0 end
    local ok, n = pcall(p.getNumOfAnimals, p)
    if ok and type(n) == "number" then return n end
    return 0
end

-- Lokalisierter Frucht-/FillType-Name analog fruitName.
function MyTodos:_fillTypeLabel(fillTypeIdx)
    if fillTypeIdx == nil or g_fillTypeManager == nil then return "?" end
    local ft = g_fillTypeManager:getFillTypeByIndex(fillTypeIdx)
    if ft == nil then return "?" end
    local raw = ft.title or ft.name or "?"
    if g_i18n ~= nil and g_i18n.hasText ~= nil then
        local key = "fillType_" .. string.lower(raw)
        if g_i18n:hasText(key) then return g_i18n:getText(key) end
    end
    -- Fallback: erste Buchstaben gross
    local s = string.lower(raw)
    return s:sub(1, 1):upper() .. s:sub(2)
end

function MyTodos:collectOwnedHusbandries(farmId)
    local result = {}
    local ps = g_currentMission and g_currentMission.placeableSystem
    if ps == nil or type(ps.placeables) ~= "table" then return result end
    for i, p in ipairs(ps.placeables) do
        if self:_isHusbandryPlaceable(p)
                and self:_placeableOwnerFarmId(p) == farmId then
            table.insert(result, {
                placeable = p,
                index = i,
                name = self:_husbandryName(p),
            })
        end
    end
    table.sort(result, function(a, b) return a.index < b.index end)
    return result
end

-- Liest die Settings-Schwelle als Prozent. Default falls Setting fehlt.
function MyTodos:_pctThreshold(key, default)
    local v = self.settings and self.settings[key]
    if type(v) == "number" then return v end
    return default
end

-- Summe ueber alle fillLevels in einer Spec, plus Capacity. Nutzt
-- spec.fillLevels falls vorhanden, sonst die getter-API auf placeable.
function MyTodos:_specFillRatio(p, spec, capacityField)
    if spec == nil then return nil end
    local cap = spec[capacityField or "capacity"]
    if cap == nil or cap <= 0 then return nil end
    local total = 0
    if type(spec.fillLevels) == "table" then
        for _, lvl in pairs(spec.fillLevels) do
            if type(lvl) == "number" then total = total + lvl end
        end
    end
    return total / cap, total, cap
end

-- Pasture-Weide: fillLevels und capacities sind beide pro fruitType.
function MyTodos:_meadowRatio(meadow)
    if meadow == nil or type(meadow.fillLevels) ~= "table"
            or type(meadow.capacities) ~= "table" then
        return nil
    end
    local totalLvl, totalCap = 0, 0
    for k, v in pairs(meadow.fillLevels) do
        totalLvl = totalLvl + (v or 0)
        totalCap = totalCap + (meadow.capacities[k] or 0)
    end
    if totalCap <= 0 then return nil end
    return totalLvl / totalCap
end

-- Wasser hat keine fillLevels-Tabelle in der Spec. Geht ueber Placeable-API.
function MyTodos:_waterRatio(p, water)
    if water == nil or water.fillType == nil then return nil end
    return self:_filltypeRatio(p, water.fillType)
end

-- Generischer Ratio-Reader fuer einen bestimmten fillType via Placeable-API.
-- Aggregiert ueber alle angeschlossenen Storages (eigene + externe Tanks).
function MyTodos:_filltypeRatio(p, fillTypeIdx)
    if fillTypeIdx == nil
            or type(p.getHusbandryFillLevel) ~= "function"
            or type(p.getHusbandryCapacity) ~= "function" then
        return nil
    end
    local lOk, lvl = pcall(p.getHusbandryFillLevel, p, fillTypeIdx)
    local cOk, cap = pcall(p.getHusbandryCapacity, p, fillTypeIdx)
    if not (lOk and cOk) then return nil end
    if type(lvl) ~= "number" or type(cap) ~= "number" or cap <= 0 then
        return nil
    end
    return lvl / cap
end

-- Cached lookup fuer den FORAGE-fillType (= Totalmischration / TMR). Der
-- kanonische fillType-Name ist "FORAGE" -- per mtProbeHusbandryDeep
-- bestaetigt (der Anzeige-Titel "Totalmischration" ist NICHT der Name).
function MyTodos:_tmrFillTypeIdx()
    if self._tmrFillTypeIdxCached ~= nil then
        if self._tmrFillTypeIdxCached == false then return nil end
        return self._tmrFillTypeIdxCached
    end
    if g_fillTypeManager == nil
            or type(g_fillTypeManager.getFillTypeByName) ~= "function" then
        self._tmrFillTypeIdxCached = false
        return nil
    end
    local ok, ft = pcall(g_fillTypeManager.getFillTypeByName,
        g_fillTypeManager, "FORAGE")
    if not ok or type(ft) ~= "table" or type(ft.index) ~= "number" then
        self._tmrFillTypeIdxCached = false
        return nil
    end
    self._tmrFillTypeIdxCached = ft.index
    return ft.index
end

-- Ratio eines einzelnen fillTypes in einer Futter-Spec, bezogen auf die
-- Gesamt-Futter-Capacity. Liest food.fillLevels/food.capacity direkt
-- (probe-bestaetigt) -- analog zu _specFillRatio, nur fuer einen Typ.
function MyTodos:_foodFillTypeRatio(food, fillTypeIdx)
    if food == nil or fillTypeIdx == nil
            or type(food.fillLevels) ~= "table" then
        return nil
    end
    local cap = food.capacity
    if type(cap) ~= "number" or cap <= 0 then return nil end
    local lvl = food.fillLevels[fillTypeIdx]
    if type(lvl) ~= "number" then lvl = 0 end
    return lvl / cap
end

-- Liefert task-string fuer eine Husbandry, oder nil wenn nichts ansteht.
function MyTodos:deriveHusbandryTask(entry)
    local p = entry.placeable
    local parts = {}

    -- Stall ohne Tiere -> keine Tasks. Futter/Wasser/Mist sind irrelevant
    -- solange niemand eingestallt ist (User-Entscheidung 15.05.2026).
    if self:_husbandryNumAnimals(p) == 0 then
        return nil
    end

    -- Futter. Spezialfall TMR-faehige Husbandries (Kuehe): nur die echte
    -- Totalmischration (FORAGE) zaehlt. Loses Gras/Heu und "gestrecktes"
    -- Futter (FORAGE_*_FAILED) im Trog halten die Kuehe zwar am Leben,
    -- druecken die Produktion aber auf ~40% -- die Summe ueber alle
    -- fillTypes wuerde den Stall faelschlich als satt werten. TMR-
    -- Erkennung: FORAGE steht in food.supportedFillTypes.
    local food = p.spec_husbandryFood
    local tmrIdx = self:_tmrFillTypeIdx()
    local usesTmr = tmrIdx ~= nil and food ~= nil
            and type(food.supportedFillTypes) == "table"
            and food.supportedFillTypes[tmrIdx] == true
    if usesTmr then
        local r = self:_foodFillTypeRatio(food, tmrIdx)
        if r ~= nil
                and r < self:_pctThreshold("foodThreshold", 20) / 100 then
            table.insert(parts, self:t("myTodos_husb_tmr", r * 100))
        end
    else
        local foodRatio = self:_specFillRatio(p, food, "capacity")
        if foodRatio ~= nil
                and foodRatio < self:_pctThreshold("foodThreshold", 20) / 100 then
            table.insert(parts, self:t("myTodos_husb_food", foodRatio * 100))
        end
    end

    -- Wasser (nur wenn manuell)
    local water = p.spec_husbandryWater
    if water ~= nil and water.automaticWaterSupply == false then
        local r = self:_waterRatio(p, water)
        if r ~= nil and r < self:_pctThreshold("waterThreshold", 20) / 100 then
            table.insert(parts, self:t("myTodos_husb_water", r * 100))
        end
    end

    -- Weide (Pasture) -- bei TMR-Husbandries skippen: die Kuehe sind ueber
    -- die TMR versorgt, ein zusaetzlicher Weide-Task waere irrefuehrend.
    if not usesTmr then
        local meadow = p.spec_husbandryMeadow
        local meadowRatio = self:_meadowRatio(meadow)
        if meadowRatio ~= nil
                and meadowRatio < self:_pctThreshold("meadowThreshold", 20) / 100 then
            table.insert(parts, self:t("myTodos_husb_meadow", meadowRatio * 100))
        end
    end

    -- Stroh (Input - "leer = nachfuellen", umgekehrt zu Mist/Guelle)
    local straw = p.spec_husbandryStraw
    if straw ~= nil and straw.inputFillType ~= nil then
        local r = self:_filltypeRatio(p, straw.inputFillType)
        if r ~= nil and r < self:_pctThreshold("strawThreshold", 20) / 100 then
            table.insert(parts, self:t("myTodos_husb_straw", r * 100))
        end
    end

    -- Mist (Output) - kann via straw.outputFillType (wenn isManureActive)
    -- oder eigener spec_husbandryManure kommen.
    local manureFt = nil
    if straw ~= nil and straw.isManureActive and straw.outputFillType ~= nil then
        manureFt = straw.outputFillType
    end
    local manureSpec = p.spec_husbandryManure
    if manureSpec ~= nil and manureSpec.fillType ~= nil then
        manureFt = manureSpec.fillType
    end
    if manureFt ~= nil then
        local r = self:_filltypeRatio(p, manureFt)
        if r ~= nil and r >= self:_pctThreshold("manureThreshold", 80) / 100 then
            table.insert(parts, self:t("myTodos_husb_manure", r * 100))
        end
    end

    -- Guelle (Output)
    local lmanure = p.spec_husbandryLiquidManure
    if lmanure ~= nil and lmanure.fillType ~= nil then
        local r = self:_filltypeRatio(p, lmanure.fillType)
        if r ~= nil and r >= self:_pctThreshold("liquidManureThreshold", 80) / 100 then
            table.insert(parts, self:t("myTodos_husb_liquid_manure", r * 100))
        end
    end

    -- Milch (Output, mehrere fillTypes moeglich - Milchkuehe haben oft
    -- normale Milch (39) und Bio-Milch (41) parallel).
    local milk = p.spec_husbandryMilk
    if milk ~= nil and type(milk.fillTypes) == "table" then
        local milkParts = {}
        for _, ft in pairs(milk.fillTypes) do
            local r = self:_filltypeRatio(p, ft)
            if r ~= nil and r >= self:_pctThreshold("milkThreshold", 80) / 100 then
                local label = self:_fillTypeLabel(ft)
                table.insert(milkParts, string.format("%s %.0f%%", label, r * 100))
            end
        end
        table.sort(milkParts)
        for _, m in ipairs(milkParts) do
            table.insert(parts, m)
        end
    end

    -- Pallets (Wolle / Eier / Ziegenmilch / etc.). Wir sehen nur Pallets
    -- die noch im Spawn-Place der Husbandry stehen (per pal.fillLevels[ft]).
    -- Sobald sie in den Abholbereich verschoben werden (vom Spieler oder
    -- Engine-Trigger), verlieren wir die Sicht. Reicht als "Erinnerung",
    -- weil der Spieler die Pallets visuell sieht wenn er am Stall ist.
    -- "(voll)" wenn palletLimitReached - dann ist Production gestoppt
    -- und sofortiges Abholen noetig.
    local pal = p.spec_husbandryPallets
    if pal ~= nil then
        local entries = {}
        if type(pal.fillLevels) == "table" then
            for ft, lvl in pairs(pal.fillLevels) do
                if type(lvl) == "number" and lvl > 0 then
                    local label = self:_fillTypeLabel(ft)
                    table.insert(entries, {
                        label = label,
                        text = string.format("%s %.0fL", label, lvl),
                    })
                end
            end
        end
        table.sort(entries, function(a, b) return a.label < b.label end)
        if #entries > 0 then
            local texts = {}
            for _, e in ipairs(entries) do table.insert(texts, e.text) end
            local s = table.concat(texts, ", ")
            if pal.palletLimitReached then
                s = s .. self:t("myTodos_husb_pallets_full_suffix")
            end
            table.insert(parts, s)
        elseif pal.palletLimitReached then
            -- Edge case: Limit erreicht direkt nach Pallet-Spawn (Buffer
            -- bereits zurueckgesetzt). Production gestoppt -> Hinweis.
            table.insert(parts, self:t("myTodos_husb_pallets_full"))
        end
    end

    if #parts == 0 then return nil end

    local n = self:_husbandryNumAnimals(p)
    local heading
    if n > 0 then
        heading = string.format("%s (%d)", entry.name, n)
    else
        heading = entry.name
    end
    return string.format("%s - %s", heading, table.concat(parts, ", "))
end

function MyTodos:scanHusbandries(verbose)
    self.husbandryTasks = {}
    self.husbandryOwnedCount = 0
    if self.farmId == nil then return end

    local owned = self:collectOwnedHusbandries(self.farmId)
    self.husbandryOwnedCount = #owned

    for _, entry in ipairs(owned) do
        local task = self:deriveHusbandryTask(entry)
        if task ~= nil then
            table.insert(self.husbandryTasks, { name = entry.name, task = task })
        end
    end

    if verbose then
        Logging.info("[MyTodos] husbandries: %d owned, %d with tasks",
            self.husbandryOwnedCount, #self.husbandryTasks)
        for _, t in ipairs(self.husbandryTasks) do
            Logging.info("[MyTodos]   %s", t.task)
        end
    end
end
