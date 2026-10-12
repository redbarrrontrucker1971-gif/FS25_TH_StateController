-- Explicit GSI grain-flow opt-in. Real SC storages own every liter, including
-- dryer batches, so existing storage savegame/network code persists the flow.
SCGrainFlow = {}

function SCGrainFlow.registerXMLPaths(schema, path)
    path = path .. ".grainFlow"
    schema:register(XMLValueType.STRING, path .. "#role", "receive, dryer, or discharge")
    schema:register(XMLValueType.STRING, path .. "#destinationStorageId", "Fixed internal discharge storage; ignores Output State")
    schema:register(XMLValueType.FLOAT, path .. "#litersPerHour", "Maximum liters per game hour", 10000)
end

function SCGrainFlow.configure(data, recipe, rd, xml, key, customEnv)
    local role = xml:getValue(key .. ".grainFlow#role")
    if role == nil or customEnv ~= "FS25_GSI_SILOS" then return false end
    local rate = xml:getValue(key .. ".grainFlow#litersPerHour", 10000)
    local destinationId = xml:getValue(key .. ".grainFlow#destinationStorageId")
    if destinationId ~= nil then destinationId = string.upper(destinationId) end
    rd.grainFlow = {role = role, rate = rate, destinationId = destinationId,
        invalid = (role ~= "receive" and role ~= "dryer" and role ~= "discharge")
            or type(rate) ~= "number" or rate <= 0 or rate >= math.huge}
    rd.type = SCProductionPoint.RECIPE_TYPE.NORMAL
    rd.isInitialized = true
    rd.isDirty = false
    if role == "dryer" and SCMoisture.system() then
        SCMoistureDryer.configure(data, recipe, rd, xml, key, customEnv)
        if rd.moistureDryer then
            rd.moistureDryer.storageId = "DRYER"
            rd.moistureDryer.holdFinished = true
        else
            rd.grainFlow.invalid = true
        end
    elseif role == "dryer" then
        local grain = g_fillTypeManager:getFillTypeIndexByName("MAIZE")
        local fuel = g_fillTypeManager:getFillTypeIndexByName("PROPANE")
        local product = g_fillTypeManager:getFillTypeIndexByName("CORN_DRY")
        if grain and fuel and product then
            recipe.inputs = {{type = grain, amount = 200}, {type = fuel, amount = 4}}
            recipe.outputs = {{type = product, amount = 200, sellDirectly = false}}
            recipe.primaryProductFillType = product
        else rd.grainFlow.invalid = true end
    end
    return true
end

-- Check physical storage support/occupancy, independently of selector state.
function SCGrainFlow.space(storage, ft)
    if not storage or not storage:getIsFillTypeSupported(ft) then return 0 end
    if not storage.supportsMultipleFillTypes then
        for other, level in pairs(storage:getFillLevels()) do
            if other ~= ft and level > 0 then return 0 end
        end
    end
    return math.max(0, storage:getFreeCapacity(ft))
end

function SCGrainFlow.move(controller, source, destination, ft, limit)
    if not source or not destination or source == destination then return 0 end
    local before = source:getFillLevel(ft)
    local amount = math.min(before, limit, SCGrainFlow.space(destination, ft))
    if amount <= 0 then return 0 end
    local info = SCMoisture.info(source, ft)
    local accepted = 0
    SCMoisture.withContext(controller, {incoming = {[ft] = info}}, function()
        source:setFillLevel(before - amount, ft)
        local removed = before - source:getFillLevel(ft)
        local oldDestination = destination:getFillLevel(ft)
        destination:setFillLevel(oldDestination + removed, ft)
        accepted = destination:getFillLevel(ft) - oldDestination
        if accepted < removed then
            source:setFillLevel(source:getFillLevel(ft) + removed - accepted, ft)
        end
        source:raiseDirtyFlags(source.storageDirtyFlag)
        destination:raiseDirtyFlags(destination.storageDirtyFlag)
    end)
    return accepted
end

function SCGrainFlow.leg(data, recipe, sourceId, stateType, limit, hours, destinationId)
    local c = data.stateController
    local source = c:getStorage(sourceId)
    -- A configured physical pipe never falls back to the selected output.
    local destinations = destinationId ~= nil and {c:getStorage(destinationId)}
        or c:getActiveStorageList(stateType)
    local moved, hasGrain = 0, false
    if source then
        -- Sort for predictable handling of any legacy multi-crop storage.
        local crops = {}
        for ft, level in pairs(source:getFillLevels()) do
            if level > 0 then table.insert(crops, ft); hasGrain = true end
        end
        table.sort(crops)
        for _, ft in ipairs(crops) do
            for _, destination in ipairs(destinations) do
                -- Fixed pipes use internal storage on this owned production, like the dryer.
                -- Selector-driven routes retain the normal state access checks.
                if destination ~= source and (destinationId ~= nil
                    or c:getCanAccessStorage(destination, nil, ft, stateType)) then
                    moved = moved + SCGrainFlow.move(c, source, destination, ft, math.max(0, limit - moved))
                end
            end
        end
    end
    local status = ProductionPoint.PROD_STATUS.MISSING_INPUTS
    if moved > 0 then
        status = ProductionPoint.PROD_STATUS.RUNNING
        local p = data:getParent()
        p.productionCostsToClaim = p.productionCostsToClaim
            + (recipe.costsPerActiveMinute or 0) * hours * 60 * math.min(1, moved / limit)
    elseif hasGrain then status = ProductionPoint.PROD_STATUS.NO_OUTPUT_SPACE end
    SCMoistureDryer.setStatus(data, recipe, status)
end

function SCGrainFlow.dry(data, recipe, rd, hours)
    local c = data.stateController
    local chamber, ready = c:getStorage("DRYER"), c:getStorage("DRYER_OUT")
    local wet, fuel = c:getStorage("BIN01"), c:getStorage("TANK01")
    local maize = g_fillTypeManager:getFillTypeIndexByName("MAIZE")
    local propane = g_fillTypeManager:getFillTypeIndexByName("PROPANE")
    local dryCorn = g_fillTypeManager:getFillTypeIndexByName("CORN_DRY")
    local function status(value) SCMoistureDryer.setStatus(data, recipe, ProductionPoint.PROD_STATUS[value]) end
    if not chamber or not ready or not wet or not fuel or not maize or not propane then
        status("MISSING_INPUTS"); return
    end
    -- No topping up a running batch: new wet grain stays in Wet Bin.
    if chamber:getFillLevel(maize) <= 0 then
        SCGrainFlow.move(c, wet, chamber, maize, SCGrainFlow.space(chamber, maize))
    end
    if chamber:getFillLevel(maize) <= 0 then status("MISSING_INPUTS"); return end
    if rd.moistureDryer then
        local config = rd.moistureDryer
        local info = SCMoisture.info(chamber, maize)
        if not info or not SCMoisture.system(maize) then status("MISSING_INPUTS"); return end
        if SCGrainFlow.space(ready, maize) <= 0 then status("NO_OUTPUT_SPACE"); return end
        if info.moisture > config.target + 0.0000001 then
            SCMoistureDryer.update(data, recipe, rd, hours, {})
            info = SCMoisture.info(chamber, maize)
        end
        if info and info.moisture <= config.target + 0.0000001 then
            SCGrainFlow.move(c, chamber, ready, maize, chamber:getFillLevel(maize))
            status(chamber:getFillLevel(maize) > 0 and "NO_OUTPUT_SPACE" or "RUNNING")
        end
    else
        -- Legacy drying: same 200 corn + 4 propane -> 200 dry corn ratio.
        if not dryCorn then status("MISSING_INPUTS"); return end
        local amount = math.min(chamber:getFillLevel(maize), rd.grainFlow.rate * hours,
            SCGrainFlow.space(ready, dryCorn), fuel:getFillLevel(propane) / 0.02)
        if amount <= 0 then
            status(SCGrainFlow.space(ready, dryCorn) <= 0 and "NO_OUTPUT_SPACE" or "MISSING_INPUTS")
            return
        end
        local oldGrain, oldFuel, oldOutput = chamber:getFillLevel(maize), fuel:getFillLevel(propane), ready:getFillLevel(dryCorn)
        ready:setFillLevel(oldOutput + amount, dryCorn)
        local accepted = ready:getFillLevel(dryCorn) - oldOutput
        chamber:setFillLevel(oldGrain - accepted, maize)
        fuel:setFillLevel(oldFuel - accepted * 0.02, propane)
        for _, s in ipairs({chamber, ready, fuel}) do s:raiseDirtyFlags(s.storageDirtyFlag) end
        local p = data:getParent()
        p.productionCostsToClaim = p.productionCostsToClaim
            + (recipe.costsPerActiveMinute or 0) * 60 * accepted / rd.grainFlow.rate
        status(accepted > 0 and "RUNNING" or "NO_OUTPUT_SPACE")
    end
end

function SCGrainFlow.update(data, recipe, rd, hours)
    if not data.isServer or not data:getParent().isOwned or hours <= 0 then return end
    local cfg = rd.grainFlow
    if cfg.invalid then
        SCMoistureDryer.setStatus(data, recipe, ProductionPoint.PROD_STATUS.MISSING_INPUTS)
    elseif cfg.role == "receive" then
        SCGrainFlow.leg(data, recipe, "BIN03", SCStateController.STATE_TYPE.INPUT, cfg.rate * hours, hours)
    elseif cfg.role == "discharge" then
        SCGrainFlow.leg(data, recipe, "DRYER_OUT", SCStateController.STATE_TYPE.OUTPUT, cfg.rate * hours, hours, cfg.destinationId)
    else
        SCGrainFlow.dry(data, recipe, rd, hours)
    end
end
