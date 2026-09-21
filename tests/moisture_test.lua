-- Run with: texlua tests/moisture_test.lua (or Lua 5.3+).
unpack = table.unpack
local function equal(a, b, label)
    assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b) assert(math.abs(a - b) < 0.000001, tostring(a) .. " ~= " .. tostring(b)) end
local checks = 0
local function test(name, callback)
    callback()
    checks = checks + 1
    print("PASS " .. name)
end
local names = {[1] = "MAIZE", [2] = "WHEAT", [3] = "PROPANE"}
g_fillTypeManager = {
    getFillTypeNameByIndex = function(_, i) return names[i] end,
    getFillTypeIndexByName = function(_, name)
        for i, n in pairs(names) do if n == name then return i end end
    end
}
g_currentMission = {}
local records = {}
local ms = {
    shouldTrackFillType = function(_, ft) return ft == 1 or ft == 2 end,
    getObjectInfo = function(_, id, ft) return records[id] and records[id][ft] end,
    setObjectInfo = function(_, id, ft, info)
        records[id] = records[id] or {}; records[id][ft] = info
    end,
    getDefaultMoisture = function() return 0.18 end,
    deriveQuality = function() return 70 end
}
function bitAND(a, b) return math.floor(a / b) % 2 * b end
function Class(class, parent)
    class.superClass = function() return parent end
    return {__index = class}
end
THData = {getParent = function(self) return self.parent end}
THUtils = {
    argIsValid = function(value) return value end,
    getIsType = function() return true end
}
g_thMain = {
    xmlDataKey = "thStateController",
    setFunctionHook = function(_, parent, name, class, _, data)
        local original = parent[name]
        parent[name] = function(self, ...) return class["hook_" .. name](data, original, self, ...) end
    end,
    call = function(_, callback, ...) return callback(...) end
}
SCStateController = {
    loadFromXMLFile = function() return true end,
    saveToXMLFile = function() return true end
}
SCProductionPoint = {onUpdateProductionFinished = function(self)
    self.stateController.scMoistureContext = {leaked = true}
    error("simulated production failure")
end}
-- Station initialization is stubbed; storage validation uses the real SCStorage.
SCSellingStation = {initialize = function() return true end}
SCLoadingStation = {initialize = function() return true end}
Storage = {registerSavegameXMLPaths = function() end}
XMLValueType = {STRING = 1, FLOAT = 2}
dofile("scripts/objects/SCStorage.lua")
dofile("scripts/objects/SCMoisture.lua")

local function controller()
    return setmetatable({isServer = true, bins = {}, ids = {}}, {__index = SCStateController})
end
function SCStateController:getStorageList() return self.bins, #self.bins end
function SCStateController:getStorage(id) return self.ids[id] end
local function bin(c, id, capacity, isServer)
    local s = {
        isServer = isServer ~= false, levels = {}, capacity = capacity or 1000,
        supportsMultipleFillTypes = false, dirty = 0, storageDirtyFlag = 1,
        load = function() return true end,
        getNextDirtyFlag = function() return 2 end,
        raiseDirtyFlags = function(self, flag) self.dirty = flag end,
        getFillLevel = function(self, ft) return self.levels[ft] or 0 end,
        getFillLevels = function(self) return self.levels end,
        setFillLevel = function(self, amount, ft)
            self.levels[ft] = math.max(0, math.min(self.capacity, amount)); return "original result"
        end,
        writeStream = function() end, readStream = function() end,
        writeUpdateStream = function() end, readUpdateStream = function() end
    }
    local data = setmetatable({parent = s}, SCStorage_mt)
    assert(SCStorage.initialize(data, c))
    c.ids[id] = s; table.insert(c.bins, s)
    return s
end
local function intake(c)
    local s = {isServer = true, addFillLevelFromTool = function(_, _, amount, ft)
        local left = amount
        for _, b in ipairs(c.bins) do
            local old = b:getFillLevel(ft)
            b:setFillLevel(old + left, ft)
            left = left - (b:getFillLevel(ft) - old)
        end
        return amount - left
    end}
    assert(SCSellingStation.initialize({getParent = function() return s end}, c))
    return s
end
local function deposit(c, source, amount, ft)
    return intake(c):addFillLevelFromTool(1, amount, ft or 1, {sourceUniqueId = source}, 0)
end
local function source(id, m, q) ms:setObjectInfo(id, 1, {moisture = m, quality = q}) end
source("wet", 0.24, 50); source("dry", 0.14, 95)

test("without Moisture System: existing capacity and single-crop rules", function()
    local c = controller(); local b = bin(c, "BIN1", 100)
    equal(deposit(c, "wet", 130), 100)
    equal(b:getFillLevel(1), 100); equal(next(b.scMoisture), nil)
    b:setFillLevel(60, 2); equal(b:getFillLevel(2), 0)
    equal(SCMoisture.hudText(b, 1), "")
end)
g_currentMission.MoistureSystem = ms
test("separate bins keep separate moisture and quality", function()
    local c1, c2 = controller(), controller()
    local wet, dry = bin(c1, "BIN1"), bin(c2, "BIN2")
    deposit(c1, "wet", 100); deposit(c2, "dry", 200)
    near(SCMoisture.info(wet, 1).moisture, 0.24)
    near(SCMoisture.info(dry, 1).moisture, 0.14)
    equal(SCMoisture.info(wet, 1).quality, 50)
    equal(SCMoisture.hudText(wet, 1), " | 24.0%")
end)
test("accepted liters, full bins, overflow, rejected crops", function()
    local c = controller(); local a = bin(c, "A", 100); local b = bin(c, "B", 100)
    deposit(c, "dry", 50); equal(deposit(c, "wet", 200), 150)
    near(SCMoisture.info(a, 1).moisture, 0.19)
    near(SCMoisture.info(a, 1).quality, 72.5)
    near(SCMoisture.info(b, 1).moisture, 0.24)
    equal(deposit(c, "wet", 10, 2), 0); equal(SCMoisture.info(a, 2), nil)
end)
test("mover drains an entire source and blends into destination", function()
    local c = controller(); local a = bin(c, "A"); local b = bin(c, "B")
    a:setFillLevel(100, 1); b:setFillLevel(200, 1)
    SCMoisture.set(a, 1, {moisture = 0.24, quality = 50})
    SCMoisture.set(b, 1, {moisture = 0.14, quality = 95})
    local previous = SCMoisture.beginRecipe(c, "SC_FILLTYPE_MOVER")
    a:setFillLevel(0, 1); b:setFillLevel(300, 1)
    SCMoisture.endRecipe(c, previous)
    equal(SCMoisture.info(a, 1), nil)
    near(SCMoisture.info(b, 1).moisture, (100 * 0.24 + 200 * 0.14) / 300)
    near(SCMoisture.info(b, 1).quality, 80)
    equal(c.scMoistureContext, nil)
end)
test("multiple source bins use actual removed amounts", function()
    local c = controller(); local a = bin(c, "A"); local b = bin(c, "B"); local dest = bin(c, "C")
    a:setFillLevel(100, 1); b:setFillLevel(900, 1)
    SCMoisture.set(a, 1, {moisture = 0.24, quality = 50})
    SCMoisture.set(b, 1, {moisture = 0.14, quality = 95})
    local p = SCMoisture.beginRecipe(c, "SC_FILLTYPE_MOVER")
    a:setFillLevel(0, 1); b:setFillLevel(850, 1); dest:setFillLevel(150, 1)
    SCMoisture.endRecipe(c, p)
    near(SCMoisture.info(dest, 1).moisture, (100 * 0.24 + 50 * 0.14) / 150)
end)
test("trailer receives actual withdrawn crop, replacing pooled result once", function()
    local c = controller(); local a = bin(c, "A"); local b = bin(c, "B")
    a:setFillLevel(100, 1); b:setFillLevel(900, 1)
    SCMoisture.set(a, 1, {moisture = 0.24, quality = 50})
    SCMoisture.set(b, 1, {moisture = 0.14, quality = 95})
    local target = {uniqueId = "trailer", liters = 50, getFillUnitFillLevel = function(self) return self.liters end}
    source("trailer", 0.14, 95)
    local station = {isServer = true, sourceStorages = {[a] = true, [b] = true},
        addFillLevelToFillableObject = function(_, t, _, ft, delta)
            a:setFillLevel(a:getFillLevel(ft) - delta, ft); t.liters = t.liters + delta
            ms:setObjectInfo(t.uniqueId, ft, {moisture = 0.1, quality = 100})
            return delta
        end}
    assert(SCLoadingStation.initialize({getParent = function() return station end}, c))
    equal(station:addFillLevelToFillableObject(target, 1, 1, 100), 100)
    near(ms:getObjectInfo("trailer", 1).moisture, (50 * 0.14 + 100 * 0.24) / 150)
    near(ms:getObjectInfo("trailer", 1).quality, 65)
    equal(SCMoisture.info(a, 1), nil)
end)
test("disabled mod clears history on additions but preserves untouched bins", function()
    local c = controller(); local a = bin(c, "A"); local b = bin(c, "B")
    a:setFillLevel(20, 1); b:setFillLevel(20, 1)
    g_currentMission.MoistureSystem = nil
    a:setFillLevel(30, 1)
    equal(SCMoisture.info(a, 1), nil); assert(SCMoisture.info(b, 1))
    g_currentMission.MoistureSystem = ms
end)
test("untracked propane has no moisture", function()
    local c = controller(); local b = bin(c, "GAS")
    deposit(c, "wet", 50, 3); equal(SCMoisture.info(b, 3), nil)
end)
test("context cleanup survives nested callback and production errors", function()
    local c = controller(); c.scMoistureContext = {original = true}
    local original = c.scMoistureContext
    local ok = pcall(SCMoisture.withContext, c, {}, function() error("simulated failure") end)
    equal(ok, false); equal(c.scMoistureContext, original)
    ok = pcall(SCProductionPoint.onUpdateProductionFinished, {stateController = c})
    equal(ok, false); equal(c.scMoistureContext, original)
end)
local function xml()
    return {
        values = {},
        setValue = function(self, key, value) self.values[key] = value end,
        getValue = function(self, key, default)
            local v = self.values[key]; if v == nil then return default end; return v
        end,
        iterate = function(self, base, callback)
            local i = 0
            while true do
                local key, found = base .. "(" .. i .. ")", false
                for path in pairs(self.values) do
                    if path:sub(1, #key) == key then found = true; break end
                end
                if not found then break end
                callback(i, key); i = i + 1
            end
        end
    }
end
test("save/load resolves storage ID, not array order, also with mod disabled", function()
    local c = controller(); local a = bin(c, "A"); local b = bin(c, "B")
    a:setFillLevel(50, 1); b:setFillLevel(60, 1)
    SCMoisture.set(a, 1, {moisture = 0.24, quality = 50})
    SCMoisture.set(b, 1, {moisture = 0.14, quality = 95})
    local x = xml()
    x:setValue("sc.storages.storage(0).thStateController#id", "A")
    x:setValue("sc.storages.storage(1).thStateController#id", "B")
    c:saveToXMLFile(x, "sc")
    c.bins = {b, a}; a.scMoisture = {}; b.scMoisture = {}
    g_currentMission.MoistureSystem = nil
    c:loadFromXMLFile(x, "sc")
    near(SCMoisture.info(a, 1).moisture, 0.24); near(SCMoisture.info(b, 1).moisture, 0.14)
    g_currentMission.MoistureSystem = ms
end)
local function write(s, v) table.insert(s, v) end
local function read(s) s.pos = (s.pos or 0) + 1; return s[s.pos] end
streamWriteUIntN = write; streamWriteString = write; streamWriteFloat32 = write; streamWriteBool = write
streamReadUIntN = read; streamReadString = read; streamReadFloat32 = read; streamReadBool = read
local clientConnection = {getIsServer = function() return false end}
local serverConnection = {getIsServer = function() return true end}
test("initial and dirty network streams synchronize values and empty records", function()
    local c = controller(); local a = bin(c, "A"); local client = bin(c, "CLIENT", 1000, false)
    a:setFillLevel(50, 1); SCMoisture.set(a, 1, {moisture = 0.24, quality = 50})
    local s = {}; a:writeStream(s, clientConnection); client:readStream(s, serverConnection)
    near(SCMoisture.info(client, 1).moisture, 0.24)
    a:setFillLevel(0, 1)
    s = {}; a:writeUpdateStream(s, clientConnection, a.dirty)
    client:readUpdateStream(s, 0, serverConnection); equal(next(client.scMoisture), nil)
    s = {}; a:writeUpdateStream(s, clientConnection, 0)
    equal(#s, 1); equal(s[1], false)
end)
if arg[1] then
    test("uploaded Moisture System loading hook and SC wrapper compose correctly", function()
        Utils = {overwrittenFunction = function(original, override)
            return function(self, ...) return override(self, original, ...) end
        end}
        MSStorageHeapExtension = {isStorageHeap = function() return false end}
        ms.getObjectMoisture = function(self, id, ft)
            local info = self:getObjectInfo(id, ft); return info and info.moisture
        end
        ms.transferObjectMoisture = function(self, sourceId, targetId, amount, before, ft)
            self:setObjectInfo(targetId, ft, SCMoisture.blend(self:getObjectInfo(targetId, ft), before,
                self:getObjectInfo(sourceId, ft) or {moisture = 0.14, quality = 100}, amount))
        end
        local c = controller(); local b = bin(c, "BIN")
        deposit(c, "wet", 100)
        LoadingStation = {addFillLevelToFillableObject = function(_, target, unit, ft, amount)
            b:setFillLevel(b:getFillLevel(ft) - amount, ft)
            target.liters = target.liters + amount
            return amount
        end}
        dofile(arg[1] .. "/src/extensions/LoadingStationExtension.lua")
        local outlet = setmetatable({isServer = true, sourceStorages = {[b] = true},
            owningPlaceable = {uniqueId = "GSI"}}, {__index = LoadingStation})
        SCLoadingStation.initialize({getParent = function() return outlet end}, c)
        local target = {uniqueId = "realHookTrailer", liters = 0,
            getFillUnitFillLevel = function(self) return self.liters end}
        equal(outlet:addFillLevelToFillableObject(target, 1, 1, 100), 100)
        near(ms:getObjectInfo(target.uniqueId, 1).moisture, 0.24)
        near(ms:getObjectInfo(target.uniqueId, 1).quality, 50)
    end)
    test("uploaded selling hook respects skip-sell and passes source moisture", function()
        local c = controller(); local b = bin(c, "BIN")
        SellingStation = {
            addFillLevelFromTool = function(_, _, amount, ft)
                b:setFillLevel(b:getFillLevel(ft) + amount, ft); return amount
            end,
            getSkipSell = function() return true end
        }
        g_currentMission.getIsServer = function() return true end
        CropValueMap = {Data = {}, getQualityGrade = function() return "C", 0.7 end,
            getIdealRange = function() return 0.13, 0.15 end}
        ms.settings = {sellDryingChargeRate = 1}
        dofile(arg[1] .. "/src/extensions/SellingStationExtension.lua")
        local station = setmetatable({isServer = true}, {__index = SellingStation})
        SCSellingStation.initialize({getParent = function() return station end}, c)
        equal(station:addFillLevelFromTool(1, 100, 1, {sourceUniqueId = "wet"}, 0), 100)
        near(SCMoisture.info(b, 1).moisture, 0.24)
        equal(SellingStationExtension.dryingChargeAccumulator, 0)
    end)
end
dofile("scripts/objects/SCMoistureDryer.lua")
SCStateController.STATE_TYPE = {INPUT = 1, OUTPUT = 2}
SCProductionPoint.RECIPE_TYPE = {NORMAL = 0}
ProductionPoint = {PROD_STATUS = {MISSING_INPUTS = 1, RUNNING = 2, NO_OUTPUT_SPACE = 3}}
local function dryingSetup(moisture, fuelLevel)
    local c = controller()
    local wet = bin(c, "BIN01", 10000)
    local other = bin(c, "BIN04", 10000)
    local fuel = bin(c, "TANK01", 10000)
    wet:setFillLevel(1000, 1); other:setFillLevel(1000, 1); fuel:setFillLevel(fuelLevel or 100, 3)
    SCMoisture.set(wet, 1, {moisture = moisture or 0.24, quality = 50})
    SCMoisture.set(other, 1, {moisture = 0.24, quality = 50})
    c.selected = other
    c.getActiveStorageList = function(self, stateType)
        if stateType == SCStateController.STATE_TYPE.OUTPUT then return self.outputs or {} end
        return {self.selected}
    end
    c.getCanAccessStorage = function(_, storage) return not storage.denied end
    c.getIsStorageActive = function(self, storage) return storage == self.selected end
    local parent = {
        isOwned = true, productionCostsToClaim = 0, enabled = true,
        owningPlaceable = {productionStatusChanged = function() end},
        setProductionStatus = function() end,
        setProductionState = function(self, _, enabled) self.enabled = enabled end
    }
    local data = {isServer = true, stateController = c, getParent = function() return parent end,
        i18n = {getText = function() return "Moisture drying" end}}
    local recipe = {id = "GRAIN_DRYER", inputs = {}, outputs = {}, costsPerActiveMinute = 20 / 60}
    local rd = {}
    assert(SCMoistureDryer.configure(data, recipe, rd, xml(), "recipe", "FS25_GSI_SILOS"))
    return data, recipe, rd, wet, other, fuel, parent
end
test("crop tracking becomes ready after recipe loading: 1000L at 20.2% dries", function()
    local data, recipe, _, wet, other, fuel, parent = dryingSetup(0.202)
    fuel.capacity = 80000
    fuel:setFillLevel(80000, 3)
    local originalTracking = ms.shouldTrackFillType
    ms.shouldTrackFillType = function() return false end
    local rd = {}
    assert(SCMoistureDryer.configure(data, recipe, rd, xml(), "recipe", "FS25_GSI_SILOS"))
    -- Recipe setup happens before MS:onStartMission initializes CropValueMap.
    SCMoistureDryer.update(data, recipe, rd, 0.1, {})
    near(fuel:getFillLevel(3), 80000)
    near(SCMoisture.info(wet, 1).moisture, 0.202)
    ms.shouldTrackFillType = originalTracking
    SCMoistureDryer.update(data, recipe, rd, 0.1, {})
    near(SCMoisture.info(wet, 1).moisture, 0.20)
    near(fuel:getFillLevel(3), 79999.6)
    equal(wet:getFillLevel(1), 1000)
    near(SCMoisture.info(other, 1).moisture, 0.24)
    equal(parent.enabled, true) -- waits for an output bin
end)
test("GSI profile only dries BIN01 despite another input being selected", function()
    local data, recipe, rd, wet, other, fuel, parent = dryingSetup()
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    near(SCMoisture.info(wet, 1).moisture, 0.22)
    near(SCMoisture.info(other, 1).moisture, 0.24)
    equal(wet:getFillLevel(1), 1000); equal(other:getFillLevel(1), 1000)
    near(fuel:getFillLevel(3), 96); near(parent.productionCostsToClaim, 20)
    equal(SCMoisture.info(wet, 1).quality, 50)
    equal(recipe.outputs[1].type, 1)
end)
test("no propane means no drying or operating charge", function()
    local data, recipe, rd, wet, _, fuel, parent = dryingSetup(0.24, 0)
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    near(SCMoisture.info(wet, 1).moisture, 0.24)
    equal(parent.productionCostsToClaim, 0); equal(fuel:getFillLevel(3), 0)
    equal(recipe.status, ProductionPoint.PROD_STATUS.MISSING_INPUTS)
end)
test("insufficient propane scales drying and operating charge", function()
    local data, recipe, rd, wet, _, fuel, parent = dryingSetup(0.24, 2)
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    near(SCMoisture.info(wet, 1).moisture, 0.23)
    near(parent.productionCostsToClaim, 10); near(fuel:getFillLevel(3), 0)
end)
test("target clamp stops drying and only charges the final fraction", function()
    local data, recipe, rd, wet, _, fuel, parent = dryingSetup(0.205)
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    near(SCMoisture.info(wet, 1).moisture, 0.20)
    near(fuel:getFillLevel(3), 99); near(parent.productionCostsToClaim, 5)
    equal(parent.enabled, true) -- waits for an output bin
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    near(fuel:getFillLevel(3), 99); near(parent.productionCostsToClaim, 5)
end)
test("two dryer recipes cannot double-dry the same wet bin", function()
    local data, recipe, rd, wet, _, fuel, parent = dryingSetup()
    local processed = {}
    SCMoistureDryer.update(data, recipe, rd, 1, processed)
    SCMoistureDryer.update(data, {id = "CORN_DRYER"}, rd, 1, processed)
    near(SCMoisture.info(wet, 1).moisture, 0.22)
    near(fuel:getFillLevel(3), 96); near(parent.productionCostsToClaim, 20)
end)
test("missing wet bin does not fall back to another bin", function()
    local data, recipe, rd, _, other, fuel, parent = dryingSetup()
    data.stateController.ids.BIN01 = nil
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    near(SCMoisture.info(other, 1).moisture, 0.24)
    near(fuel:getFillLevel(3), 100); equal(parent.productionCostsToClaim, 0)
end)
test("unknown moisture and dry grain do not consume propane", function()
    local data, recipe, rd, wet, _, fuel = dryingSetup(0.12)
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    near(fuel:getFillLevel(3), 100)
    SCMoisture.set(wet, 1, nil)
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    near(fuel:getFillLevel(3), 100); equal(SCMoisture.info(wet, 1), nil)
end)
test("client never changes moisture, propane or money", function()
    local data, recipe, rd, wet, _, fuel, parent = dryingSetup()
    data.isServer = false
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    near(SCMoisture.info(wet, 1).moisture, 0.24)
    near(fuel:getFillLevel(3), 100); equal(parent.productionCostsToClaim, 0)
end)
test("MS disabled keeps legacy recipe and blocks drying from other bins", function()
    local data, _, _, wet, other = dryingSetup()
    local recipe = {id = "CORN_DRYER", inputs = {{type = 1}}, outputs = {{type = 4}}}
    local inputs, outputs = recipe.inputs, recipe.outputs
    local rd = {}
    g_currentMission.MoistureSystem = nil
    equal(SCMoistureDryer.configure(data, recipe, rd, xml(), "recipe", "FS25_GSI_SILOS"), false)
    equal(recipe.inputs, inputs); equal(recipe.outputs, outputs); equal(rd.moistureDryer, nil)
    data.stateController.selected = other
    equal(SCMoistureDryer.isBlockedLegacy(data, rd), true)
    data.stateController.selected = wet
    equal(SCMoistureDryer.isBlockedLegacy(data, rd), false)
    g_currentMission.MoistureSystem = ms
end)
test("unrelated mods do not get the GSI profile", function()
    local data, recipe = dryingSetup()
    local rd = {}
    equal(SCMoistureDryer.configure(data, recipe, rd, xml(), "recipe", "OtherMod"), false)
    equal(rd.moistureDryer, nil); equal(rd.legacyDryerStorageId, nil)
end)
test("real production loop uses the dryer branch instead of consuming grain", function()
    dofile("scripts/objects/SCProductionPoint.lua")
    local data, recipe, rd, wet, _, fuel = dryingSetup()
    local parent = data:getParent()
    parent.getOwnerFarmId = function() return 1 end
    parent.getIsProductionEnabled = function(self) return self.enabled end
    parent.minuteFactorTimescaled = 1 / 1000
    parent.activeProductions = {recipe}
    data.getProductionRecipeList = function() return {recipe}, 1 end
    data.getProductionRecipe = function() return recipe, rd end
    data.updateProductionRecipes = function() end
    g_currentMission.environment = {timeAdjustment = 1}
    g_time = 60000
    SCProductionPoint.onUpdateProductionFinished(data, 60000)
    equal(wet:getFillLevel(1), 1000); near(SCMoisture.info(wet, 1).moisture, 0.22)
    near(fuel:getFillLevel(3), 96)
end)
local function outputBin(data, capacity)
    local b = bin(data.stateController, "OUTPUT", capacity or 10000)
    b.getFreeCapacity = function(self, ft) return self.capacity - self:getFillLevel(ft) end
    data.stateController.outputs = {b}
    return b
end
test("dryer transfers the finished batch with moisture and quality intact", function()
    local data, recipe, rd, wet, other, fuel, parent = dryingSetup(0.202)
    local output = outputBin(data)
    SCMoistureDryer.update(data, recipe, rd, 0.05, {})
    equal(output:getFillLevel(1), 0); equal(wet:getFillLevel(1), 1000)
    SCMoistureDryer.update(data, recipe, rd, 0.05, {})
    equal(wet:getFillLevel(1), 0); equal(output:getFillLevel(1), 1000)
    near(SCMoisture.info(output, 1).moisture, 0.20)
    equal(SCMoisture.info(output, 1).quality, 50)
    near(fuel:getFillLevel(3), 99.6); equal(parent.enabled, false)
    equal(other:getFillLevel(1), 1000)
end)
test("previously dried 15% corn transfers without fuel or rehydration", function()
    local data, recipe, rd, wet, _, fuel, parent = dryingSetup(0.15)
    local output = outputBin(data)
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    equal(wet:getFillLevel(1), 0); equal(output:getFillLevel(1), 1000)
    near(SCMoisture.info(output, 1).moisture, 0.15)
    equal(fuel:getFillLevel(3), 100); equal(parent.productionCostsToClaim, 0)
end)
test("partial output waits then follows a new output without using more fuel", function()
    local data, recipe, rd, wet, _, fuel, parent = dryingSetup(0.20)
    local first = outputBin(data, 400)
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    equal(first:getFillLevel(1), 400); equal(wet:getFillLevel(1), 600)
    equal(recipe.status, ProductionPoint.PROD_STATUS.NO_OUTPUT_SPACE)
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    equal(wet:getFillLevel(1), 600); equal(fuel:getFillLevel(3), 100)
    local second = outputBin(data)
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    equal(second:getFillLevel(1), 600); equal(wet:getFillLevel(1), 0)
    equal(parent.enabled, false); equal(fuel:getFillLevel(3), 100)
end)
test("another crop, same bin, and inaccessible output never lose grain", function()
    local data, recipe, rd, wet = dryingSetup(0.20)
    local output = outputBin(data)
    output:setFillLevel(100, 2)
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    equal(wet:getFillLevel(1), 1000); equal(output:getFillLevel(1), 0)
    equal(output:getFillLevel(2), 100)
    near(SCMoisture.info(wet, 1).moisture, 0.20)
    data.stateController.outputs = {wet}
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    equal(wet:getFillLevel(1), 1000)
    output = outputBin(data); output.denied = true
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    equal(wet:getFillLevel(1), 1000); equal(output:getFillLevel(1), 0)
end)
test("output blends with existing corn by actual transferred liters", function()
    local data, recipe, rd, wet = dryingSetup(0.20)
    local output = outputBin(data)
    output:setFillLevel(1000, 1)
    SCMoisture.set(output, 1, {moisture = 0.13, quality = 90})
    SCMoistureDryer.update(data, recipe, rd, 1, {})
    equal(output:getFillLevel(1), 2000); equal(wet:getFillLevel(1), 0)
    near(SCMoisture.info(output, 1).moisture, 0.165)
    near(SCMoisture.info(output, 1).quality, 70)
end)
test("mover recipe excludes propane unsupported by the output state", function()
    local rd = {type = SCProductionPoint.RECIPE_TYPE.SPECIAL, baseAmount = 100,
        isInitialized = true, baseFillType = 1}
    local recipe = {id = "SC_FILLTYPE_MOVER", inputs = {}, outputs = {}}
    local c = {
        getActiveFillTypeList = function() return {1, 3}, 2 end,
        getStorageValue = function(_, _, _, ft) return ft == 1 and 1000 or 80000 end,
        getIsFillTypeActive = function(_, ft) return ft == 1 end
    }
    local data = {isServer = true, stateController = c,
        getParent = function() return {} end,
        getSpecialRecipe = function() return recipe end,
        messageCenter = {publish = function() end}}
    local getDataTable = g_thMain.getDataTable
    g_thMain.getDataTable = function() return rd end
    THUtils.clearTable = function(t) for k in pairs(t) do t[k] = nil end; return t end
    THUtils.round = function(n) return n end
    SCProductionPoint.updateSpecialRecipes(data, recipe.id, true)
    g_thMain.getDataTable = getDataTable
    equal(#recipe.inputs, 1); equal(recipe.inputs[1].type, 1)
    equal(#recipe.outputs, 1); equal(recipe.outputs[1].type, 1)
end)
print(string.format("%d tests passed", checks))
