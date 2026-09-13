-- Copyright ©2023 by Todd Hundersmarck (ThundR)
-- All Rights Reserved

SCPlaceableProductionController = {}
function SCPlaceableProductionController.prerequisitesPresent(specializations)
if SpecializationUtil.hasSpecialization(PlaceableProductionPoint, specializations) then
return true
end
return false
end
function SCPlaceableProductionController.registerXMLPaths(schema, path)
local xmlDataKey = g_thMain.xmlDataKey
schema:setXMLSpecializationType("SCProductionStateController")
SCStateController.registerXMLPaths(schema, path.."."..xmlDataKey)
schema:setXMLSpecializationType()
end
function SCPlaceableProductionController.registerSavegameXMLPaths(schema, path)
schema:setXMLSpecializationType("SCProductionStateController")
SCStateController.registerSavegameXMLPaths(schema, path)
schema:setXMLSpecializationType()
end
function SCPlaceableProductionController.registerEventListeners(placeableType)
SpecializationUtil.registerEventListener(placeableType, "onDelete",             SCPlaceableProductionController)
SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement",  SCPlaceableProductionController)
SpecializationUtil.registerEventListener(placeableType, "onReadStream",         SCPlaceableProductionController)
SpecializationUtil.registerEventListener(placeableType, "onWriteStream",        SCPlaceableProductionController)
end
function SCPlaceableProductionController.registerOverwrittenFunctions(placeableType)
SpecializationUtil.registerOverwrittenFunction(placeableType, "setOwnerFarmId",     SCPlaceableProductionController.setOwnerFarmId)
SpecializationUtil.registerOverwrittenFunction(placeableType, "collectPickObjects", SCPlaceableProductionController.collectPickObjects)
end
function SCPlaceableProductionController:onLoad(superFunc, savegame, ...)
local specTable = g_thMain:getSpecTable(self, "productionController")
local xmlDataKey = g_thMain.xmlDataKey
local xmlBaseKey = "placeable."..xmlDataKey
local xmlFile = self.xmlFile
local components = self.components
local i3dMappings = self.i3dMappings
local customEnv = self.customEnvironment
local specializations = self.specializations
local function prependFunc(...)
if SpecializationUtil.hasSpecialization(SCPlaceableProductionController, specializations)
and specTable ~= nil and xmlFile ~= nil and xmlFile:hasProperty(xmlBaseKey)
then
local function hook_newProduction(pSuperFunc, ...)
local function appendFunc2(production, ...)
local function protectedChunk2()
if production ~= nil then
local controller = SCStateController.new(self, production)
if controller ~= nil then
if controller:load(components, xmlFile, xmlBaseKey, customEnv, i3dMappings) then
g_thMain:createDataTable(production, false, nil,nil, SCProductionPoint_mt, controller)
specTable.stateController = controller
else
controller:delete()
end
end
end
end
g_thMain:call(protectedChunk2)
return production, ...
end
return appendFunc2(pSuperFunc(...))
end
THUtils.makeTempHook(self, "ProductionPoint", "new", hook_newProduction)
end
end
local function appendFunc(...)
THUtils.restoreFunction(self, "ProductionPoint", "new")
return ...
end
g_thMain:call(prependFunc, ...)
return appendFunc(superFunc(self, savegame, ...))
end
function SCPlaceableProductionController:onDelete(...)
local function protectedFunc(...)
local specTable = g_thMain:getSpecTable(self, "productionController")
local controller = specTable.stateController
if controller ~= nil then
controller:delete()
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCPlaceableProductionController:onFinalizePlacement(...)
local function protectedFunc(...)
local specTable = g_thMain:getSpecTable(self, "productionController")
local controller = specTable.stateController
local ownerFarmId = self:getOwnerFarmId()
if controller ~= nil then
controller:register(true)
controller:setOwnerFarmId(ownerFarmId)
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCPlaceableProductionController:onReadStream(streamId, connection, ...)
local specTable = g_thMain:getSpecTable(self, "productionController")
if specTable ~= nil then
local controller = specTable.stateController
if controller ~= nil then
local controllerId = NetworkUtil.readNodeObjectId(streamId)
controller:readStream(streamId, connection)
g_client:finishRegisterObject(controller, controllerId)
end
end
end
function SCPlaceableProductionController:onWriteStream(streamId, connection)
local specTable = g_thMain:getSpecTable(self, "productionController")
if specTable ~= nil then
local controller = specTable.stateController
if controller ~= nil then
NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(controller))
controller:writeStream(streamId, connection)
g_server:registerObjectInStream(connection, controller)
end
end
end
function SCPlaceableProductionController:loadFromXMLFile(xmlFile, key, ...)
local function protectedFunc(...)
local specTable = g_thMain:getSpecTable(self, "productionController")
local controller = specTable.stateController
if controller ~= nil then
controller:loadFromXMLFile(xmlFile, key)
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCPlaceableProductionController:saveToXMLFile(xmlFile, key, useModNames, ...)
local function protectedFunc(...)
local specTable = g_thMain:getSpecTable(self, "productionController")
local controller = specTable.stateController
if controller ~= nil then
controller:saveToXMLFile(xmlFile, key, useModNames)
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCPlaceableProductionController:setOwnerFarmId(superFunc, farmId, noEventSend, ...)
local function appendFunc(...)
local function protectedChunk()
local specTable = g_thMain:getSpecTable(self, "productionController")
local controller = specTable.stateController
if controller ~= nil then
controller:setOwnerFarmId(farmId, noEventSend)
end
end
g_thMain:call(protectedChunk)
return ...
end
return appendFunc(superFunc(self, farmId, noEventSend, ...))
end
function SCPlaceableProductionController:collectPickObjects(superFunc, node, ...)
local function prependFunc(...)
if node ~= nil then
local specTable = g_thMain:getSpecTable(self, "productionController")
local controller = specTable.stateController
if controller ~= nil then
for _, sellingStation in pairs(controller.sellingStations) do
if sellingStation.unloadTriggers ~= nil then
for _, unloadTrigger in pairs(sellingStation.unloadTriggers) do
if node == unloadTrigger.exactFillRootNode then
return true
end
end
end
end
for _, loadingStation in pairs(controller.loadingStations) do
if loadingStation.loadTriggers ~= nil then
for _, loadTrigger in pairs(loadingStation.loadTriggers) do
if node == loadTrigger.triggerNode then
return true
end
end
end
end
end
end
return false
end
if g_thMain:call(prependFunc, ...) then
return
end
return superFunc(self, node, ...)
end
local function runScript()
g_thMain:setFunctionHook("PlaceableProductionPoint", "onLoad", SCPlaceableProductionController, "onLoad", true)
end
g_thMain:call(runScript)