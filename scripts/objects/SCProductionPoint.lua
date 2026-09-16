-- Copyright ©2023 by Todd Hundersmarck (ThundR)
-- All Rights Reserved

SCProductionPoint = {}
SCProductionPoint_mt = Class(SCProductionPoint, THData)
SCProductionPoint.RECIPE_TYPE = {
NORMAL  = 0,
SPECIAL = 1,
DYNAMIC = 2
}
SCProductionPoint.SPECIAL_RECIPE = {
SC_FILLTYPE_MOVER = 1
}
SCProductionPoint.MESSAGE_TYPE = {
RECIPE_UPDATED = nextMessageTypeId
}
function SCProductionPoint:initialize(controller)
self.getParent = function(pSelf)
return SCProductionPoint:superClass().getParent(pSelf)
end
if THUtils.argIsValid(THUtils.getIsType(controller, SCStateController), "controller", controller, true) then
self.stateController = controller
self.messageCenter = controller.messageCenter
self.inputBinding = controller.inputBinding
self.soundManager = g_soundManager
self.effectManager = g_effectManager
self.animationManager = g_animationManager
self.i18n = controller.i18n
self.specialRecipes  = {}
self.dynamicRecipes  = {}
self.recipeFillTypes = {}
self.recipeFillTypesArray = {}
self.stateTypes = {}
self.recipeEventIds = {}
self.areRecipesDirty = false
for stateTypeIdx = 1, SCStateController.MAX_STATE_TYPES do
local stateTypeInfo = controller:getStateType(stateTypeIdx)
local extendedInfo = {}
extendedInfo.id     = stateTypeInfo.id
extendedInfo.index  = stateTypeInfo.index
extendedInfo.parent = stateTypeInfo
extendedInfo.recipeFillTypes = {}
extendedInfo.recipeFillTypesArray = {}
self.stateTypes[extendedInfo.id] = extendedInfo
end
self.isFinalized = false
if controller:getIsEnabled() then
local parent = self:getParent()
local scActivatable = controller.activatable
self.isClient = parent.isClient
self.isServer = parent.isServer
if self.isServer then
self.areRecipesDirty = true
end
self.messageCenter:subscribe(SCStateController.MESSAGE_TYPE.STORAGE_UPDATED, self.onStorageUpdated, self)
self.messageCenter:subscribe(THMain.MESSAGE_TYPE.FILL_LEVEL_CHANGED, self.onFillLevelChanged, self)
g_thMain:setFunctionHook(parent, "load",                       SCProductionPoint, nil, self)
g_thMain:setFunctionHook(parent, "delete",                     SCProductionPoint, nil, self)
g_thMain:setFunctionHook(parent, "writeStream",                SCProductionPoint, nil, self)
g_thMain:setFunctionHook(parent, "getFillLevel",               SCProductionPoint, nil, self)
g_thMain:setFunctionHook(parent, "getCapacity",                SCProductionPoint, nil, self)
g_thMain:setFunctionHook(parent, "updateProduction",           SCProductionPoint, nil, self)
g_thMain:setFunctionHook(parent, "updateInfo",                 SCProductionPoint, nil, self)
g_thMain:setFunctionHook(parent, "directlySellOutputs",        SCProductionPoint, nil, self)
g_thMain:setFunctionHook(parent, "palletSpawnRequestCallback", SCProductionPoint, nil, self)
g_thMain:setFunctionHook(controller, "getIsFillTypeActive",   SCProductionPoint.SCStateController, nil, self)
g_thMain:setFunctionHook(controller, "getActiveFillTypeList", SCProductionPoint.SCStateController, nil, self)
g_thMain:setFunctionHook(scActivatable, "getIsActivatable",         SCProductionPoint.SCStateControllerActivatable, nil, self)
g_thMain:setFunctionHook(scActivatable, "registerCustomInput",      SCProductionPoint.SCStateControllerActivatable, nil, self)
g_thMain:setFunctionHook(scActivatable, "removeCustomInput",        SCProductionPoint.SCStateControllerActivatable, nil, self)
g_thMain:setFunctionHook(scActivatable, "updateActionEvents",       SCProductionPoint.SCStateControllerActivatable, nil, self)
g_thMain:setFunctionHook(scActivatable, "actionSelectControlState", SCProductionPoint.SCStateControllerActivatable, nil, self)
return true
end
end
return false
end
function SCProductionPoint.registerXMLPaths(schema, xmlPath)
local xmlDataKey = g_thMain.xmlDataKey
local productionPath = xmlPath..".productions.production(?)"
local productionDataPath = productionPath.."."..xmlDataKey
THUtils.registerXMLPath(schema, XMLValueType.BOOL,   productionDataPath, "#isDynamic", "Use dynamic configuration", false)
THUtils.registerXMLPath(schema, XMLValueType.STRING, productionDataPath, "#iconFilename", "Custom recipe icon filename")
local additivePath = productionDataPath..".additives.additive(?)"
THUtils.registerXMLPath(schema, XMLValueType.STRING, additivePath, "#fillType", "Additive fillType name")
THUtils.registerXMLPath(schema, XMLValueType.FLOAT,  additivePath, "#amount", "Additive fillType amount", 1)
THUtils.registerXMLPath(schema, XMLValueType.STRING, additivePath, "#addTo", "Input fillTypes to append", "")
local byproductPath = productionDataPath..".byproducts.byproduct(?)"
THUtils.registerXMLPath(schema, XMLValueType.STRING, byproductPath, "#fillType", "Byproduct fillType name")
THUtils.registerXMLPath(schema, XMLValueType.FLOAT,  byproductPath, "#amount", "Byproduct fillType amount", 1)
THUtils.registerXMLPath(schema, XMLValueType.STRING, byproductPath, "#addTo", "Output fillTypes to append", "")
THUtils.registerXMLPath(schema, XMLValueType.BOOL,   byproductPath, "sellDirectly", "Sell fillType directly", false)
ProductionPoint.registerXMLPaths(schema, xmlPath)
end
function SCProductionPoint:load(components, xmlFile, xmlKey, customEnv, i3dMappings)
local controller = self.stateController
local production = self:getParent()
local xmlDataKey = g_thMain.xmlDataKey
local basePath = production.baseDirectory
if basePath == nil and customEnv ~= nil then
local modEntry = g_thMain:getLoadedMod(customEnv)
if modEntry ~= nil then
basePath = modEntry.path
end
end
xmlFile:iterate(xmlKey..".productions.production", function(_, pRecipeKey)
local recipeId = xmlFile:getValue(pRecipeKey.."#id")
local recipeInfo = self:getProductionRecipe(recipeId)
if recipeInfo ~= nil then
local recipeData = g_thMain:createDataTable(recipeInfo, false)
local recipeDataKey = pRecipeKey.."."..xmlDataKey
recipeData.type = SCProductionPoint.RECIPE_TYPE.NORMAL
recipeData.factor = 1
recipeData.isDirty = false
recipeData.isInitialized = false
recipeData.baseFillType = recipeInfo.inputs[1].type
recipeData.baseAmount   = recipeInfo.inputs[1].amount
recipeData.baseSellDirectly = recipeInfo.outputs[1].sellDirectly
recipeData.oldInputs = {}
recipeData.oldOutputs = {}
recipeData.dynamicInputs = {}
recipeData.dynamicOutputs = {}
recipeData.inputTypeMapping = {}
recipeData.outputTypeMapping = {}
recipeData.additives = {}
recipeData.byproducts = {}
for inputIdx, inputInfo in pairs(recipeInfo.inputs) do
recipeData.oldInputs[inputIdx] = inputInfo
recipeData.dynamicInputs[inputIdx] = {}
end
for outputIdx, outputInfo in pairs(recipeInfo.outputs) do
recipeData.oldOutputs[outputIdx] = outputInfo
recipeData.dynamicOutputs[outputIdx] = {}
end
local iconFilename = xmlFile:getValue(recipeDataKey.."#iconFilename")
if iconFilename ~= nil then
recipeData.iconFilename = Utils.getFilename(iconFilename, basePath)
end
if self:loadProductionRecipe(recipeId, components, xmlFile, recipeDataKey, customEnv, basePath, i3dMappings) then
if recipeData.type == SCProductionPoint.RECIPE_TYPE.SPECIAL then
self.specialRecipes[recipeId] = recipeInfo
elseif recipeData.type == SCProductionPoint.RECIPE_TYPE.DYNAMIC then
self.dynamicRecipes[recipeId] = recipeInfo
end
end
end
end)
local inputStateType = self:getExtendedStateType(SCStateController.STATE_TYPE.INPUT)
local outputStateType = self:getExtendedStateType(SCStateController.STATE_TYPE.OUTPUT)
local function addRecipeFillType(pFillType, pStateTypeInfo)
if pStateTypeInfo ~= nil then
if not pStateTypeInfo.recipeFillTypes[pFillType] then
table.insert(pStateTypeInfo.recipeFillTypesArray, pFillType)
pStateTypeInfo.recipeFillTypes[pFillType] = true
end
end
if not self.recipeFillTypes[pFillType] then
table.insert(self.recipeFillTypesArray, pFillType)
self.recipeFillTypes[pFillType] = true
end
end
local _, numRecipes = self:getProductionRecipeList()
THUtils.clearTable(production.soldFillTypesToPayOut)
if numRecipes > 0 then
for recipeIdx = 1, numRecipes do
local recipeInfo = self:getProductionRecipe(recipeIdx)
for _, inputInfo in pairs(recipeInfo.inputs) do
addRecipeFillType(inputInfo.type, inputStateType)
end
for _, outputInfo in pairs(recipeInfo.outputs) do
if outputInfo.sellDirectly then
production.soldFillTypesToPayOut[outputInfo.type] = 0
else
addRecipeFillType(outputInfo.type, outputStateType)
end
end
end
end
if self:getSpecialRecipe("SC_FILLTYPE_MOVER") then
for _, fillType in ipairs(controller.storageFillTypesArray) do
if inputStateType.parent.storageFillTypes[fillType] then
addRecipeFillType(fillType, inputStateType)
end
if outputStateType.parent.storageFillTypes[fillType] then
addRecipeFillType(fillType, outputStateType)
end
end
end
THUtils.sortTable(inputStateType.recipeFillTypesArray, "title", "getFillType")
THUtils.sortTable(outputStateType.recipeFillTypesArray, "title", "getFillType")
THUtils.sortTable(self.recipeFillTypesArray, "title", "getFillType")
production.inputFillTypeIds = inputStateType.recipeFillTypes
production.inputFillTypeIdsArray = inputStateType.recipeFillTypesArray
production.outputFillTypeIds = outputStateType.recipeFillTypes
production.outputFillTypeIdsArray = outputStateType.recipeFillTypesArray
if self:createMainStorage() then
return true
end
return false
end
function SCProductionPoint:finishLoading()
return true
end
function SCProductionPoint:delete()
self.messageCenter:unsubscribeAll(self)
return true
end
function SCProductionPoint:loadProductionRecipe(recipeId, components, xmlFile, xmlKey, customEnv, basePath, i3dMappings)
local recipeInfo, recipeData = self:getProductionRecipe(recipeId)
if recipeData == nil then
THUtils.errorMsg(false, "Cannot find recipe data table")
return false
end
local numInputs = #recipeInfo.inputs
local numOutputs = #recipeInfo.outputs
local isDynamicRecipe = xmlFile:getValue(xmlKey.."#isDynamic", false)
local isSpecialRecipe = false
if SCProductionPoint.SPECIAL_RECIPE[recipeId] ~= nil then
isDynamicRecipe = true
isSpecialRecipe = true
end
recipeData.type = SCProductionPoint.RECIPE_TYPE.NORMAL
if isDynamicRecipe then
if isSpecialRecipe then
recipeData.type = SCProductionPoint.RECIPE_TYPE.SPECIAL
else
if numInputs <= 0 or numOutputs > numInputs then
THUtils.errorMsg(false, "Production %q missing inputs", recipeInfo.id)
recipeData.type = SCProductionPoint.RECIPE_TYPE.NORMAL
return false
elseif numOutputs <= 0 or numInputs > numOutputs then
THUtils.errorMsg(false, "Production %q missing outputs", recipeInfo.id)
recipeData.type = SCProductionPoint.RECIPE_TYPE.NORMAL
return false
else
recipeData.type = SCProductionPoint.RECIPE_TYPE.DYNAMIC
end
end
else
return true
end
local function loadExtraFillTypes(pExtrasBaseKey, pExtrasBaseTable)
xmlFile:iterate(pExtrasBaseKey, function(_, extrasKey)
local extrasType         = "additive"
local extraFillType      = xmlFile:getValue(extrasKey.."#fillType")
local extraAmount        = xmlFile:getValue(extrasKey.."#amount", 0)
local extraSellDirectly  = nil
local addToFillTypeNames = xmlFile:getValue(extrasKey.."#addTo", "")
if pExtrasBaseTable == recipeData.byproducts then
extrasType        = "byproduct"
extraSellDirectly = xmlFile:getValue(extrasKey.."#sellDirectly", false)
end
if recipeId == "SC_FILLTYPE_MOVER" then
addToFillTypeNames = ""
end
local extraFillTypeInfo = THUtils.getFillType(extraFillType, true, false)
local addToFillTypeList = g_fillTypeManager:getFillTypesByNames(addToFillTypeNames)
local isEntryValid = true
if addToFillTypeList == nil then
addToFillTypeList = {}
end
if extraFillTypeInfo ~= nil then
if extraAmount <= 0 then
THUtils.errorMsg(false, "Recipe %q, invalid %s amount (%s) specified for fillType %q", recipeId, extrasType, extraAmount, extraFillTypeInfo.name)
isEntryValid = false
elseif #addToFillTypeList == 0 then
if isSpecialRecipe then
table.insert(addToFillTypeList, FillType.UNKNOWN)
else
THUtils.errorMsg(false, "Recipe %q, no valid %s addToFillTypes specified for fillType %q", recipeId, extrasType, extraFillTypeInfo.name)
isEntryValid = false
end
end
end
if isEntryValid then
for _, addToFillType in ipairs(addToFillTypeList) do
local extrasTable = pExtrasBaseTable[addToFillType]
local isExtraFound = false
if extrasTable == nil then
extrasTable = {}
pExtrasBaseTable[addToFillType] = extrasTable
end
for _, extraInfo in pairs(extrasTable) do
if extraInfo.type == extraFillTypeInfo.index then
extraInfo.amount = extraAmount
extraInfo.sellDirectly = extraSellDirectly
isExtraFound = true
break
end
end
if not isExtraFound then
table.insert(extrasTable, {
type         = extraFillTypeInfo.index,
amount       = extraAmount,
sellDirectly = extraSellDirectly
})
end
end
end
end)
return true
end
if  loadExtraFillTypes(xmlKey..".additives.additive", recipeData.additives)
and loadExtraFillTypes(xmlKey..".byproducts.byproduct", recipeData.byproducts)
then
local dynamicInputs = THUtils.clearTable(recipeData.dynamicInputs)
local dynamicOutputs = THUtils.clearTable(recipeData.dynamicOutputs)
if not isSpecialRecipe then
for entryIdx = 1, numInputs do
local inputInfo = recipeData.oldInputs[entryIdx]
local outputInfo = recipeData.oldOutputs[entryIdx]
local additiveList = recipeData.additives[inputInfo.type]
local byproductList = recipeData.byproducts[outputInfo.type]
dynamicInputs[entryIdx]  = {inputInfo}
dynamicOutputs[entryIdx] = {outputInfo}
if additiveList ~= nil and #additiveList > 0 then
for _, additiveInfo in ipairs(additiveList) do
table.insert(dynamicInputs[entryIdx], additiveInfo)
end
end
if byproductList ~= nil and #byproductList > 0 then
for _, byproductInfo in ipairs(byproductList) do
table.insert(dynamicOutputs[entryIdx], byproductInfo)
end
end
end
end
return true
end
return false
end
function SCProductionPoint:getProductionRecipe(recipeId)
local parent = self:getParent()
local targetType = type(recipeId)
local recipeInfo = nil
if targetType == "string" then
recipeInfo = parent.productionsIdToObj[recipeId]
elseif targetType == "number" then
recipeInfo = parent.productions[recipeId]
end
local recipeData = g_thMain:getDataTable(recipeInfo)
return recipeInfo, recipeData
end
function SCProductionPoint:getProductionRecipeList(byId)
local parent = self:getParent()
if parent.productions ~= nil then
local numRecipes = #parent.productions
if byId == true then
return parent.productionsIdToObj, numRecipes
else
return parent.productions, numRecipes
end
end
return {}, 0
end
function SCProductionPoint:getDynamicRecipe(recipeId)
local recipeInfo, recipeData = self:getProductionRecipe(recipeId)
if recipeData ~= nil and self.dynamicRecipes[recipeInfo.id] == recipeInfo then
return recipeInfo, recipeData
end
end
function SCProductionPoint:getSpecialRecipe(recipeId)
local recipeInfo, recipeData = self:getProductionRecipe(recipeId)
if recipeData ~= nil and self.specialRecipes[recipeInfo.id] == recipeInfo then
return recipeInfo, recipeData
end
end
function SCProductionPoint:updateDynamicRecipes(recipeId, noEventSend)
local production = self:getParent()
local controller = self.stateController
local function updateRecipe(pRecipeInfo)
local recipeData = g_thMain:getDataTable(pRecipeInfo)
if recipeData ~= nil and recipeData.type == SCProductionPoint.RECIPE_TYPE.DYNAMIC then
local numEntries = #recipeData.dynamicInputs
if self.isServer and numEntries > 0 then
local inputsTable    = pRecipeInfo.inputs
local outputsTable   = pRecipeInfo.outputs
local areTablesReset = false
if not recipeData.isInitialized then
inputsTable    = THUtils.clearTable(pRecipeInfo.inputs)
outputsTable   = THUtils.clearTable(pRecipeInfo.outputs)
areTablesReset = true
recipeData.isInitialized = true
end
local inputTypeMapping = THUtils.clearTable(recipeData.inputTypeMapping)
local outputTypeMapping = THUtils.clearTable(recipeData.outputTypeMapping)
local validEntries, numValidEntries = {}, 0
local baseEntryIdx = nil
for entryIdx = 1, numEntries do
local inputsList = recipeData.dynamicInputs[entryIdx]
local outputsList = recipeData.dynamicOutputs[entryIdx]
local numInputs = #inputsList
local numOutputs = #outputsList
if numInputs > 0 and numOutputs > 0 then
local baseFillType = inputsList[1].type
local baseFillLevel = controller:getStorageValue("fillLevel", SCStateController.STATE_TYPE.INPUT, baseFillType, true)
local isEntryValid = true
if baseFillLevel == nil or baseFillLevel <= 0 then
isEntryValid = false
elseif baseEntryIdx == nil then
if not areTablesReset then
inputsTable    = THUtils.clearTable(pRecipeInfo.inputs)
outputsTable   = THUtils.clearTable(pRecipeInfo.outputs)
areTablesReset = true
end
baseEntryIdx = entryIdx
end
if isEntryValid and numInputs > 1 then
for inputIdx = 2, numInputs do
local inputInfo = inputsList[inputIdx]
local inputFillType = inputInfo.type
local inputFillLevel = controller:getStorageValue("fillLevel", SCStateController.STATE_TYPE.INPUT, inputFillType)
if inputFillLevel == nil or inputFillLevel <= 0 then
isEntryValid = false
break
end
end
end
if isEntryValid then
if numValidEntries == 0 then
baseEntryIdx = entryIdx
end
table.insert(validEntries, entryIdx)
numValidEntries = numValidEntries + 1
end
end
end
if numValidEntries > 0 then
areTablesReset = false
for validEntryIdx = 1, numValidEntries do
local entryIdx = validEntries[validEntryIdx]
local inputsList = recipeData.dynamicInputs[entryIdx]
local outputsList = recipeData.dynamicOutputs[entryIdx]
local numInputs = #inputsList
local numOutputs = #outputsList
for inputIdx = 1, numInputs do
local inputInfo     = inputsList[inputIdx]
local inputFillType = inputInfo.type
local inputAmount   = THUtils.round(inputInfo.amount / numValidEntries, 1)
local otherInfo     = inputTypeMapping[inputFillType]
inputAmount = math.max(0.1, inputAmount)
if otherInfo ~= nil then
otherInfo.amount = otherInfo.amount + inputAmount
else
otherInfo = {
type   = inputFillType,
amount = inputAmount
}
table.insert(inputsTable, otherInfo)
inputTypeMapping[inputFillType] = otherInfo
end
end
for outputIdx = 1, numOutputs do
local outputInfo       = outputsList[outputIdx]
local outputFillType   = outputInfo.type
local outputAmount     = THUtils.round(outputInfo.amount / numValidEntries, 1)
local outputDirectSell = THUtils.getNoNil(outputInfo.sellDirectly, false)
local otherInfo        = outputTypeMapping[outputFillType]
outputAmount = math.max(0.1, outputAmount)
if otherInfo ~= nil then
otherInfo.amount = otherInfo.amount + outputInfo.amount
if otherInfo.sellDirectly == true and otherInfo.sellDirectly ~= outputDirectSell then
otherInfo.sellDirectly = false
end
else
otherInfo = {
type         = outputFillType,
amount       = outputAmount,
sellDirectly = outputDirectSell
}
table.insert(outputsTable, otherInfo)
outputTypeMapping[outputFillType] = otherInfo
end
end
end
end
if #inputsTable == 0 or #outputsTable == 0 then
if not areTablesReset then
inputsTable    = THUtils.clearTable(pRecipeInfo.inputs)
outputsTable   = THUtils.clearTable(pRecipeInfo.outputs)
areTablesReset = true
end
baseEntryIdx = THUtils.getNoNil(baseEntryIdx, 1)
local baseInputs  = recipeData.dynamicInputs[baseEntryIdx]
local baseOutputs = recipeData.dynamicOutputs[baseEntryIdx]
for inputIdx = 1, #baseInputs do
table.insert(inputsTable, baseInputs[inputIdx])
end
for outputIdx = 1, #baseOutputs do
table.insert(outputsTable, baseOutputs[outputIdx])
end
end
pRecipeInfo.primaryProductFillType = pRecipeInfo.outputs[1].type
end
recipeData.isDirty = false
if self.isServer and numEntries > 0 then
self.messageCenter:publish(SCProductionPoint.MESSAGE_TYPE.RECIPE_UPDATED, pRecipeInfo, recipeData)
if noEventSend ~= true then
SCUpdateProductionRecipeEvent.sendEvent(production, pRecipeInfo.id)
end
end
end
end
if recipeId == nil then
local recipeList, numRecipes = self:getProductionRecipeList()
if numRecipes > 0 then
for recipeIdx = 1, numRecipes do
updateRecipe(recipeList[recipeIdx])
end
end
else
local recipeInfo = self:getDynamicRecipe(recipeId)
if recipeInfo == nil then
return false
else
updateRecipe(recipeInfo)
end
end
return true
end
function SCProductionPoint:updateSpecialRecipes(recipeId, noEventSend)
local production = self:getParent()
local controller = self.stateController
local inputFillTypesArray, numInputFillTypes = controller:getActiveFillTypeList(SCStateController.STATE_TYPE.INPUT)
local function updateRecipe(pRecipeInfo)
local recipeData = g_thMain:getDataTable(pRecipeInfo)
if recipeData ~= nil and recipeData.type == SCProductionPoint.RECIPE_TYPE.SPECIAL then
if self.isServer then
local inputsTable    = pRecipeInfo.inputs
local outputsTable   = pRecipeInfo.outputs
local areTablesReset = false
if not recipeData.isInitialized then
inputsTable    = THUtils.clearTable(pRecipeInfo.inputs)
outputsTable   = THUtils.clearTable(pRecipeInfo.outputs)
areTablesReset = true
recipeData.isInitialized = true
end
local baseFillType     = nil
local baseAmount       = recipeData.baseAmount
local baseSellDirectly = recipeData.baseSellDirectly
if pRecipeInfo.id == "SC_FILLTYPE_MOVER" then
local numValidFillTypes = 0
if numInputFillTypes > 0 then
if not areTablesReset then
inputsTable    = THUtils.clearTable(pRecipeInfo.inputs)
outputsTable   = THUtils.clearTable(pRecipeInfo.outputs)
areTablesReset = true
end
for fillTypeIdx = 1, numInputFillTypes do
local fillType  = inputFillTypesArray[fillTypeIdx]
local fillLevel = controller:getStorageValue("fillLevel", SCStateController.STATE_TYPE.INPUT, fillType, true)
if baseFillType == nil then
baseFillType = fillType
end
if fillLevel ~= nil and fillLevel > 0 then
local inputInfo  = {type = fillType, amount = baseAmount}
local outputInfo = {type = fillType, amount = baseAmount, sellDirectly = false}
table.insert(inputsTable, inputInfo)
table.insert(outputsTable, outputInfo)
numValidFillTypes = numValidFillTypes + 1
end
end
end
if numValidFillTypes > 0 then
local newAmount = THUtils.round(baseAmount / numValidFillTypes, 1)
newAmount = math.max(0.1, newAmount)
areTablesReset = false
for entryIdx = 1, #inputsTable do
local inputInfo = inputsTable[entryIdx]
local outputInfo = outputsTable[entryIdx]
inputInfo.amount = newAmount
outputInfo.amount = newAmount
end
end
end
if #inputsTable == 0 or #outputsTable == 0 then
if not areTablesReset then
inputsTable    = THUtils.clearTable(pRecipeInfo.inputs)
outputsTable   = THUtils.clearTable(pRecipeInfo.outputs)
areTablesReset = true
end
baseFillType = THUtils.getNoNil(baseFillType, recipeData.baseFillType)
table.insert(inputsTable, {type = baseFillType, amount = baseAmount})
table.insert(outputsTable, {type = baseFillType, amount = baseAmount, sellDirectly = baseSellDirectly})
end
pRecipeInfo.primaryProductFillType = pRecipeInfo.outputs[1].type
end
recipeData.isDirty = false
if self.isServer then
self.messageCenter:publish(SCProductionPoint.MESSAGE_TYPE.RECIPE_UPDATED, pRecipeInfo, recipeData)
if noEventSend ~= true then
SCUpdateProductionRecipeEvent.sendEvent(production, pRecipeInfo.id)
end
end
end
end
if recipeId == nil then
for _, recipeInfo in pairs(self.specialRecipes) do
updateRecipe(recipeInfo)
end
else
local recipeInfo = self:getSpecialRecipe(recipeId)
if recipeInfo == nil then
return false
else
updateRecipe(recipeInfo)
end
end
return true
end
function SCProductionPoint:updateProductionRecipes(recipeId)
local function updateRecipe(pRecipeInfo)
if self.isServer then
local recipeData = g_thMain:getDataTable(pRecipeInfo)
if recipeData ~= nil then
if self.isServer then
if recipeData.type == SCProductionPoint.RECIPE_TYPE.SPECIAL then
return self:updateSpecialRecipes(pRecipeInfo.id)
elseif recipeData.type == SCProductionPoint.RECIPE_TYPE.DYNAMIC then
return self:updateDynamicRecipes(pRecipeInfo.id)
end
end
recipeData.isInitialized = true
recipeData.isDirty = false
end
end
end
if recipeId == nil then
local recipeList, numRecipes = self:getProductionRecipeList()
if numRecipes > 0 then
for recipeIdx = 1, numRecipes do
updateRecipe(recipeList[recipeIdx])
end
end
else
local recipeInfo = self:getProductionRecipe(recipeId)
if recipeInfo == nil then
return false
else
updateRecipe(recipeInfo)
end
end
return true
end
function SCProductionPoint:getIsRecipeFillType(fillType, stateType)
if fillType == nil then
return false
end
fillType = THUtils.getFillTypeIndex(fillType, true, true)
if stateType == nil then
if self.recipeFillTypes[fillType] then
return true
end
else
local stateTypeInfo = self:getExtendedStateType(stateType)
if stateTypeInfo ~= nil then
if stateTypeInfo.recipeFillTypes[fillType] then
return true
end
end
end
return false
end
function SCProductionPoint:getRecipeFillTypeList(stateType, byId)
if stateType == nil then
local numFillTypes = #self.recipeFillTypesArray
if byId == true then
return self.recipeFillTypes, numFillTypes
else
return self.recipeFillTypesArray, numFillTypes
end
else
local stateTypeInfo = self:getExtendedStateType(stateType)
if stateTypeInfo ~= nil then
local numFillTypes = #stateTypeInfo.recipeFillTypesArray
if byId == true then
return stateTypeInfo.recipeFillTypes, numFillTypes
else
return stateTypeInfo.recipeFillTypesArray, numFillTypes
end
end
end
return {}, 0
end
function SCProductionPoint:createMainStorage()
local controller = self.stateController
local production = self:getParent()
local sellingStation = production.unloadingStation
local loadingStation = production.loadingStation
local mainStorage = production.storage
local storageData = g_thMain:createDataTable(mainStorage, false, nil,nil, SCProductionStorage_mt, controller)
if mainStorage == nil then
return false
else
local fillTypeList, numFillTypes = self:getRecipeFillTypeList()
mainStorage.capacity = 0
mainStorage.isExtension = false
mainStorage.supportsMultipleFillTypes = true
mainStorage.fillTypes = {}
mainStorage.sortedFillTypes = {}
mainStorage.capacities = {}
mainStorage.fillLevels = {}
mainStorage.fillLevelsLastSynced = {}
mainStorage.fillLevelsLastPublished = {}
if numFillTypes > 0 then
for i = 1, numFillTypes do
local fillType = fillTypeList[i]
if not mainStorage.fillTypes[fillType] then
table.insert(mainStorage.sortedFillTypes, fillType)
mainStorage.fillTypes[fillType] = true
end
mainStorage.fillTypes[fillType] = true
mainStorage.capacities[fillType] = 0
mainStorage.fillLevels[fillType] = 0
mainStorage.fillLevelsLastSynced[fillType] = 0
mainStorage.fillLevelsLastPublished[fillType] = 0
end
table.sort(mainStorage.sortedFillTypes)
end
end
local function hook_updateSupportedFillTypes(pSuperFunc, pSelf, ...)
local function appendFunc2(...)
local function protectedChunk2()
local fillTypeList, numFillTypes = self:getRecipeFillTypeList()
if numFillTypes > 0 then
for i = 1, numFillTypes do
local fillType = fillTypeList[i]
if not pSelf.supportedFillTypes[fillType] then
pSelf.supportedFillTypes[fillType] = true
end
end
end
end
g_thMain:call(protectedChunk2)
return ...
end
return appendFunc2(pSuperFunc(pSelf, ...))
end
if sellingStation == nil then
return false
else
sellingStation.storageRadius = 0
sellingStation.supportsExtension = false
sellingStation.hideFromPricesMenu = true
sellingStation.appearsOnStats = false
sellingStation.allowMissions = false
sellingStation.hasDynamic = false
if sellingStation.unloadTriggers ~= nil then
for _, unloadTrigger in pairs(sellingStation.unloadTriggers) do
unloadTrigger:delete()
end
THUtils.clearTable(sellingStation.unloadTriggers)
end
THUtils.hookFunction(sellingStation, "updateSupportedFillTypes", hook_updateSupportedFillTypes)
sellingStation:updateSupportedFillTypes()
end
if loadingStation ~= nil then
loadingStation.storageRadius = 0
loadingStation.supportsExtension = false
if loadingStation.loadTriggers ~= nil then
for _, loadTrigger in pairs(loadingStation.loadTriggers) do
loadTrigger:delete()
end
THUtils.clearTable(loadingStation.loadTriggers)
end
THUtils.hookFunction(loadingStation, "updateSupportedFillTypes", hook_updateSupportedFillTypes)
loadingStation:updateSupportedFillTypes()
end
return true
end
function SCProductionPoint:getMainStorage()
local production = self:getParent()
local storageData, storageInfo = g_thMain:getDataTable(production.storage)
return storageInfo, storageData
end
function SCProductionPoint:getExtendedStateType(stateType)
local controller = self.stateController
local stateTypeInfo = controller:getStateType(stateType)
if stateTypeInfo ~= nil then
return self.stateTypes[stateTypeInfo.id]
end
end
function SCProductionPoint:onUpdateProductionFinished(dt)
local parent = self:getParent()
local controller = self.stateController
local placeable = parent.owningPlaceable
local palletSpawner = parent.palletSpawner
local ownerFarmId = parent:getOwnerFarmId()
local isOwned = parent.isOwned
local timeAdjust = g_currentMission.environment.timeAdjustment
local minuteFactor = dt * parent.minuteFactorTimescaled * timeAdjust
local payOutFillTypes = parent.soldFillTypesToPayOut
local _, numRecipes = self:getProductionRecipeList()
local numActiveRecipes = 0
local areRecipesDirty = self.areRecipesDirty
if parent.activeProductions ~= nil then
numActiveRecipes = #parent.activeProductions
end
self.areRecipesDirty = false
if numRecipes > 0 then
for recipeIdx = 1, numRecipes do
local recipeInfo, recipeData = self:getProductionRecipe(recipeIdx)
if self.isServer and areRecipesDirty then
recipeData.isDirty = true
end
if not parent:getIsProductionEnabled(recipeInfo.id) then
if recipeData.isDirty then
self:updateProductionRecipes(recipeInfo.id)
end
else
local inputsTable = recipeInfo.inputs
local outputsTable = recipeInfo.outputs
local numInputs, numOutputs = #inputsTable, #outputsTable
local enoughInput, enoughOutput = true, true
local productionFactor = recipeInfo.cyclesPerMinute * minuteFactor
if parent.sharedThroughputCapacity == true then
productionFactor = productionFactor / math.max(1, numActiveRecipes)
end
recipeData.factor = 1
for inputIdx = 1, numInputs do
local inputInfo = inputsTable[inputIdx]
local inputFillType  = inputInfo.type
local inputAmount    = inputInfo.amount * productionFactor
local inputFillLevel = controller:getStorageValue("fillLevel", SCStateController.STATE_TYPE.INPUT, inputFillType)
parent.inputFillLevels[inputInfo] = inputFillLevel
if inputFillLevel == 0 and isOwned then
enoughInput = false
if recipeInfo.status ~= ProductionPoint.PROD_STATUS.MISSING_INPUTS then
recipeInfo.status = ProductionPoint.PROD_STATUS.MISSING_INPUTS
placeable:productionStatusChanged(recipeInfo, recipeInfo.status)
parent:setProductionStatus(recipeInfo.id, recipeInfo.status)
end
break
elseif isOwned then
if inputFillLevel < inputAmount then
local inputFactor = inputFillLevel / inputAmount
recipeData.factor = math.min(recipeData.factor, inputFactor)
end
end
end
if isOwned and enoughInput then
local usedOutputStorages = {}
for outputIdx = 1, numOutputs do
local outputInfo = outputsTable[outputIdx]
local outputFillType = outputInfo.type
local outputAmount   = outputInfo.amount * productionFactor
if not outputInfo.sellDirectly then
local outputFreeCapacity = controller:getStorageValue("freeCapacity", SCStateController.STATE_TYPE.OUTPUT, outputFillType)
if outputFreeCapacity > 0 then
for storageInfo, freeCapacity in pairs(controller.storageCache) do
if not storageInfo.supportsMultipleFillTypes then
if usedOutputStorages[storageInfo] ~= nil then
outputFreeCapacity = math.max(0, outputFreeCapacity - freeCapacity)
elseif freeCapacity > 0 then
usedOutputStorages[storageInfo] = freeCapacity
end
end
end
end
if outputFreeCapacity <= 0 then
enoughOutput = false
if recipeInfo.status ~= ProductionPoint.PROD_STATUS.NO_OUTPUT_SPACE then
recipeInfo.status = ProductionPoint.PROD_STATUS.NO_OUTPUT_SPACE
placeable:productionStatusChanged(recipeInfo, recipeInfo.status)
parent:setProductionStatus(recipeInfo.id, recipeInfo.status)
end
break
else
if outputFreeCapacity < outputAmount then
local outputFactor = outputFreeCapacity / outputAmount
recipeData.factor = math.min(recipeData.factor, outputFactor)
end
end
end
end
end
if isOwned then
parent.productionCostsToClaim = parent.productionCostsToClaim + (recipeInfo.costsPerActiveMinute * productionFactor)
end
if (not isOwned or enoughInput) and enoughOutput then
for inputIdx = 1, numInputs do
local inputInfo = inputsTable[inputIdx]
local inputFillType = inputInfo.type
local inputAmount   = inputInfo.amount * productionFactor * recipeData.factor
controller:addFillLevel(SCStateController.STATE_TYPE.INPUT, -inputAmount, inputFillType)
end
if isOwned then
for outputIdx = 1, numOutputs do
local outputInfo = outputsTable[outputIdx]
local outputFillType = outputInfo.type
local outputAmount   = outputInfo.amount * productionFactor * recipeData.factor
if outputInfo.sellDirectly then
if self.isServer then
payOutFillTypes[outputFillType] = payOutFillTypes[outputFillType] + outputAmount
end
else
controller:addFillLevel(SCStateController.STATE_TYPE.OUTPUT, outputAmount, outputFillType)
end
end
end
if recipeInfo.status ~= ProductionPoint.PROD_STATUS.RUNNING then
recipeInfo.status = ProductionPoint.PROD_STATUS.RUNNING
placeable:productionStatusChanged(recipeInfo, recipeInfo.status)
ProductionPointProductionStatusEvent.sendEvent(parent, recipeInfo.id, recipeInfo.status)
end
THUtils.clearTable(parent.inputFillLevels)
end
end
end
if palletSpawner ~= nil then
if self.isServer and isOwned and parent.palletSpawnCooldown < g_time and not parent.waitingForPalletToSpawn then
local nextFillTypeId = nil
while true do
local fillTypeId = parent.lastPalletFillTypeId
if fillTypeId ~= nil and parent.outputFillTypeIdsDirectSell[fillTypeId] == nil and parent.outputFillTypeIdsAutoDeliver[fillTypeId] == nil then
local fillLevel = controller:getStorageValue("fillLevel", SCStateController.STATE_TYPE.OUTPUT, fillTypeId)
if fillLevel > 0 then
local palletInfo = parent.outputFillTypeIdsToPallets[fillTypeId]
if palletInfo and fillLevel >= palletInfo.capacity then
nextFillTypeId = fillTypeId
break
end
end
end
parent.lastPalletFillTypeId = next(parent.outputFillTypeIdsToPallets, parent.lastPalletFillTypeId)
if parent.lastPalletFillTypeId == nil then
break
end
end
if nextFillTypeId ~= nil then
parent.waitingForPalletToSpawn = true
palletSpawner:spawnPallet(ownerFarmId, nextFillTypeId, parent.palletSpawnRequestCallback, parent)
end
end
end
end
parent.lastUpdatedTime = g_time
end
function SCProductionPoint:onStorageUpdated(controller, ...)
local function protectedFunc(...)
if self.isServer then
local thisController = self.stateController
if controller == thisController then
self.areRecipesDirty = true
elseif thisController.allowExtendedStorage then
local storageArray, numStorages = controller:getActiveStorageList()
if numStorages > 0 then
for storageIdx = 1, numStorages do
local storageInfo = storageArray[storageIdx]
if storageInfo.isExtension and thisController:getIsExtendedStorage(storageInfo) then
self.areRecipesDirty = true
break
end
end
end
end
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCProductionPoint:onFillLevelChanged(storageInfo, fillType, oldFillLevel, newFillLevel, ...)
local function protectedFunc(...)
if self.isServer then
local controller = self.stateController
local inputStateInfo = controller:getCurrentControlState(SCStateController.STATE_TYPE.INPUT)
local isStorageValid = false
if inputStateInfo ~= nil then
if controller:getIsStorageActive(storageInfo, inputStateInfo.type) then
if controller:getIsFillTypeActive(fillType, inputStateInfo.type) then
isStorageValid = true
end
elseif storageInfo.isExtension then
if controller:getIsExtendedStorage(storageInfo, inputStateInfo.type) then
if controller:getIsExtensionFillType(fillType, inputStateInfo.type) then
isStorageValid = true
end
end
end
end
if isStorageValid then
if newFillLevel <= 0 or oldFillLevel <= 0 then
self.areRecipesDirty = true
end
end
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCProductionPoint:actionToggleFillTypeMover(...)
local function protectedFunc(...)
local controller = self.stateController
local production = self:getParent()
if controller ~= nil and controller:getIsEnabled() then
if self.isClient then
local recipeInfo = self:getSpecialRecipe("SC_FILLTYPE_MOVER")
if recipeInfo ~= nil then
local isRecipeEnabled = production:getIsProductionEnabled(recipeInfo.id)
production:setProductionState(recipeInfo.id, not isRecipeEnabled)
end
end
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCProductionPoint:hook_load(superFunc, production, components, xmlFile, xmlKey, customEnv, i3dMappings, ...)
local xmlDataKey = g_thMain.xmlDataKey
local isControllerLoaded = true
local function prependFunc(...)
local controller = self.stateController
local controllerBaseKey = "placeable."..xmlDataKey..".productionPoint"
if controller ~= nil and xmlFile ~= nil and xmlKey ~= nil then
isControllerLoaded = false
if not controller:getIsEnabled() then
return
end
local function hook_xmlFileIterate(pSuperFunc, pSelf, pXMLKey, pIterateFunc, ...)
local function prependFunc2(...)
if pXMLKey ~= nil then
local relativeKey = pXMLKey:sub(#xmlKey + 1)
local isSellingStationTrigger = relativeKey:find(".sellingStation", 1, true) ~= nil
and relativeKey:find("unloadTrigger", 1, true) ~= nil
local isLoadingStationTrigger = relativeKey:find(".loadingStation", 1, true) ~= nil
and relativeKey:find("loadTrigger", 1, true) ~= nil
if isSellingStationTrigger or isLoadingStationTrigger then
pIterateFunc = function(...) end
else
local targetKey = pXMLKey:gsub(xmlKey, "")
if targetKey ~= nil and targetKey ~= "" then
if pSelf:hasProperty(controllerBaseKey..targetKey) then
pXMLKey = controllerBaseKey..targetKey
end
end
end
end
end
g_thMain:call(prependFunc2, ...)
return pSuperFunc(pSelf, pXMLKey, pIterateFunc, ...)
end
THUtils.makeTempHook(self, xmlFile, "iterate", hook_xmlFileIterate)
local function hook_storageLoad(pSuperFunc, pSelf, pComponents, pXmlFile, pXmlKey, ...)
local function appendFunc2(success, ...)
local function protectedChunk2()
if success and pSelf == production.storage then
if self:load(components, xmlFile, xmlKey, customEnv, i3dMappings) then
isControllerLoaded = true
end
end
end
g_thMain:call(protectedChunk2)
return success, ...
end
return appendFunc2(pSuperFunc(pSelf, pComponents, pXmlFile, pXmlKey, ...))
end
THUtils.makeTempHook(self, "Storage", "load", hook_storageLoad)
end
end
local function appendFunc(success, ...)
THUtils.restoreFunction(self, xmlFile, "iterate")
THUtils.restoreFunction(self, "Storage", "load")
local function protectedChunk()
success = success and isControllerLoaded
if success then
if not self:finishLoading() then
success = false
end
end
end
g_thMain:call(protectedChunk)
return success, ...
end
g_thMain:call(prependFunc, ...)
return appendFunc(superFunc(production, components, xmlFile, xmlKey, customEnv, i3dMappings, ...))
end
function SCProductionPoint:hook_delete(superFunc, parent, ...)
local function appendFunc(...)
self:delete()
return ...
end
return appendFunc(superFunc(parent, ...))
end
function SCProductionPoint:hook_writeStream(superFunc, parent, streamId, connection, ...)
local controller = self.stateController
local function appendFunc(...)
if not connection:getIsServer() then
if self.isServer and controller ~= nil and controller:getIsEnabled() then
self.areRecipesDirty = true
end
end
end
return appendFunc(superFunc(parent, streamId, connection, ...))
end
function SCProductionPoint:hook_getFillLevel(superFunc, production, fillType, ...)
local controller = self.stateController
local function appendFunc(rValue, ...)
local function protectedChunk()
if controller ~= nil and controller:getIsEnabled() then
local newFillLevel = production.storage:getFillLevel(fillType)
rValue = THUtils.getNoNil(newFillLevel, 0)
end
end
g_thMain:call(protectedChunk)
return rValue, ...
end
return appendFunc(superFunc(production, fillType, ...))
end
function SCProductionPoint:hook_getCapacity(superFunc, production, fillType, ...)
local controller = self.stateController
local function appendFunc(rValue, ...)
local function protectedChunk()
if controller ~= nil and controller:getIsEnabled() then
local newFillLevel = production.storage:getCapacity(fillType)
rValue = THUtils.getNoNil(newFillLevel, 0)
end
end
g_thMain:call(protectedChunk)
return rValue, ...
end
return appendFunc(superFunc(production, fillType, ...))
end
function SCProductionPoint:hook_updateProduction(superFunc, parent, ...)
local controller = self.stateController
local oldLastUpdatedTime = parent.lastUpdatedTime
local prependSuccess = false
local function prependFunc(...)
if controller ~= nil and controller:getIsEnabled() then
if oldLastUpdatedTime ~= nil then
parent.lastUpdatedTime = nil
prependSuccess = true
end
end
end
local function appendFunc(...)
local function protectedChunk()
if prependSuccess then
local dt = math.clamp(g_time - oldLastUpdatedTime, 0, 30000)
parent.lastUpdatedTime = oldLastUpdatedTime
self:onUpdateProductionFinished(dt)
end
end
g_thMain:call(protectedChunk)
return ...
end
g_thMain:call(prependFunc, ...)
return appendFunc(superFunc(parent, ...))
end
function SCProductionPoint:hook_updateInfo(superFunc, production, ...)
local oldInputFillTypesArray, oldOutputFillTypesArray = nil,nil
local hasInputFillTypes, hasOutputFillTypes = false, false
local function prependFunc(...)
local controller = self.stateController
local recipeFillTypes = self:getRecipeFillTypeList()
if controller ~= nil and controller:getIsEnabled() then
oldInputFillTypesArray = production.inputFillTypeIdsArray
oldOutputFillTypesArray = production.outputFillTypeIdsArray
hasInputFillTypes = oldInputFillTypesArray ~= nil
hasOutputFillTypes = oldOutputFillTypesArray ~= nil
production.inputFillTypeIdsArray = recipeFillTypes
production.outputFillTypeIdsArray = {}
local function hook_getFillLevel(pSuperFunc, pSelf, pFillType, ...)
local function appendFunc2(rValue, ...)
local function protectedChunk2()
if pSelf == production and pFillType ~= nil then
if controller:getIsMultiStateFillType(pFillType) then
local otherValue = controller:getStorageValue("fillLevel", SCStateController.STATE_TYPE.NONE, pFillType)
if otherValue ~= nil then
rValue = otherValue
end
end
end
end
g_thMain:call(protectedChunk2)
return rValue, ...
end
return appendFunc2(pSuperFunc(pSelf, pFillType, ...))
end
THUtils.makeTempHook(self, production, "getFillLevel", hook_getFillLevel)
end
end
local function appendFunc(...)
if hasInputFillTypes then production.inputFillTypeIdsArray = oldInputFillTypesArray end
if hasOutputFillTypes then production.outputFillTypeIdsArray = oldOutputFillTypesArray end
THUtils.restoreFunction(self, production, "getFillLevel")
return ...
end
g_thMain:call(prependFunc, ...)
return appendFunc(superFunc(production, ...))
end
function SCProductionPoint:hook_directlySellOutputs(superFunc, production, ...)
local controller = self.stateController
local prependSuccess = false
local function prependFunc(...)
if controller ~= nil and controller:getIsEnabled() then
if controller:setCurrentStateType(SCStateController.STATE_TYPE.OUTPUT) then
prependSuccess = true
end
end
end
local function appendFunc(...)
local function protectedChunk()
if prependSuccess then
controller:setCurrentStateType(nil)
end
end
g_thMain:call(protectedChunk)
return ...
end
g_thMain:call(prependFunc, ...)
return appendFunc(superFunc(production, ...))
end
function SCProductionPoint:hook_palletSpawnRequestCallback(superFunc, production, pallet, status, fillType, ...)
local controller = self.stateController
local prependSuccess = false
local function prependFunc(...)
if controller ~= nil and controller:getIsEnabled() then
if fillType ~= nil then
if controller:setCurrentStateType(SCStateController.STATE_TYPE.OUTPUT, fillType) then
prependSuccess = true
end
end
end
end
local function appendFunc(...)
local function protectedChunk()
if prependSuccess then
controller:setCurrentStateType(nil, fillType)
end
end
g_thMain:call(protectedChunk)
return ...
end
g_thMain:call(prependFunc, ...)
return appendFunc(superFunc(production, pallet, status, fillType, ...))
end
SCProductionPoint.SCStateController = {}
function SCProductionPoint.SCStateController:hook_getIsFillTypeActive(superFunc, controller, fillType, stateType, ...)
local function appendFunc(rIsActive, ...)
local function protectedChunk()
if controller == self.stateController and controller:getIsEnabled() then
if rIsActive then
local newIsActive = self:getIsRecipeFillType(fillType, stateType)
if newIsActive ~= nil then
rIsActive = newIsActive
end
end
end
end
g_thMain:call(protectedChunk)
return rIsActive, ...
end
return appendFunc(superFunc(controller, fillType, stateType, ...))
end
function SCProductionPoint.SCStateController:hook_getActiveFillTypeList(superFunc, controller, stateType, byId, ...)
local function appendFunc(rFillTypeList, rNumFillTypes, ...)
local function protectedChunk()
if controller == self.stateController and controller:getIsEnabled() then
if rNumFillTypes ~= nil then
local newFillTypeList, newNumFillTypes = self:getRecipeFillTypeList(stateType, byId)
if newNumFillTypes ~= nil then
rFillTypeList = newFillTypeList
rNumFillTypes = newNumFillTypes
end
end
end
end
g_thMain:call(protectedChunk)
return rFillTypeList, rNumFillTypes, ...
end
return appendFunc(superFunc(controller, ...))
end
SCProductionPoint.SCStateControllerActivatable = {}
function SCProductionPoint.SCStateControllerActivatable:hook_getIsActivatable(superFunc, activatable, ...)
local function appendFunc(rIsActivatable, ...)
local function protectedChunk()
local controller = self.stateController
if controller ~= nil and controller == activatable.stateController and controller:getIsEnabled() then
if rIsActivatable then
end
end
end
g_thMain:call(protectedChunk)
return rIsActivatable, ...
end
return appendFunc(superFunc(activatable, ...))
end
function SCProductionPoint.SCStateControllerActivatable:hook_registerCustomInput(superFunc, activatable, ...)
local function appendFunc(...)
local function protectedChunk()
local controller = self.stateController
local inputBinding = self.inputBinding
if controller ~= nil and controller == activatable.stateController and controller:getIsEnabled() then
if self.isClient then
for recipeId in pairs(self.specialRecipes) do
local _, recipeEventId = nil,nil
if recipeId == "SC_FILLTYPE_MOVER" then
_, recipeEventId = inputBinding:registerActionEvent(InputAction.SC_ACTIVATE_FILLTYPE_MOVER, self, self.actionToggleFillTypeMover, false, true, false, true)
if recipeEventId ~= nil then
inputBinding:setActionEventTextVisibility(recipeEventId, true)
inputBinding:setActionEventTextPriority(recipeEventId, GS_PRIO_HIGH)
self.recipeEventIds[recipeId] = recipeEventId
end
end
end
end
end
end
g_thMain:call(protectedChunk)
return ...
end
return appendFunc(superFunc(activatable, ...))
end
function SCProductionPoint.SCStateControllerActivatable:hook_removeCustomInput(superFunc, activatable, ...)
local function appendFunc(...)
local function protectedChunk()
local controller = self.stateController
local inputBinding = self.inputBinding
if controller ~= nil and controller == activatable.stateController then
for _, recipeEventId in pairs(self.recipeEventIds) do
inputBinding:removeActionEvent(recipeEventId)
end
THUtils.clearTable(self.recipeEventIds)
end
end
g_thMain:call(protectedChunk)
return ...
end
return appendFunc(superFunc(activatable, ...))
end
function SCProductionPoint.SCStateControllerActivatable:hook_updateActionEvents(superFunc, activatable, ...)
local function appendFunc(...)
local function protectedChunk()
local controller = self.stateController
local production = self:getParent()
local inputBinding = self.inputBinding
local i18n = self.i18n
if controller ~= nil and controller == activatable.stateController and controller:getIsEnabled() then
if self.isClient then
for recipeId, eventId in pairs(self.recipeEventIds) do
if recipeId == "SC_FILLTYPE_MOVER" then
if production:getIsProductionEnabled(recipeId) then
inputBinding:setActionEventText(eventId, i18n:getText("scAction_moveToOutputOff"))
else
inputBinding:setActionEventText(eventId, i18n:getText("scAction_moveToOutputOn"))
end
end
end
end
end
end
g_thMain:call(protectedChunk)
return ...
end
return appendFunc(superFunc(activatable, ...))
end
function SCProductionPoint.SCStateControllerActivatable:hook_actionSelectControlState(superFunc, activatable, actionName, inputValue, stateType, ...)
local function appendFunc(...)
local function protectedChunk()
local controller = self.stateController
local production = self:getParent()
if controller ~= nil and controller == activatable.stateController and controller:getIsEnabled() then
if self.isClient then
local recipeList, numRecipes = self:getProductionRecipeList()
if numRecipes > 0 then
for recipeIdx = 1, numRecipes do
local recipeInfo = recipeList[recipeIdx]
local isRecipeEnabled = production:getIsProductionEnabled(recipeInfo.id)
if isRecipeEnabled then
production:setProductionState(recipeInfo.id, not isRecipeEnabled)
end
end
end
end
end
end
g_thMain:call(protectedChunk)
return ...
end
return appendFunc(superFunc(activatable, actionName, inputValue, stateType, ...))
end
SCProductionStorage = {}
SCProductionStorage_mt = Class(SCProductionStorage, THData)
function SCProductionStorage.initialize(dataTable, controller)
local self = dataTable
self.getParent = function(pSelf)
return SCProductionStorage:superClass().getParent(pSelf)
end
if THUtils.argIsValid(THUtils.getIsType(controller, SCStateController), "controller", controller, true) then
self.stateController  = controller
self.isRoutingEnabled = true
local parent = self:getParent()
g_thMain:setFunctionHook(parent, "setFillLevel",      SCProductionStorage, nil, self)
g_thMain:setFunctionHook(parent, "getFillLevel",      SCProductionStorage, nil, self)
g_thMain:setFunctionHook(parent, "getCapacity",       SCProductionStorage, nil, self)
g_thMain:setFunctionHook(parent, "getFreeCapacity",   SCProductionStorage, nil, self)
g_thMain:setFunctionHook(parent, "empty",             SCProductionStorage, nil, self)
g_thMain:setFunctionHook(parent, "readStream",        SCProductionStorage, nil, self)
g_thMain:setFunctionHook(parent, "writeStream",       SCProductionStorage, nil, self)
g_thMain:setFunctionHook(parent, "readUpdateStream",  SCProductionStorage, nil, self)
g_thMain:setFunctionHook(parent, "writeUpdateStream", SCProductionStorage, nil, self)
return true
end
return false
end
function SCProductionStorage:hook_setFillLevel(superFunc, parent, fillLevel, fillType, ...)
local controller = self.stateController
local prependSuccess = false
local function prependFunc(...)
if controller ~= nil and controller:getIsEnabled() then
if self.isRoutingEnabled then
if fillType ~= nil and fillLevel ~= nil then
local oldFillLevel = parent:getFillLevel(fillType)
local deltaFill = fillLevel - oldFillLevel
local totalApplied, totalRemaining = controller:addFillLevel(nil, deltaFill, fillType, false, ...)
if totalApplied ~= nil and totalRemaining ~= nil then
prependSuccess = true
end
end
end
end
end
g_thMain:call(prependFunc, ...)
if not prependSuccess then
return superFunc(parent, fillLevel, fillType, ...)
end
end
function SCProductionStorage:hook_getFillLevel(superFunc, parent, fillType, ...)
local controller = self.stateController
local prependSuccess, totalValue = false, 0
local function prependFunc(...)
if controller ~= nil and controller:getIsEnabled() then
if self.isRoutingEnabled then
totalValue = controller:getStorageValue("fillLevel", nil, fillType, false, ...)
if totalValue ~= nil then
prependSuccess = true
end
end
end
end
local function appendFunc(rValue, ...)
if prependSuccess then
rValue = totalValue
end
return rValue, ...
end
g_thMain:call(prependFunc, ...)
return appendFunc(superFunc(parent, fillType, ...))
end
function SCProductionStorage:hook_getCapacity(superFunc, parent, fillType, ...)
local controller = self.stateController
local prependSuccess, totalValue = false, 0
local function prependFunc(...)
if controller ~= nil and controller:getIsEnabled() then
if self.isRoutingEnabled then
totalValue = controller:getStorageValue("capacity", nil, fillType, false, ...)
if totalValue ~= nil then
prependSuccess = true
end
end
end
end
local function appendFunc(rValue, ...)
if prependSuccess then
rValue = totalValue
end
return rValue, ...
end
g_thMain:call(prependFunc, ...)
return appendFunc(superFunc(parent, fillType, ...))
end
function SCProductionStorage:hook_getFreeCapacity(superFunc, parent, fillType, ...)
local controller = self.stateController
local prependSuccess, totalValue = false, 0
local function prependFunc(...)
if controller ~= nil and controller:getIsEnabled() then
if self.isRoutingEnabled then
totalValue = controller:getStorageValue("freeCapacity", nil, fillType, false, ...)
if totalValue ~= nil then
prependSuccess = true
end
end
end
end
local function appendFunc(rValue, ...)
if prependSuccess then
rValue = totalValue
end
return rValue, ...
end
g_thMain:call(prependFunc, ...)
return appendFunc(superFunc(parent, fillType, ...))
end
function SCProductionStorage:hook_empty(superFunc, parent, ...)
local controller = self.stateController
local function appendFunc(...)
local function protectedChunk()
if controller ~= nil and controller:getIsEnabled() then
if self.isRoutingEnabled then
controller:emptyStorage()
end
end
end
g_thMain:call(protectedChunk)
return ...
end
return appendFunc(superFunc(parent, ...))
end
function SCProductionStorage:hook_readStream(superFunc, parent, ...)
local lastIsRoutingEnabled = self.isRoutingEnabled
self.isRoutingEnabled = false
local function appendFunc(...)
self.isRoutingEnabled = lastIsRoutingEnabled
return ...
end
return appendFunc(superFunc(parent, ...))
end
function SCProductionStorage:hook_writeStream(superFunc, parent, ...)
local lastIsRoutingEnabled = self.isRoutingEnabled
self.isRoutingEnabled = false
local function appendFunc(...)
self.isRoutingEnabled = lastIsRoutingEnabled
return ...
end
return appendFunc(superFunc(parent, ...))
end
function SCProductionStorage:hook_readUpdateStream(superFunc, parent, streamId, timestamp, connection, ...)
local lastIsRoutingEnabled = self.isRoutingEnabled
self.isRoutingEnabled = false
local function appendFunc(...)
self.isRoutingEnabled = lastIsRoutingEnabled
return ...
end
return appendFunc(superFunc(parent, streamId, timestamp, connection, ...))
end
function SCProductionStorage:hook_writeUpdateStream(superFunc, parent, streamId, connection, dirtyMask, ...)
local lastIsRoutingEnabled = self.isRoutingEnabled
self.isRoutingEnabled = false
local function appendFunc(...)
self.isRoutingEnabled = lastIsRoutingEnabled
return ...
end
return appendFunc(superFunc(parent, streamId, connection, dirtyMask, ...))
end