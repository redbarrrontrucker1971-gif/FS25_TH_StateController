-- In-place moisture drying. The original recipes are untouched when MS is absent.
SCMoistureDryer = {}

function SCMoistureDryer.registerXMLPaths(schema, path)
    path = path .. ".moistureDrying"
    schema:register(XMLValueType.BOOL, path .. "#enabled", "Use optional moisture drying")
    schema:register(XMLValueType.STRING, path .. "#fillType", "Grain fill type", "MAIZE")
    schema:register(XMLValueType.STRING, path .. "#fuelFillType", "Dryer fuel", "PROPANE")
    schema:register(XMLValueType.STRING, path .. "#fuelStorageId", "Dedicated controlled fuel storage")
    schema:register(XMLValueType.STRING, path .. "#storageId", "Only this controlled grain storage may dry")
    schema:register(XMLValueType.FLOAT, path .. "#target", "Target moisture fraction", 0.15)
    schema:register(XMLValueType.FLOAT, path .. "#ratePerHour", "Moisture fraction removed per game hour", 0.02)
    schema:register(XMLValueType.FLOAT, path .. "#fuelPer1000LitersPerPoint", "Fuel liters per 1000 liters per percentage point", 2)
end

function SCMoistureDryer.configure(productionData, recipe, data, xml, key, customEnv)
    -- Profile for the verified GSI 0.0.1.8 recipes. Other mods opt in with XML.
    local isGSI = customEnv == "FS25_GSI_SILOS"
        and (recipe.id == "GRAIN_DRYER" or recipe.id == "CORN_DRYER")
    -- Even the legacy conversion must never consume grain from another bin.
    if isGSI then data.legacyDryerStorageId = "BIN01" end
    if SCMoisture.system() == nil then return false end
    local path = key .. ".moistureDrying"
    if not xml:getValue(path .. "#enabled", isGSI) then return false end
    local grain = g_fillTypeManager:getFillTypeIndexByName(xml:getValue(path .. "#fillType", "MAIZE"))
    local fuel = g_fillTypeManager:getFillTypeIndexByName(xml:getValue(path .. "#fuelFillType", "PROPANE"))
    local config = {
        grain = grain, fuel = fuel,
        storageId = xml:getValue(path .. "#storageId", isGSI and "BIN01" or nil),
        fuelStorageId = xml:getValue(path .. "#fuelStorageId", isGSI and "TANK01" or nil),
        target = xml:getValue(path .. "#target", 0.15),
        rate = xml:getValue(path .. "#ratePerHour", 0.02),
        fuelRate = xml:getValue(path .. "#fuelPer1000LitersPerPoint", 2)
    }
    if not grain or not fuel or grain == fuel or not SCMoisture.system(grain)
        or not (config.target > 0 and config.target < 1)
        or not (config.rate > 0 and config.rate <= 1)
        or not (config.fuelRate > 0 and config.fuelRate < math.huge) then
        -- Invalid opt-in settings must not silently convert grain instead.
        config.invalid = true
    end
    data.moistureDryer = config
    data.type = SCProductionPoint.RECIPE_TYPE.NORMAL
    data.isInitialized = true
    data.isDirty = false
    if not config.invalid then
        recipe.inputs = {{type = grain, amount = 1000}, {type = fuel, amount = config.fuelRate}}
        recipe.outputs = {{type = grain, amount = 1000, sellDirectly = false}}
        recipe.primaryProductFillType = grain
    end
    recipe.name = productionData.i18n:getText("scProduction_moistureDrying")
        .. string.format(" (%.0f%%)", config.target * 100)
    return true
end

function SCMoistureDryer.isBlockedLegacy(data, recipeData)
    if recipeData.legacyDryerStorageId == nil then return false end
    local controller = data.stateController
    local storage = controller:getStorage(recipeData.legacyDryerStorageId)
    return storage == nil or not controller:getIsStorageActive(storage, SCStateController.STATE_TYPE.INPUT)
end

function SCMoistureDryer.fuelStorages(controller, config)
    if config.fuelStorageId then
        local storage = controller:getStorage(config.fuelStorageId)
        return storage and {storage} or {}
    end
    return controller:getActiveStorageList(SCStateController.STATE_TYPE.INPUT)
end

-- A named drying bin is independent of the intake and outlet selectors.
function SCMoistureDryer.grainStorages(controller, config)
    if config.storageId then
        local storage = controller:getStorage(config.storageId)
        return storage and {storage} or {}
    end
    return controller:getActiveStorageList(SCStateController.STATE_TYPE.INPUT)
end

-- Planning has no side effects. Only internal, measured grain counts.
function SCMoistureDryer.plan(controller, config, hours, processed)
    local plan = {bins = {}, fuel = 0, hasGrain = false, unknown = false, alreadyProcessed = false}
    if config.invalid or hours <= 0 then return plan end
    local storages = SCMoistureDryer.grainStorages(controller, config)
    for _, storage in ipairs(storages) do
        local level = storage:getFillLevel(config.grain)
        if level > 0 then
            plan.hasGrain = true
            local info = SCMoisture.info(storage, config.grain)
            if not info then
                plan.unknown = true
            elseif processed[storage] then
                plan.alreadyProcessed = true
            elseif info.moisture > config.target then
                local reduction = math.min(config.rate * hours, info.moisture - config.target)
                local fuel = level / 1000 * reduction * 100 * config.fuelRate
                table.insert(plan.bins, {storage = storage, info = info, reduction = reduction})
                plan.fuel = plan.fuel + fuel
            end
        end
    end
    return plan
end

function SCMoistureDryer.setStatus(data, recipe, status)
    if recipe.status ~= status then
        local parent = data:getParent()
        recipe.status = status
        parent.owningPlaceable:productionStatusChanged(recipe, status)
        parent:setProductionStatus(recipe.id, status)
    end
end

function SCMoistureDryer.update(data, recipe, recipeData, hours, processed)
    local parent = data:getParent()
    local controller = data.stateController
    local config = recipeData.moistureDryer
    if not data.isServer or not parent.isOwned or hours <= 0 then return end
    if config.invalid or not SCMoisture.system(config.grain) then
        SCMoistureDryer.setStatus(data, recipe, ProductionPoint.PROD_STATUS.MISSING_INPUTS)
        return
    end
    local plan = SCMoistureDryer.plan(controller, config, hours, processed)
    if plan.fuel <= 0 then
        if plan.hasGrain and not plan.unknown and not plan.alreadyProcessed then
            parent:setProductionState(recipe.id, false)
        elseif not plan.alreadyProcessed then
            SCMoistureDryer.setStatus(data, recipe, ProductionPoint.PROD_STATUS.MISSING_INPUTS)
        end
        return
    end
    -- Consume actual fuel before granting drying. Lack of fuel scales the work.
    local consumed = 0
    for _, storage in ipairs(SCMoistureDryer.fuelStorages(controller, config)) do
        local before = storage:getFillLevel(config.fuel)
        local take = math.min(before, plan.fuel - consumed)
        if take > 0 then
            storage:setFillLevel(before - take, config.fuel)
            consumed = consumed + math.max(0, before - storage:getFillLevel(config.fuel))
            storage:raiseDirtyFlags(storage.storageDirtyFlag)
        end
        if consumed >= plan.fuel then break end
    end
    if consumed <= 0 then
        SCMoistureDryer.setStatus(data, recipe, ProductionPoint.PROD_STATUS.MISSING_INPUTS)
        return
    end
    local factor = math.min(1, consumed / plan.fuel)
    local finished = not plan.unknown and not plan.alreadyProcessed
    local longestReduction = 0
    for _, entry in ipairs(plan.bins) do
        local info = entry.info
        local reduction = entry.reduction * factor
        longestReduction = math.max(longestReduction, reduction)
        info.moisture = math.max(config.target, info.moisture - reduction)
        -- Match MS's own dryer: preserve quality history and grain fill type.
        SCMoisture.set(entry.storage, config.grain, info)
        processed[entry.storage] = true
        if info.moisture > config.target + 0.0000001 then finished = false end
    end
    local activeHours = longestReduction / config.rate
    parent.productionCostsToClaim = parent.productionCostsToClaim
        + (recipe.costsPerActiveMinute or 0) * activeHours * 60
    SCMoistureDryer.setStatus(data, recipe, ProductionPoint.PROD_STATUS.RUNNING)
    if finished then parent:setProductionState(recipe.id, false) end
end
