-- Copyright ©2023 by Todd Hundersmarck (ThundR)
-- All Rights Reserved

SCUpdateProductionRecipeEvent = {}
local SCUpdateProductionRecipeEvent_mt = Class(SCUpdateProductionRecipeEvent, Event)
InitEventClass(SCUpdateProductionRecipeEvent, "SCUpdateProductionRecipeEvent")
function SCUpdateProductionRecipeEvent.emptyNew()
return Event.new(SCUpdateProductionRecipeEvent_mt)
end
function SCUpdateProductionRecipeEvent.new(production, recipeId)
local self = SCUpdateProductionRecipeEvent.emptyNew()
if  THUtils.argIsValid(THUtils.getIsType(production, ProductionPoint), "production", production, true)
and THUtils.argIsValid(type(recipeId) == "string", "recipeId", recipeId, true)
then
local productionData = g_thMain:getDataTable(production)
if productionData ~= nil then
local recipeInfo, recipeData = productionData:getProductionRecipe(recipeId)
if recipeData ~= nil then
if recipeData.type == SCProductionPoint.RECIPE_TYPE.DYNAMIC
or recipeData.type == SCProductionPoint.RECIPE_TYPE.SPECIAL
then
local inputsTable, numInputs = recipeInfo.inputs, #recipeInfo.inputs
local outputsTable, numOutputs = recipeInfo.outputs, #recipeInfo.outputs
if numInputs > 0 and numOutputs > 0 then
self.production = production
self.recipeId = recipeInfo.id
self.inputsTable = inputsTable
self.outputsTable = outputsTable
self.numInputs = numInputs
self.numOutputs = numOutputs
self.primaryFillType = THUtils.getNoNil(recipeInfo.primaryProductFillType, FillType.UNKNOWN)
return self
end
end
end
end
end
end
function SCUpdateProductionRecipeEvent:readStream(streamId, connection)
self.production      = NetworkUtil.readNodeObject(streamId)
self.recipeId        = streamReadString(streamId)
self.primaryFillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
self.inputsTable = {}
self.outputsTable = {}
self.numInputs = streamReadUIntN(streamId, 16)
self.numOutputs = streamReadUIntN(streamId, 16)
for inputIdx = 1, self.numInputs do
local inputInfo = {}
inputInfo.type = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
inputInfo.amount = streamReadFloat32(streamId)
self.inputsTable[inputIdx] = inputInfo
end
for outputIdx = 1, self.numOutputs do
local outputInfo = {}
outputInfo.type = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
outputInfo.amount = streamReadFloat32(streamId)
outputInfo.sellDirectly = streamReadBool(streamId)
self.outputsTable[outputIdx] = outputInfo
end
self:run(connection)
end
function SCUpdateProductionRecipeEvent:writeStream(streamId, connection)
NetworkUtil.writeNodeObject(streamId, self.production)
streamWriteString(streamId, self.recipeId)
streamWriteUIntN(streamId, self.primaryFillType, FillTypeManager.SEND_NUM_BITS)
streamWriteUIntN(streamId, self.numInputs, 16)
streamWriteUIntN(streamId, self.numOutputs, 16)
for inputIdx = 1, self.numInputs do
local inputInfo = self.inputsTable[inputIdx]
local inputFillType = THUtils.getNoNil(inputInfo.type, FillType.UNKNOWN)
local inputAmount = THUtils.getNoNil(inputInfo.amount, 0)
streamWriteUIntN(streamId, inputFillType, FillTypeManager.SEND_NUM_BITS)
streamWriteFloat32(streamId, inputAmount)
end
for outputIdx = 1, self.numOutputs do
local outputInfo = self.outputsTable[outputIdx]
local outputFillType = THUtils.getNoNil(outputInfo.type, FillType.UNKNOWN)
local outputAmount = THUtils.getNoNil(outputInfo.amount, 0)
local sellDirectly = THUtils.getNoNil(outputInfo.sellDirectly, false)
streamWriteUIntN(streamId, outputFillType, FillTypeManager.SEND_NUM_BITS)
streamWriteFloat32(streamId, outputAmount)
streamWriteBool(streamId, sellDirectly)
end
end
function SCUpdateProductionRecipeEvent:run(connection)
local function protectedFunc()
local production      = self.production
local recipeId        = self.recipeId
local inputsTable     = self.inputsTable
local outputsTable    = self.outputsTable
local numInputs       = self.numInputs
local numOutputs      = self.numOutputs
local primaryFillType = self.primaryFillType
if connection:getIsServer() then
local productionData = g_thMain:getDataTable(production)
if productionData ~= nil then
local recipeInfo, recipeData = productionData:getProductionRecipe(recipeId)
if recipeData ~= nil then
THUtils.clearTable(recipeInfo.inputs)
THUtils.clearTable(recipeInfo.outputs)
for inputIdx = 1, numInputs do
local inputInfo = inputsTable[inputIdx]
recipeInfo.inputs[inputIdx] = inputInfo
end
for outputIdx = 1, numOutputs do
local outputInfo = outputsTable[outputIdx]
recipeInfo.outputs[outputIdx] = outputInfo
end
recipeInfo.primaryProductFillType = primaryFillType
end
end
end
end
return g_thMain:call(protectedFunc)
end
function SCUpdateProductionRecipeEvent.sendEvent(production, recipeId)
local function protectedFunc()
local newEvent = SCUpdateProductionRecipeEvent.new(production, recipeId)
if newEvent ~= nil then
if g_server ~= nil then
g_server:broadcastEvent(newEvent)
end
end
end
return g_thMain:call(protectedFunc)
end