-- Optional integration with Moisture System 2.0.0.5.
-- Records belong to real SC storages, not fabricated Moisture System object IDs.
SCMoisture = {}
local unpackValues = unpack or table.unpack
local function packValues(...) return {n = select("#", ...), ...} end

function SCMoisture.system(fillType)
    local ms = g_currentMission and g_currentMission.MoistureSystem
    if ms == nil or type(ms.shouldTrackFillType) ~= "function"
        or type(ms.getObjectInfo) ~= "function" or type(ms.setObjectInfo) ~= "function"
        or type(ms.getDefaultMoisture) ~= "function" or type(ms.deriveQuality) ~= "function" then
        return nil
    end
    if fillType ~= nil and not ms:shouldTrackFillType(fillType) then return nil end
    return ms
end

function SCMoisture.copy(info)
    if info == nil or type(info.moisture) ~= "number" then return nil end
    return {moisture = info.moisture, quality = info.quality}
end

function SCMoisture.normalize(info, fillType)
    info = SCMoisture.copy(info)
    local ms = SCMoisture.system(fillType)
    if info and info.quality == nil and ms then
        info.quality = ms:deriveQuality(fillType, info.moisture)
    end
    return info
end

function SCMoisture.defaultInfo(fillType)
    local ms = SCMoisture.system(fillType)
    if ms == nil then return nil end
    local moisture = ms:getDefaultMoisture()
    return {moisture = moisture, quality = ms:deriveQuality(fillType, moisture)}
end

function SCMoisture.blend(old, oldLiters, incoming, liters)
    if incoming == nil or liters <= 0 then return SCMoisture.copy(old) end
    if old == nil or oldLiters <= 0 then return SCMoisture.copy(incoming) end
    local total = oldLiters + liters
    return {
        moisture = (old.moisture * oldLiters + incoming.moisture * liters) / total,
        quality = ((old.quality or 100) * oldLiters + (incoming.quality or 100) * liters) / total
    }
end

function SCMoisture.info(storage, fillType)
    local name = g_fillTypeManager:getFillTypeNameByIndex(fillType)
    return SCMoisture.copy(storage.scMoisture and storage.scMoisture[name])
end

function SCMoisture.set(storage, fillType, info)
    local name = g_fillTypeManager:getFillTypeNameByIndex(fillType)
    if name == nil then return end
    storage.scMoisture = storage.scMoisture or {}
    storage.scMoisture[name] = SCMoisture.copy(info)
    if storage.isServer and storage.scMoistureDirtyFlag then
        storage:raiseDirtyFlags(storage.scMoistureDirtyFlag)
    end
end

-- A short-lived context is scoped to one controller and one actual operation.
-- pcall restores it even if another mod's callback fails.
function SCMoisture.withContext(controller, context, callback, ...)
    local previous = controller.scMoistureContext
    controller.scMoistureContext = context
    local result = packValues(pcall(callback, ...))
    controller.scMoistureContext = previous
    if not result[1] then error(result[2], 0) end
    return unpackValues(result, 2, result.n)
end

function SCMoisture.changed(storage, controller, fillType, oldLevel, newLevel, oldInfo)
    if not storage.isServer or oldLevel == newLevel then return end
    local ms = SCMoisture.system(fillType)
    local context = controller.scMoistureContext
    if newLevel < oldLevel then
        if ms and context and context.removed then
            local entry = context.removed[fillType] or {liters = 0}
            local liters = oldLevel - newLevel
            entry.info = SCMoisture.blend(entry.info, entry.liters,
                oldInfo or SCMoisture.defaultInfo(fillType), liters)
            entry.liters = entry.liters + liters
            context.removed[fillType] = entry
        end
        if newLevel <= 0 then SCMoisture.set(storage, fillType, nil) end
    elseif ms then
        local incoming = context and context.incoming and context.incoming[fillType]
        if incoming == nil and context and context.removed and context.removed[fillType] then
            incoming = context.removed[fillType].info
        end
        SCMoisture.set(storage, fillType, SCMoisture.blend(
            oldInfo or SCMoisture.defaultInfo(fillType), oldLevel,
            incoming or SCMoisture.defaultInfo(fillType), newLevel - oldLevel))
    else
        -- Untracked additions invalidate stale history if the mod is disabled.
        SCMoisture.set(storage, fillType, nil)
    end
end

function SCMoisture.write(storage, streamId)
    local names = {}
    for name in pairs(storage.scMoisture or {}) do table.insert(names, name) end
    table.sort(names)
    streamWriteUIntN(streamId, #names, 16)
    for _, name in ipairs(names) do
        local info = storage.scMoisture[name]
        streamWriteString(streamId, name)
        streamWriteFloat32(streamId, info.moisture)
        streamWriteFloat32(streamId, info.quality or 100)
    end
end

function SCMoisture.read(storage, streamId)
    storage.scMoisture = {}
    local count = streamReadUIntN(streamId, 16)
    for _ = 1, count do
        local name = streamReadString(streamId)
        local moisture = streamReadFloat32(streamId)
        local quality = streamReadFloat32(streamId)
        storage.scMoisture[name] = {moisture = moisture, quality = quality}
    end
end

local initializeStorage = SCStorage.initialize
function SCStorage.initialize(data, controller, ...)
    local ok = initializeStorage(data, controller, ...)
    if not ok then return ok end
    local storage = data:getParent()
    storage.scMoisture = {}
    storage.scMoistureDirtyFlag = storage:getNextDirtyFlag()
    local setFillLevel = storage.setFillLevel
    storage.setFillLevel = function(self, level, fillType, ...)
        if level == nil or fillType == nil then return setFillLevel(self, level, fillType, ...) end
        local oldLevel = self:getFillLevel(fillType)
        local oldInfo = SCMoisture.info(self, fillType)
        local result = packValues(setFillLevel(self, level, fillType, ...))
        SCMoisture.changed(self, controller, fillType, oldLevel, self:getFillLevel(fillType), oldInfo)
        return unpackValues(result, 1, result.n)
    end
    local writeStream, readStream = storage.writeStream, storage.readStream
    storage.writeStream = function(self, streamId, connection, ...)
        writeStream(self, streamId, connection, ...)
        if not connection:getIsServer() then SCMoisture.write(self, streamId) end
    end
    storage.readStream = function(self, streamId, connection, ...)
        readStream(self, streamId, connection, ...)
        if connection:getIsServer() then SCMoisture.read(self, streamId) end
    end
    local writeUpdate, readUpdate = storage.writeUpdateStream, storage.readUpdateStream
    storage.writeUpdateStream = function(self, streamId, connection, dirtyMask, ...)
        writeUpdate(self, streamId, connection, dirtyMask, ...)
        if not connection:getIsServer() then
            local changed = bitAND(dirtyMask, self.scMoistureDirtyFlag) ~= 0
            streamWriteBool(streamId, changed)
            if changed then SCMoisture.write(self, streamId) end
        end
    end
    storage.readUpdateStream = function(self, streamId, timestamp, connection, ...)
        readUpdate(self, streamId, timestamp, connection, ...)
        if connection:getIsServer() and streamReadBool(streamId) then SCMoisture.read(self, streamId) end
    end
    return ok
end

local registerSave = SCStorage.registerSavegameXMLPaths
function SCStorage.registerSavegameXMLPaths(schema, path)
    registerSave(schema, path)
    local key = path .. "." .. g_thMain.xmlDataKey .. ".moisture.crop(?)"
    schema:register(XMLValueType.STRING, key .. "#fillType", "Moisture crop name")
    schema:register(XMLValueType.FLOAT, key .. "#value", "Moisture fraction")
    schema:register(XMLValueType.FLOAT, key .. "#quality", "Crop quality")
end

local loadController = SCStateController.loadFromXMLFile
function SCStateController:loadFromXMLFile(xmlFile, key)
    local result = loadController(self, xmlFile, key)
    xmlFile:iterate(key .. ".storages.storage", function(_, storageKey)
        local dataKey = storageKey .. "." .. g_thMain.xmlDataKey
        local storage = self:getStorage(xmlFile:getValue(dataKey .. "#id"))
        if storage then
            storage.scMoisture = {}
            xmlFile:iterate(dataKey .. ".moisture.crop", function(_, cropKey)
                local name = xmlFile:getValue(cropKey .. "#fillType")
                local fillType = name and g_fillTypeManager:getFillTypeIndexByName(name)
                local value = xmlFile:getValue(cropKey .. "#value")
                local quality = xmlFile:getValue(cropKey .. "#quality", 100)
                if fillType and value and value >= 0 and value <= 1 and quality >= 0
                    and quality <= 100 and storage:getFillLevel(fillType) > 0 then
                    SCMoisture.set(storage, fillType, {moisture = value, quality = quality})
                end
            end)
        end
    end)
    return result
end

local saveController = SCStateController.saveToXMLFile
function SCStateController:saveToXMLFile(xmlFile, key, ...)
    local result = saveController(self, xmlFile, key, ...)
    local storages = self:getStorageList()
    for index, storage in ipairs(storages) do
        local base = string.format("%s.storages.storage(%d).%s.moisture.crop", key, index - 1, g_thMain.xmlDataKey)
        local cropIndex = 0
        for name, info in pairs(storage.scMoisture or {}) do
            local fillType = g_fillTypeManager:getFillTypeIndexByName(name)
            if fillType and storage:getFillLevel(fillType) > 0 then
                local cropKey = string.format("%s(%d)", base, cropIndex)
                xmlFile:setValue(cropKey .. "#fillType", name)
                xmlFile:setValue(cropKey .. "#value", info.moisture)
                xmlFile:setValue(cropKey .. "#quality", info.quality or 100)
                cropIndex = cropIndex + 1
            end
        end
    end
    return result
end

local initializeIntake = SCSellingStation.initialize
function SCSellingStation.initialize(data, controller, ...)
    local ok = initializeIntake(data, controller, ...)
    if not ok then return ok end
    local station = data:getParent()
    local add = station.addFillLevelFromTool
    station.addFillLevelFromTool = function(self, farmId, delta, fillType, fillInfo, toolType, attributes)
        local ms = self.isServer and SCMoisture.system(fillType)
        if not ms then return add(self, farmId, delta, fillType, fillInfo, toolType, attributes) end
        local sourceId = fillInfo and (fillInfo.sourceUniqueId or (fillInfo.sourceObject and fillInfo.sourceObject.uniqueId))
        local incoming = sourceId and SCMoisture.normalize(ms:getObjectInfo(sourceId, fillType), fillType)
        return SCMoisture.withContext(controller, {incoming = {[fillType] = incoming}},
            add, self, farmId, delta, fillType, fillInfo, toolType, attributes)
    end
    return ok
end

function SCMoisture.stationInfo(station, fillType)
    local info, liters = nil, 0
    for storage in pairs(station.sourceStorages or {}) do
        local level = storage:getFillLevel(fillType)
        if level > 0 then
            info = SCMoisture.blend(info, liters, SCMoisture.info(storage, fillType)
                or SCMoisture.defaultInfo(fillType), level)
            liters = liters + level
        end
    end
    return info
end

local initializeOutlet = SCLoadingStation.initialize
function SCLoadingStation.initialize(data, controller, ...)
    local ok = initializeOutlet(data, controller, ...)
    if not ok then return ok end
    local station = data:getParent()
    local add = station.addFillLevelToFillableObject
    station.addFillLevelToFillableObject = function(self, target, unit, fillType, delta, ...)
        local ms = self.isServer and SCMoisture.system(fillType)
        if not ms or target.uniqueId == nil then return add(self, target, unit, fillType, delta, ...) end
        local before = target:getFillUnitFillLevel(unit)
        local old = SCMoisture.normalize(ms:getObjectInfo(target.uniqueId, fillType), fillType)
        local incoming = SCMoisture.stationInfo(self, fillType)
        local context = {removed = {}}
        local amount = SCMoisture.withContext(controller, context, add, self, target, unit, fillType, delta, ...)
        if amount and amount > 0 then
            local removed = context.removed[fillType]
            incoming = removed and removed.info or incoming
            if incoming then
                -- Replace the pooled-placeable result from Moisture System using
                -- the target's pre-transfer state, avoiding double averaging.
                ms:setObjectInfo(target.uniqueId, fillType, SCMoisture.blend(
                    old or SCMoisture.defaultInfo(fillType), before, incoming, amount))
            end
        end
        return amount
    end
    return ok
end

function SCMoisture.beginRecipe(controller, recipeId)
    local previous = controller.scMoistureContext
    if controller.isServer and SCMoisture.system() and recipeId == "SC_FILLTYPE_MOVER" then
        controller.scMoistureContext = {removed = {}}
    end
    return previous
end

function SCMoisture.endRecipe(controller, previous)
    controller.scMoistureContext = previous
end

-- Clear a recipe's context on errors as well as on successful updates.
local updateProduction = SCProductionPoint.onUpdateProductionFinished
function SCProductionPoint:onUpdateProductionFinished(...)
    return SCMoisture.withContext(self.stateController, self.stateController.scMoistureContext,
        updateProduction, self, ...)
end

function SCMoisture.hudText(storage, fillType)
    if not SCMoisture.system(fillType) then return "" end
    local info = SCMoisture.info(storage, fillType)
    if not info then return " | --%" end
    return string.format(" | %.1f%%", info.moisture * 100)
end
