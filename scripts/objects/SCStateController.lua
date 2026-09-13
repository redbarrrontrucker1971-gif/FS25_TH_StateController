-- Copyright ©2023 by Todd Hundersmarck (ThundR)
-- All Rights Reserved

SCStateController = {}
SCStateController_mt = Class(SCStateController, Object)
InitObjectClass(SCStateController, "SCStateController")
SCStateController.NUM_STORAGE_BITS = 8
SCStateController.NUM_STATION_BITS = 8
SCStateController.NUM_STATE_BITS = 16
SCStateController.NUM_STATE_TYPE_BITS = 2
SCStateController.MAX_STATE_TYPES = 2
SCStateController.STATE_TYPE = {
NONE   = 0,
INPUT  = 1,
OUTPUT = 2
}
SCStateController.MSG = {
APPLY_DELTA_FAIL = "Could not apply remaining delta (%s) to storage %q"
}
SCStateController.MESSAGE_TYPE = {
STORAGE_UPDATED = nextMessageTypeId()
}
function SCStateController.new(placeable, production, customMt)
customMt = THUtils.getNoNil(customMt, SCStateController_mt)
if  THUtils.argIsValid(THUtils.getIsType(placeable, Placeable), "placeable", placeable, true)
and THUtils.argIsValid(production == nil or THUtils.getIsType(production, ProductionPoint), "production", production, true)
then
local self = Object.new(placeable.isServer, placeable.isClient, customMt)
if self ~= nil then
self.parentPlaceable = placeable
self.productionPoint = production
self.messageCenter = g_thMain.messageCenter
self.inputBinding = g_thMain.inputBinding
self.storageSystem = g_currentMission.storageSystem
self.accessHandler = g_currentMission.accessHandler
self.i18n = g_thMain.i18n
self.sellingStations = {}
self.sellingStationMapping = {}
self.loadingStations = {}
self.loadingStationMapping = {}
self.storages = {
byId     = {},
byIndex  = {},
byTarget = {}
}
self.storageCache = {}
self.activeStorages = {}
self.activeStoragesArray = {}
self.allowExtendedStorage = false
self.extendedStorages = {}
self.extendedStorageMapping = {}
self.storageFillTypes = {}
self.storageFillTypesArray = {}
self.activeFillTypes = {}
self.activeFillTypesArray = {}
self.stateTypes = {
byId      = {},
byIndex   = {},
byTarget  = {}
}
self.currentStateType = {}
for stateTypeId, stateTypeIndex in pairs(SCStateController.STATE_TYPE) do
local stateTypeInfo = {
id    = stateTypeId,
name  = stateTypeId:lower(),
index = stateTypeIndex
}
stateTypeInfo.properName = THUtils.properCase(stateTypeInfo.name)
stateTypeInfo.controlStates = {
byId     = {},
byIndex  = {},
byTarget = {}
}
stateTypeInfo.currentControlState = 0
stateTypeInfo.storages = {}
stateTypeInfo.storageMapping = {}
stateTypeInfo.storageFillTypes = {}
stateTypeInfo.storageFillTypesArray = {}
stateTypeInfo.activateText = self.i18n:getText("scAction_select"..stateTypeInfo.properName.."State")
stateTypeInfo.activateAction = InputAction["SC_SELECT_"..stateTypeInfo.id.."_STATE"]
self.stateTypes.byId[stateTypeInfo.id] = stateTypeInfo
self.stateTypes.byIndex[stateTypeInfo.index] = stateTypeInfo
self.stateTypes.byTarget[stateTypeInfo] = stateTypeInfo
end
self.hudBox = g_currentMission.hud.infoDisplay:createBox(KeyValueInfoHUDBox)
self.hudInfo = {}
self.infoTitle = ""
self.rootNode = placeable.rootNode
self.activatable = nil
self.triggerNode = nil
self.isInTrigger = false
self.isEnabled = false
self.isStorageDirty  = false
self.areVisualsDirty = false
self.isLoadFinished  = false
end
return self
end
end
function SCStateController.registerXMLPaths(schema, path)
schema:register(XMLValueType.STRING, path.."#infoTitle", "Info box title")
schema:register(XMLValueType.NODE_INDEX, path.."#triggerNode", "Controller trigger node")
local productionPath = path..".productionPoint"
SCProductionPoint.registerXMLPaths(schema, productionPath)
local sellingStationPath = path..".sellingStations.sellingStation(?)"
SCSellingStation.registerXMLPaths(schema, sellingStationPath)
local loadingStationPath = path..".loadingStations.loadingStation(?)"
SCLoadingStation.registerXMLPaths(schema, loadingStationPath)
local storagePath = path..".storages.storage(?)"
SCStorage.registerXMLPaths(schema, storagePath)
local function registerControlStatePaths(pStatesPath)
schema:register(XMLValueType.STRING, pStatesPath.."#activateText", "State activation text")
schema:register(XMLValueType.STRING, pStatesPath.."#activateAction", "State activation input action")
local statePath = pStatesPath..".state(?)"
schema:register(XMLValueType.STRING, statePath.."#id", "Control state unique name")
schema:register(XMLValueType.STRING, statePath.."#title", "Control state l10n title")
THUtils.registerXMLPath(schema, XMLValueType.STRING, statePath, "#storageIds #storages", "String list of linked storage ids")
THUtils.registerXMLPath(schema, XMLValueType.BOOL,   statePath, "#allowExtensions", "Allow silo extensions", false)
THUtils.registerXMLPath(schema, XMLValueType.FLOAT,  statePath, "#extensionRange", "Silo extension max range", 50)
THUtils.registerXMLPath(schema, XMLValueType.STRING, statePath, "#extensionFillTypes", "Extendible fillType names")
ObjectChangeUtil.registerObjectChangeXMLPaths(schema, statePath..".objectChanges")
end
registerControlStatePaths(path..".inputStates")
registerControlStatePaths(path..".outputStates")
end
function SCStateController.registerSavegameXMLPaths(schema, path)
schema:register(XMLValueType.INT, path.."#inputState",  "Current input control state", 0)
schema:register(XMLValueType.INT, path.."#outputState", "Current output control state", 0)
local storagePath = path..".storages.storage(?)"
SCStorage.registerSavegameXMLPaths(schema, storagePath)
end
function SCStateController:load(components, xmlFile, xmlKey, customEnv, i3dMappings)
if not self.isLoadFinished then
self.isEnabled = false
local function hook_xmlGetValue(pSuperFunc, pSelf, pXMLKey, ...)
if pSelf == xmlFile and pXMLKey ~= nil then
local function appendFunc2(rValue, ...)
local function protectedChunk2()
local _, _, xmlPath2, xmlKey2 = pXMLKey:find("(.+)(%#.+)")
if xmlPath2 ~= nil and xmlKey2 ~= nil then
if xmlKey2 == "#fillTypeCategories" then
if pSuperFunc(pSelf, xmlPath2.."#fillTypes") ~= nil then
rValue = nil
end
elseif xmlKey2 == "#fillTypes" then
if rValue ~= nil then
local fillTypeNames = rValue
local categoryNames = pSuperFunc(pSelf, xmlPath2.."#fillTypeCategories")
if categoryNames ~= nil then
local newFillTypeNames = THUtils.getFillTypeNamesByCategories(categoryNames, fillTypeNames)
if newFillTypeNames ~= nil then
rValue = newFillTypeNames
end
end
end
end
end
end
g_thMain:call(protectedChunk2)
return rValue, ...
end
return appendFunc2(pSuperFunc(pSelf, pXMLKey, ...))
end
end
THUtils.hookFunction(xmlFile, "getValue", hook_xmlGetValue)
local infoTitle = xmlFile:getValue(xmlKey.."#infoTitle")
local triggerNode = xmlFile:getValue(xmlKey.."#triggerNode", nil, components, i3dMappings)
if infoTitle ~= nil then
infoTitle = self.i18n:convertText(infoTitle, customEnv)
else
infoTitle = g_thMain.modTitle
end
self.infoTitle = infoTitle
if triggerNode == nil then
THUtils.errorMsg(false, "Failed to load trigger node")
return false
end
self.triggerNode = triggerNode
if  self:loadStorages(components, xmlFile, xmlKey, customEnv, i3dMappings)
and self:loadStations(components, xmlFile, xmlKey, customEnv, i3dMappings)
and self:loadControlStates(components, xmlFile, xmlKey, customEnv, i3dMappings)
then
self.activatable = SCStateControllerActivatable.new(self)
if self.activatable ~= nil then
addTrigger(self.triggerNode, "controlTriggerCallback", self)
for stateTypeIndex = 1, SCStateController.MAX_STATE_TYPES do
local _, numStates = self:getControlStateList(stateTypeIndex)
if numStates > 0 then
if not self:selectControlState(1, stateTypeIndex, true, true) then
return false
end
end
end
self.messageCenter:subscribe(THMain.MESSAGE_TYPE.STORAGE_EXTENSION_ADDED, self.onStorageAdded, self)
self.messageCenter:subscribe(THMain.MESSAGE_TYPE.STORAGE_EXTENSION_REMOVED, self.onStorageRemoved, self)
self.messageCenter:subscribe(SCStateController.MESSAGE_TYPE.STORAGE_UPDATED, self.onStorageUpdated, self)
self.isEnabled = true
else
THUtils.errorMsg(false, "Failed to create state controller activatable")
end
end
self.isLoadFinished = true
end
return self.isEnabled
end
function SCStateController:loadStorages(components, xmlFile, key, customEnv, i3dMappings)
local storageSystem = self.storageSystem
xmlFile:iterate(key..".storages.storage", function(_, pStorageKey)
local storageInfo = Storage.new(self.isServer, self.isClient)
local storageData = g_thMain:createDataTable(storageInfo, false, nil,nil, SCStorage_mt, self, customEnv)
if storageInfo:load(components, xmlFile, pStorageKey, i3dMappings) then
storageInfo:register(true)
if storageInfo.isExtension then
storageSystem:addStorage(storageInfo)
end
table.insert(self.storages.byIndex, storageInfo)
storageData.index = #self.storages.byIndex
self.storages.byId[storageData.id] = storageInfo
self.storages.byTarget[storageInfo] = storageInfo
end
end)
if #self.storages.byIndex == 0 then
THUtils.errorMsg(false, "No storages defined for state controller")
return false
end
return true
end
function SCStateController:loadStations(components, xmlFile, key, customEnv, i3dMappings)
local placeable = self:getParentPlaceable()
local storageSystem = self.storageSystem
local economyManager = g_currentMission.economyManager
xmlFile:iterate(key..".sellingStations.sellingStation", function(_, pStationKey)
local station = SellingStation.new(self.isServer, self.isClient)
local stationData = g_thMain:createDataTable(station, false, nil,nil, SCSellingStation_mt, self)
if station:load(components, xmlFile, pStationKey, customEnv, i3dMappings, components[1].node) then
station.skipSell = placeable:getOwnerFarmId() ~= AccessHandler.EVERYONE
station.storeSoldGoods = true
station.owningPlaceable = placeable
function station.getIsFillAllowedFromFarm(_, pFarmId)
return self.accessHandler:canFarmAccess(pFarmId, placeable)
end
local storageList, numStorages = stationData:getLinkedStorageList()
if numStorages > 0 then
for _, storage in pairs(storageList) do
station:addTargetStorage(storage)
end
end
station:register(true)
storageSystem:addUnloadingStation(station, placeable)
economyManager:addSellingStation(station)
table.insert(self.sellingStations, station)
self.sellingStationMapping[station] = #self.sellingStations
end
end)
xmlFile:iterate(key..".loadingStations.loadingStation", function(_, pStationKey)
local station = LoadingStation.new(placeable.isServer, placeable.isClient)
local stationData = g_thMain:createDataTable(station, false, nil,nil, SCLoadingStation_mt, self)
if station:load(components, xmlFile, pStationKey, customEnv, i3dMappings, components[1].node) then
function station.hasFarmAccessToStorage(_, pFarmId)
return pFarmId == placeable:getOwnerFarmId()
end
station.owningPlaceable = placeable
local storageList, numStorages = stationData:getLinkedStorageList()
if numStorages > 0 then
for _, storage in pairs(storageList) do
station:addSourceStorage(storage)
end
end
station:register(true)
storageSystem:addLoadingStation(station, placeable)
table.insert(self.loadingStations, station)
self.loadingStationMapping[station] = #self.loadingStations
end
end)
return true
end
function SCStateController:loadControlStates(components, xmlFile, key, customEnv, i3dMappings)
local placeable = self:getParentPlaceable()
self.allowExtendedStorage = false
local function loadStateType(pStateType)
local stateTypeInfo  = self:getStateType(pStateType)
local stateTypeName  = stateTypeInfo.name
local stateTypeIndex = stateTypeInfo.index
local statesTable    = stateTypeInfo.controlStates
local baseKey = key.."."..stateTypeName.."States"
local activateText = xmlFile:getValue(baseKey.."#activateText")
if activateText ~= nil and activateText ~= "" then
stateTypeInfo.activateText = self.i18n:convertText(activateText, customEnv)
end
xmlFile:iterate(baseKey..".state", function(pStateIdx, pStateKey)
local stateId    = xmlFile:getValue(pStateKey.."#id")
local stateTitle = xmlFile:getValue(pStateKey.."#title")
local storageIds = THUtils.getXMLValue(xmlFile, pStateKey, "#storageIds #storages")
local allowExtensions  = THUtils.getXMLValue(xmlFile, pStateKey, "#allowExtensions", false)
local extensionRange   = THUtils.getXMLValue(xmlFile, pStateKey, "#extensionRange", 50)
local extFillTypeNames = THUtils.getXMLValue(xmlFile, pStateKey, "#extensionFillTypes")
extensionRange = math.max(0, extensionRange)
if stateId == nil or stateId == "" then
THUtils.errorMsg(false, "Missing %s state id at index %d", stateTypeName, pStateIdx)
elseif self:getControlState(stateId, stateTypeIndex) ~= nil then
THUtils.errorMsg(false, "Duplicate %s state id (%s) at index %d", stateTypeName, stateId, pStateIdx)
else
local stateInfo = {
id       = stateId:upper(),
name     = stateId,
type     = stateTypeIndex,
index    = #statesTable.byIndex + 1,
isLoaded = false,
objectChanges  = {},
linkedStorages = {
byId     = {},
byIndex  = {},
byTarget = {}
},
storageFillTypes         = {},
storageFillTypesArray    = {},
allowExtendedStorage     = allowExtensions,
extendedStorageRange     = extensionRange,
extendedStorages         = {},
extendedStorageMapping   = {},
extendedStorageFillTypes = {}
}
if stateTitle == nil or stateTitle == "" then
stateInfo.title = stateInfo.name
else
stateInfo.title = self.i18n:convertText(stateTitle, customEnv)
end
if extFillTypeNames ~= nil and extFillTypeNames ~= "" then
local extFillTypeList = THUtils.splitString(extFillTypeNames, " ")
for _, extFillTypeName in pairs(extFillTypeList) do
local extFillTypeIndex = THUtils.getFillTypeIndex(extFillTypeName)
if extFillTypeIndex ~= nil and extFillTypeIndex ~= FillType.UNKNOWN then
stateInfo.extendedStorageFillTypes[extFillTypeIndex] = true
end
end
end
if storageIds ~= nil and storageIds ~= "" then
local storageIdList = THUtils.splitString(storageIds, " ")
if storageIdList ~= nil and #storageIdList > 0 then
for i = 1, #storageIdList do
local storageId = storageIdList[i]
local storageInfo, storageData = self:getStorage(storageId)
if storageData == nil then
THUtils.errorMsg(false, "Invalid storage id (%s) for %s state %q at index %d", storageId, stateTypeName, stateInfo.name, pStateIdx)
else
if not stateInfo.linkedStorages.byTarget[storageInfo] then
table.insert(stateInfo.linkedStorages.byIndex, storageInfo)
stateInfo.linkedStorages.byId[storageData.id] = storageInfo
stateInfo.linkedStorages.byTarget[storageInfo] = storageInfo
end
if not stateTypeInfo.storageMapping[storageInfo] then
table.insert(stateTypeInfo.storages, storageInfo)
stateTypeInfo.storageMapping[storageInfo] = #stateTypeInfo.storages
end
local fillTypeList = storageInfo:getSupportedFillTypes()
for fillType in pairs(fillTypeList) do
if not stateInfo.storageFillTypes[fillType] then
table.insert(stateInfo.storageFillTypesArray, fillType)
stateInfo.storageFillTypes[fillType] = true
end
if not stateTypeInfo.storageFillTypes[fillType] then
table.insert(stateTypeInfo.storageFillTypesArray, fillType)
stateTypeInfo.storageFillTypes[fillType] = true
end
if not self.storageFillTypes[fillType] then
table.insert(self.storageFillTypesArray, fillType)
self.storageFillTypes[fillType] = true
end
end
end
end
end
end
if #stateInfo.linkedStorages.byIndex == 0 then
THUtils.errorMsg(false, "No linked storages for %s state %q at index %d", stateTypeName, stateInfo.name, pStateIdx)
else
ObjectChangeUtil.loadObjectChangeFromXML(xmlFile, pStateKey..".objectChanges", stateInfo.objectChanges, components, placeable)
ObjectChangeUtil.setObjectChanges(stateInfo.objectChanges, false)
stateInfo.getLinkedStorage = function(pSelf, pTarget, pVerbose, pRaise)
local storageInfo = THUtils.getTargetInfo(pSelf, "linkedStorages", pTarget, pVerbose, pRaise)
local storageData = g_thMain:getDataTable(storageInfo)
return storageInfo, storageData
end
stateInfo.getLinkedStorageList = function(pSelf, pById)
local numStorages = #pSelf.linkedStorages.byIndex
if pById == true then
return pSelf.linkedStorages.byId, numStorages
else
return pSelf.linkedStorages.byIndex, numStorages
end
end
stateInfo.getStorageFillTypeList = function(pSelf, pById)
local numFillTypes = #pSelf.storageFillTypesArray
if pById == true then
return pSelf.storageFillTypes, numFillTypes
else
return pSelf.storageFillTypesArray, numFillTypes
end
end
THUtils.sortTable(stateInfo.storageFillTypesArray, "title", "getFillType")
if stateInfo.allowExtendedStorage then
self.allowExtendedStorage = true
end
statesTable.byId[stateInfo.id] = stateInfo
statesTable.byIndex[stateInfo.index] = stateInfo
statesTable.byTarget[stateInfo] = stateInfo
stateInfo.isLoaded = true
end
end
end)
if #statesTable.byIndex == 0 then
THUtils.errorMsg(false, "State controller must have at least one %s state to function properly", stateTypeName)
return false
end
THUtils.sortTable(stateTypeInfo.storageFillTypesArray, "title", "getFillType")
return true
end
if loadStateType("input") and loadStateType("output") then
THUtils.sortTable(self.storageFillTypesArray, "title", "getFillType")
return true
end
return false
end
function SCStateController:delete(...)
local placeable = self:getParentPlaceable()
if self.triggerNode ~= nil then
removeTrigger(self.triggerNode)
end
local activatableObjectsSystem = g_currentMission.activatableObjectsSystem
local storageSystem = self.storageSystem
local economyManager = g_currentMission.economyManager
local infoDisplay = g_currentMission.hud.infoDisplay
if self.activatable ~= nil then
activatableObjectsSystem:removeActivatable(self.activatable)
self.activatable = nil
end
for _, loadingStation in pairs(self.loadingStations) do
storageSystem:removeLoadingStation(loadingStation, placeable)
if loadingStation:getIsFillTypeSupported(FillType.LIQUIDMANURE)
or loadingStation:getIsFillTypeSupported(FillType.DIGESTATE)
then
g_currentMission:removeLiquidManureLoadingStation(loadingStation)
end
loadingStation:delete()
end
for _, sellingStation in pairs(self.sellingStations) do
storageSystem:removeUnloadingStation(sellingStation, placeable)
economyManager:removeSellingStation(sellingStation)
sellingStation:delete()
end
local storageArray, numStorages = self:getStorageList()
if numStorages > 0 then
for _, storageInfo in pairs(storageArray) do
if storageInfo.isExtension then
storageSystem:removeStorage(storageInfo)
end
storageInfo:delete()
end
end
if self.hudBox ~= nil then
infoDisplay:destroyBox(self.hudBox)
end
self.messageCenter:unsubscribeAll(self)
self.isEnabled = false
end
function SCStateController:updateTick(dt, ...)
local function protectedFunc(...)
if self:getIsEnabled() then
if self.isStorageDirty then
self:updateStorage()
self.isStorageDirty = false
end
if self.areVisualsDirty then
self:updateVisuals()
self.areVisualsDirty = false
end
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCStateController:readStream(streamId, connection)
if connection:getIsServer() then
if streamReadBool(streamId) then
local numStorages = streamReadUIntN(streamId, SCStateController.NUM_STORAGE_BITS)
local numSellingStations = streamReadUIntN(streamId, SCStateController.NUM_STATION_BITS)
local numLoadingStations = streamReadUIntN(streamId, SCStateController.NUM_STATION_BITS)
if numStorages > 0 then
for storageIdx = 1, numStorages do
local storageInfo = self:getStorage(storageIdx)
local storageObjectId = NetworkUtil.readNodeObjectId(streamId)
storageInfo:readStream(streamId, connection)
g_client:finishRegisterObject(storageInfo, storageObjectId)
end
end
if numSellingStations > 0 then
for stationIdx = 1, numSellingStations do
local stationInfo = self:getSellingStation(stationIdx)
local stationObjectId = NetworkUtil.readNodeObjectId(streamId)
stationInfo:readStream(streamId, connection)
g_client:finishRegisterObject(stationInfo, stationObjectId)
end
end
if numLoadingStations > 0 then
for stationIdx = 1, numLoadingStations do
local stationInfo = self:getLoadingStation(stationIdx)
local stationObjectId = NetworkUtil.readNodeObjectId(streamId)
stationInfo:readStream(streamId, connection)
g_client:finishRegisterObject(stationInfo, stationObjectId)
end
end
for stateType = 1, SCStateController.MAX_STATE_TYPES do
local stateIndex = streamReadUIntN(streamId, SCStateController.NUM_STATE_BITS)
self:selectControlState(stateIndex, stateType, true, true)
end
else
self.isEnabled = false
end
end
end
function SCStateController:writeStream(streamId, connection)
if not connection:getIsServer() then
local isEnabled = self:getIsEnabled()
if streamWriteBool(streamId, isEnabled) then
local _, numStorages = self:getStorageList()
local numSellingStations = #self.sellingStations
local numLoadingStations = #self.loadingStations
streamWriteUIntN(streamId, numStorages, SCStateController.NUM_STORAGE_BITS)
streamWriteUIntN(streamId, numSellingStations, SCStateController.NUM_STATION_BITS)
streamWriteUIntN(streamId, numLoadingStations, SCStateController.NUM_STATION_BITS)
if numStorages > 0 then
for storageIdx = 1, numStorages do
local storageInfo = self:getStorage(storageIdx)
NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(storageInfo))
storageInfo:writeStream(streamId, connection)
g_server:registerObjectInStream(connection, storageInfo)
end
end
if numSellingStations > 0 then
for stationIdx = 1, numSellingStations do
local stationInfo = self:getSellingStation(stationIdx)
NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(stationInfo))
stationInfo:writeStream(streamId, connection)
g_server:registerObjectInStream(connection, stationInfo)
end
end
if numLoadingStations > 0 then
for stationIdx = 1, numLoadingStations do
local stationInfo = self:getLoadingStation(stationIdx)
NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(stationInfo))
stationInfo:writeStream(streamId, connection)
g_server:registerObjectInStream(connection, stationInfo)
end
end
for stateTypeIndex = 1, SCStateController.MAX_STATE_TYPES do
local stateTypeInfo = self:getStateType(stateTypeIndex)
streamWriteUIntN(streamId, stateTypeInfo.currentControlState, SCStateController.NUM_STATE_BITS)
end
end
end
end
function SCStateController:loadFromXMLFile(xmlFile, key)
local function protectedFunc()
if self:getIsEnabled() then
local xmlDataKey = g_thMain.xmlDataKey
xmlFile:iterate(key..".storages.storage", function (_, pStorageKey)
local storageDataKey = pStorageKey.."."..xmlDataKey
local storageId = xmlFile:getValue(storageDataKey.."#id")
local storage, storageData = self:getStorage(storageId)
if storageData ~= nil then
storage:loadFromXMLFile(xmlFile, pStorageKey)
end
end)
for stateTypeIndex = 1, SCStateController.MAX_STATE_TYPES do
local stateTypeInfo = self:getStateType(stateTypeIndex)
local stateIndex = xmlFile:getValue(key.."#"..stateTypeInfo.name.."State", 0)
if THUtils.getNoNil(stateIndex, 0) > 0 then
self:selectControlState(stateIndex, stateTypeIndex, true, true)
end
end
end
return true
end
return g_thMain:call(protectedFunc)
end
function SCStateController:saveToXMLFile(xmlFile, key, useModNames)
local function protectedFunc()
if self:getIsEnabled() then
local xmlDataKey = g_thMain.xmlDataKey
local _, numStorages = self:getStorageList()
if numStorages > 0 then
for i = 1, numStorages do
local storageKey = string.format("%s.storages.storage(%d)", key, i-1)
local storage, storageData = self:getStorage(i)
if storageData ~= nil then
local storageDataKey = storageKey.."."..xmlDataKey
xmlFile:setValue(storageDataKey.."#id", storageData.id)
storage:saveToXMLFile(xmlFile, storageKey, useModNames)
end
end
end
for stateTypeIndex = 1, SCStateController.MAX_STATE_TYPES do
local stateTypeInfo = self:getStateType(stateTypeIndex)
local stateIndex = stateTypeInfo.currentControlState
if stateIndex > 0 then
xmlFile:setValue(key.."#"..stateTypeInfo.name.."State", stateIndex)
end
end
end
return true
end
return g_thMain:call(protectedFunc)
end
function SCStateController:setOwnerFarmId(farmId, noEventSend, ...)
local function protectedFunc(...)
SCStateController:superClass().setOwnerFarmId(self, farmId, noEventSend, ...)
for _, station in pairs(self.sellingStations) do
station.skipSell = farmId ~= AccessHandler.EVERYONE
station:setOwnerFarmId(farmId)
end
for _, station in pairs(self.loadingStations) do
station:setOwnerFarmId(farmId)
end
local storageArray, numStorages = self:getStorageList()
if numStorages > 0 then
for _, storage in pairs(storageArray) do
storage:setOwnerFarmId(farmId)
end
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCStateController:getOwnerFarmId(...)
local function appendFunc(farmId, ...)
farmId = THUtils.getNoNil(farmId, AccessHandler.EVERYONE)
return farmId, ...
end
return appendFunc(SCStateController:superClass().getOwnerFarmId(self, ...))
end
function SCStateController:onStorageAdded(...)
local function protectedFunc(...)
if self:getIsEnabled() then
self:updateExtendedStorage()
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCStateController:onStorageRemoved(...)
local function protectedFunc(...)
if self:getIsEnabled() then
self:updateExtendedStorage()
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCStateController:onStorageUpdated(controller, ...)
local function protectedFunc(...)
if self:getIsEnabled() then
self:updateExtendedStorage()
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCStateController:controlTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
local function protectedFunc()
if self:getIsEnabled() then
local ownerFarmId = self:getOwnerFarmId()
local player = g_currentMission.player
if player ~= nil and otherId == player.rootNode and (onEnter or onLeave) then
if onEnter then
local accessHandler = self.accessHandler
local playerFarmId = g_currentMission:getFarmId()
if ownerFarmId == AccessHandler.EVERYONE or accessHandler:canFarmAccessOtherId(playerFarmId, ownerFarmId) then
g_currentMission.activatableObjectsSystem:addActivatable(self.activatable)
self.isInTrigger = true
end
elseif onLeave then
g_currentMission.activatableObjectsSystem:removeActivatable(self.activatable)
self.isInTrigger = false
end
end
end
end
return g_thMain:call(protectedFunc)
end
function SCStateController:getIsEnabled()
return self.isEnabled
end
function SCStateController:setIsDirty(updateStorage, updateVisuals)
local success = false
if updateStorage == nil or updateStorage == true then
self.isStorageDirty = true
success = true
end
if updateVisuals == nil or updateVisuals == true then
self.areVisualsDirty = true
success = true
end
if success then
self:raiseActive()
end
end
function SCStateController:getParentPlaceable()
return self.parentPlaceable
end
function SCStateController:getSellingStation(station)
local targetType = type(station)
local stationInfo = nil
if targetType == "table" then
local stationIndex = self.sellingStationMapping[station]
if stationIndex ~= nil then
if self.sellingStations[stationIndex] == station then
stationInfo = station
else
THUtils.errorMsg(true, "Selling station internal index mismatch")
end
end
elseif targetType == "number" then
stationInfo = self.sellingStations[station]
else
THUtils.errorMsg(true, THUtils.MSG.ARGUMENT_INVALID, "station", station)
return
end
local stationData = g_thMain:getDataTable(stationInfo)
return stationInfo, stationData
end
function SCStateController:getLoadingStation(station)
local targetType = type(station)
local stationInfo = nil
if targetType == "table" then
local stationIndex = self.loadingStationMapping[station]
if stationIndex ~= nil then
if self.loadingStations[stationIndex] == station then
stationInfo = station
else
THUtils.errorMsg(true, "Loading station internal index mismatch")
end
end
elseif targetType == "number" then
stationInfo = self.loadingStations[station]
else
THUtils.errorMsg(true, THUtils.MSG.ARGUMENT_INVALID, "station", station)
return
end
local stationData = g_thMain:getDataTable(stationInfo)
return stationInfo, stationData
end
function SCStateController:getStorage(storage, stateType)
local storageInfo = THUtils.getTargetInfo(self, "storages", storage, false, true)
local storageData = g_thMain:getDataTable(storageInfo)
if stateType ~= nil and storageInfo ~= nil then
local stateTypeInfo = self:getStateType(stateType)
if stateTypeInfo == nil then
return
else
local storageIndex = stateTypeInfo.storageMapping[storageInfo]
if storageIndex == nil or stateTypeInfo.storages[storageIndex] ~= storageInfo then
if storageIndex ~= nil then
THUtils.errorMsg(true, "Storage internal index mismatch")
end
return
end
end
end
return storageInfo, storageData
end
function SCStateController:getStorageList(stateType, byId)
if stateType == nil then
local numStorages = #self.storages.byIndex
if byId == true then
return self.storages.byId, numStorages
else
return self.storages.byIndex, numStorages
end
else
local stateTypeInfo = self:getStateType(stateType)
if stateTypeInfo ~= nil then
local numStorages = #stateTypeInfo.storages
if byId == true then
return stateTypeInfo.storageMapping, numStorages
else
return stateTypeInfo.storages, numStorages
end
end
end
return {}, 0
end
function SCStateController:getIsStorageActive(storage, stateType)
if self:getIsEnabled() then
local storageInfo = self:getStorage(storage)
if storageInfo ~= nil then
if stateType == nil then
if self.activeStorages[storageInfo] then
return true
end
else
local stateInfo = self:getCurrentControlState(stateType)
if stateInfo ~= nil then
return stateInfo:getLinkedStorage(storageInfo) ~= nil
end
end
end
end
return false
end
function SCStateController:getActiveStorageList(stateType, byId)
if self:getIsEnabled() then
if stateType == nil then
local numStorages = #self.activeStoragesArray
if byId == true then
return self.activeStorages, numStorages
else
return self.activeStoragesArray, numStorages
end
else
local stateInfo = self:getCurrentControlState(stateType)
if stateInfo ~= nil then
return stateInfo:getLinkedStorageList(byId)
end
end
end
return {}, 0
end
function SCStateController:getExtendedStorage(storage, stateType)
local storageType = type(storage)
if stateType == nil then
if storageType == "number" then
return self.extendedStorages[storage]
elseif storageType == "table" and self.extendedStorageMapping[storage] ~= nil then
return storage
end
else
local stateInfo = self:getCurrentControlState(stateType)
if stateInfo ~= nil then
if storageType == "number" then
return stateInfo.extendedStorages[storage]
elseif storageType == "table" and stateInfo.extendedStorageMapping[storage] ~= nil then
return storage
end
end
end
end
function SCStateController:getIsExtendedStorage(storage, stateType)
if self:getIsEnabled() then
if self:getExtendedStorage(storage, stateType) ~= nil then
return true
end
end
return false
end
function SCStateController:getExtendedStorageList(stateType, byId)
if stateType == nil then
local numStorages = #self.extendedStorages
if byId == true then
return self.extendedStorageMapping, numStorages
else
return self.extendedStorages, numStorages
end
else
local stateInfo = self:getCurrentControlState(stateType)
if stateInfo ~= nil then
local numStorages = #stateInfo.extendedStorages
if byId == true then
return stateInfo.extendedStorageMapping, numStorages
else
return stateInfo.extendedStorages, numStorages
end
end
end
return {}, 0
end
function SCStateController:getIsExtensionFillType(fillType, stateType)
if self:getIsFillTypeActive(fillType, stateType) then
fillType = THUtils.getFillTypeIndex(fillType, true, true)
if self.allowExtendedStorage then
if stateType == nil then
return true
else
local stateInfo = self:getCurrentControlState(stateType)
if stateInfo ~= nil and stateInfo.allowExtendedStorage then
if next(stateInfo.extendedStorageFillTypes) == nil
or stateInfo.extendedStorageFillTypes[fillType]
then
return true
end
end
end
end
end
return false
end
function SCStateController:getIsFillTypeActive(fillType, stateType)
if self:getIsEnabled() and fillType ~= nil then
fillType = THUtils.getFillTypeIndex(fillType, true, true)
if stateType == nil then
if self.activeFillTypes[fillType] then
return true
end
else
local stateInfo = self:getCurrentControlState(stateType)
if stateInfo ~= nil then
if stateInfo.storageFillTypes[fillType] then
return true
end
end
end
end
return false
end
function SCStateController:getIsMultiStateFillType(fillType)
if fillType == nil then
return false
end
fillType = THUtils.getFillTypeIndex(fillType, true, true)
local isFound = false
for stateTypeIdx = 1, SCStateController.MAX_STATE_TYPES do
if self:getIsFillTypeActive(fillType, stateTypeIdx) then
if isFound then
return true
end
isFound = true
end
end
return false
end
function SCStateController:getActiveFillTypeList(stateType, byId)
if self:getIsEnabled() then
if stateType == nil then
local numFillTypes = #self.activeFillTypesArray
if byId == true then
return self.activeFillTypes, numFillTypes
else
return self.activeFillTypesArray, numFillTypes
end
else
local stateInfo = self:getCurrentControlState(stateType)
if stateInfo ~= nil then
return stateInfo:getStorageFillTypeList(byId)
end
end
end
return {}, 0
end
function SCStateController:getFillTypeStateType(fillType)
if fillType == nil then
return
else
fillType = THUtils.getFillTypeIndex(fillType, true, true)
for stateTypeIdx = 1, SCStateController.MAX_STATE_TYPES do
if self:getIsFillTypeActive(fillType, stateTypeIdx) then
return stateTypeIdx
end
end
end
end
function SCStateController:getCanAccessStorage(storage, farmId, fillType, stateType)
if self:getIsEnabled() then
local storageData   = g_thMain:getDataTable(storage)
local accessHandler = self.accessHandler
local ownerFarmId   = self:getOwnerFarmId()
farmId = THUtils.getNoNil(farmId, ownerFarmId)
if storageData ~= nil then
if storageData.isRouterStorage then
return false
end
end
if accessHandler:canFarmAccess(farmId, storage, true) then
if self:getIsExtendedStorage(storage, stateType)
or self:getIsStorageActive(storage, stateType)
then
if fillType ~= nil then
if not storage:getIsFillTypeSupported(fillType)
or not self:getIsFillTypeActive(fillType, stateType)
then
return false
end
end
return true
end
end
end
return false
end
function SCStateController:addFillLevel(stateType, delta, fillType, noExtensions, ...)
delta = THUtils.getNoNil(delta, 0)
local totalRemaining = delta
local totalApplied   = 0
local stateTypeIndex = nil
if stateType == nil then
stateTypeIndex = self:getCurrentStateType(fillType)
if stateTypeIndex == nil then
stateTypeIndex = self:getFillTypeStateType(fillType)
end
elseif stateType ~= SCStateController.STATE_TYPE.NONE then
stateTypeIndex = self:getStateType(stateType, true)
end
if stateTypeIndex ~= nil or stateType == SCStateController.STATE_TYPE.NONE then
local storageCache = THUtils.clearTable(self.storageCache)
local function processStorage(pStorageInfo, ...)
if storageCache[pStorageInfo] == nil then
if self:getCanAccessStorage(pStorageInfo, nil, fillType, stateTypeIndex) then
local storageFillLevel = pStorageInfo:getFillLevel(fillType)
pStorageInfo:setFillLevel(storageFillLevel + totalRemaining, fillType, ...)
local newStorageFillLevel = pStorageInfo:getFillLevel(fillType)
local amountChanged = newStorageFillLevel - storageFillLevel
if amountChanged ~= 0 then
totalApplied   = totalApplied + amountChanged
totalRemaining = totalRemaining - amountChanged
if pStorageInfo.isServer then
pStorageInfo:raiseDirtyFlags(pStorageInfo.storageDirtyFlag)
end
end
storageCache[pStorageInfo] = amountChanged
end
end
end
local storageArray, numStorages = self:getActiveStorageList(stateTypeIndex)
if numStorages > 0 and totalRemaining ~= 0 then
for storageIdx = 1, numStorages do
local storageInfo = storageArray[storageIdx]
processStorage(storageInfo, ...)
end
end
if math.abs(totalRemaining) > SCStorage.MIN_STORAGE_VALUE then
if noExtensions ~= true then
if self:getIsExtensionFillType(fillType, stateTypeIndex) then
local extStorageArray, numExtStorages = self:getExtendedStorageList(stateTypeIndex)
if numExtStorages > 0 then
for extStorageIdx = 1, numExtStorages do
local extStorageInfo = extStorageArray[extStorageIdx]
processStorage(extStorageInfo, ...)
end
end
end
end
end
end
return totalApplied, totalRemaining
end
function SCStateController:getStorageValue(valueType, stateType, fillType, noExtensions, ...)
local funcName = "get"..THUtils.properCase(valueType)
local totalValue = 0
local stateTypeIndex = nil
if stateType == nil then
stateTypeIndex = self:getCurrentStateType(fillType)
if stateTypeIndex == nil then
stateTypeIndex = self:getFillTypeStateType(fillType)
end
elseif stateType ~= SCStateController.STATE_TYPE.NONE then
stateTypeIndex = self:getStateType(stateType, true)
end
if stateTypeIndex ~= nil or stateType == SCStateController.STATE_TYPE.NONE then
local storageCache = THUtils.clearTable(self.storageCache)
local function processStorage(pStorageInfo, ...)
if storageCache[pStorageInfo] == nil then
if self:getCanAccessStorage(pStorageInfo, nil, fillType, stateTypeIndex) then
local value = pStorageInfo[funcName](pStorageInfo, fillType, ...)
if value ~= nil and value > 0 then
totalValue = totalValue + value
end
storageCache[pStorageInfo] = value
end
end
end
local storageArray, numStorages = self:getActiveStorageList(stateTypeIndex)
if numStorages > 0 then
for storageIdx = 1, numStorages do
local storageInfo = storageArray[storageIdx]
processStorage(storageInfo, ...)
end
end
if noExtensions ~= true then
if fillType == nil or self:getIsExtensionFillType(fillType, stateTypeIndex) then
local extStorageArray, numExtStorages = self:getExtendedStorageList(stateTypeIndex)
if numExtStorages > 0 then
for extStorageIdx = 1, numExtStorages do
local extStorageInfo = extStorageArray[extStorageIdx]
processStorage(extStorageInfo, ...)
end
end
end
end
end
return totalValue
end
function SCStateController:emptyStorage(stateType, storage)
local storageArray, numStorages = self:getActiveStorageList(stateType)
local extStorageArray, numExtStorages = self:getExtendedStorageList(stateType)
local otherStorageInfo = nil
if storage ~= nil then
otherStorageInfo = self:getStorage(storage)
if otherStorageInfo == nil then
otherStorageInfo = self:getExtendedStorage(storage)
if otherStorageInfo == nil then
return
end
end
end
if numStorages > 0 then
for storageIdx = 1, numStorages do
local storageInfo = storageArray[storageIdx]
if otherStorageInfo == nil or storageInfo == otherStorageInfo then
storageInfo:empty()
if otherStorageInfo ~= nil then
break
end
end
end
end
if numExtStorages > 0 then
for extStorageIdx = 1, numExtStorages do
local extStorageInfo = extStorageArray[extStorageIdx]
if otherStorageInfo == nil or extStorageInfo == otherStorageInfo then
extStorageInfo:empty()
if otherStorageInfo ~= nil then
break
end
end
end
end
end
function SCStateController:getStateType(stateType, indexOnly)
local stateTypeInfo = THUtils.getTargetInfo(self, "stateTypes", stateType, true, true)
if stateTypeInfo ~= nil then
if indexOnly == true then
return stateTypeInfo.index
else
return stateTypeInfo
end
end
end
function SCStateController:getCurrentStateType(fillType, indexOnly)
if fillType ~= nil then
fillType = THUtils.getFillTypeIndex(fillType, true, true)
if fillType == nil then
return
end
else
fillType = FillType.UNKNOWN
end
local stateTypeIndex = self.currentStateType[fillType]
if stateTypeIndex == nil and fillType ~= FillType.UNKNOWN then
stateTypeIndex = self.currentStateType[FillType.UNKNOWN]
end
if stateTypeIndex ~= nil then
return self:getStateType(stateTypeIndex, indexOnly)
end
end
function SCStateController:setCurrentStateType(stateType, fillType)
if stateType ~= nil then
stateType = self:getStateType(stateType, true)
if stateType == nil then
return false
end
end
if fillType ~= nil then
fillType = THUtils.getFillTypeIndex(fillType, true, true)
if fillType == nil then
return false
end
else
fillType = FillType.UNKNOWN
end
if fillType == FillType.UNKNOWN then
THUtils.clearTable(self.currentStateType)
end
self.currentStateType[fillType] = stateType
return true
end
function SCStateController:getControlState(state, stateType)
local stateTypeInfo = self:getStateType(stateType)
if state == 0 then return end
return THUtils.getTargetInfo(stateTypeInfo, "controlStates", state, false, true)
end
function SCStateController:getCurrentControlState(stateType)
local stateTypeInfo = self:getStateType(stateType)
local stateIndex = stateTypeInfo.currentControlState
if stateIndex > 0 then
local stateInfo = stateTypeInfo.controlStates.byIndex[stateIndex]
if stateInfo == nil then
THUtils.errorMsg(true, "Invalid current %s state", stateTypeInfo.name)
end
return stateInfo
end
end
function SCStateController:getControlStateList(stateType, byId)
local stateTypeInfo = self:getStateType(stateType)
local statesTable = stateTypeInfo.controlStates
local numControlStates = #statesTable.byIndex
if byId == true then
return statesTable.byId, numControlStates
else
return statesTable.byIndex, numControlStates
end
end
function SCStateController:selectControlState(state, stateType, updateVis, noEventSend)
local stateTypeInfo = self:getStateType(stateType)
local oldStateIndex = stateTypeInfo.currentControlState
local newStateIndex = nil
updateVis = THUtils.getNoNil(updateVis, true)
if state == nil then
if self.isServer then
local _, numStates = self:getControlStateList(stateType)
if numStates > 0 then
newStateIndex = oldStateIndex + 1
if newStateIndex > numStates or newStateIndex < 1 then
newStateIndex = 1
end
else
newStateIndex = 0
end
elseif self.isClient and noEventSend ~= true then
SCSelectControlStateEvent.sendEvent(self, stateType, updateVis)
return true
end
elseif self.isServer or noEventSend == true then
if state == 0 then
newStateIndex = 0
else
local stateInfo = self:getControlState(state, stateType)
if stateInfo == nil then
newStateIndex = 0
else
newStateIndex = stateInfo.index
end
end
else
THUtils.errorMsg(true, THUtils.MSG.ARGUMENT_INVALID, "noEventSend", noEventSend)
return false
end
if newStateIndex ~= nil then
stateTypeInfo.currentControlState = newStateIndex
self:setIsDirty(true, updateVis)
if self.isServer and noEventSend ~= true then
SCSelectControlStateEvent.sendEvent(self, stateType, updateVis)
end
end
return true
end
function SCStateController:updateHudInfo(hudInfo)
local inputStateInfo = self:getCurrentControlState(SCStateController.STATE_TYPE.INPUT)
local outputStateInfo = self:getCurrentControlState(SCStateController.STATE_TYPE.OUTPUT)
local i18n = self.i18n
if inputStateInfo ~= nil then
table.insert(hudInfo, {
title = i18n:getText("scUI_currentInputState"),
text  = inputStateInfo.title,
accentuate = false
})
end
if outputStateInfo ~= nil then
table.insert(hudInfo, {
title = i18n:getText("scUI_currentOutputState"),
text  = outputStateInfo.title,
accentuate = false
})
end
table.insert(hudInfo, {
title = i18n:getText("scUI_linkedStorage")..":",
text = "",
accentuate = true
})
local function addStorageInfo(pStorageInfo)
local storageData = g_thMain:getDataTable(pStorageInfo)
if storageData ~= nil then
local storageTitle = storageData.title
local storageText = ""
local isStorageActive = true
local storageTitleColor = nil
local isInputStorage = self:getIsStorageActive(pStorageInfo, SCStateController.STATE_TYPE.INPUT)
local isOutputStorage = self:getIsStorageActive(pStorageInfo, SCStateController.STATE_TYPE.OUTPUT)
if isInputStorage then
if isOutputStorage then
storageText = i18n:getText("scUI_inputOutput")
else
storageText = i18n:getText("scUI_input")
end
elseif isOutputStorage then
storageText = i18n:getText("scUI_output")
else
isStorageActive = false
end
if isStorageActive then
storageTitleColor = THMain.COLOR.UI_ALTERNATE
else
storageTitleColor = THMain.COLOR.UI_DISABLED
end
local fillTypeList = pStorageInfo:getSupportedFillTypes()
local isStorageEmpty = true
local isStorageVisible = false
for fillType in pairs(fillTypeList) do
local fillLevel = pStorageInfo:getFillLevel(fillType)
local capacity = pStorageInfo:getCapacity(fillType)
local extStorageArray, numExtStorages = nil, 0
local extFillLevel, extCapacity = 0, 0
if self.allowExtendedStorage then
local isExtInputFillType = isInputStorage and self:getIsExtensionFillType(fillType, inputStateInfo.type)
local isExtOutputFillType = isOutputStorage and self:getIsExtensionFillType(fillType, outputStateInfo.type)
if isExtInputFillType then
if isExtOutputFillType then
extStorageArray, numExtStorages = self:getExtendedStorageList()
else
extStorageArray, numExtStorages = self:getExtendedStorageList(inputStateInfo.type)
end
elseif isExtOutputFillType then
extStorageArray, numExtStorages = self:getExtendedStorageList(outputStateInfo.type)
end
end
if extStorageArray ~= nil and numExtStorages > 0 then
for extStorageIdx = 1, numExtStorages do
local extStorageInfo = extStorageArray[extStorageIdx]
local extStorageFillLevel = extStorageInfo:getFillLevel(fillType)
local extStorageCapacity  = extStorageInfo:getCapacity(fillType)
if extStorageFillLevel > 0 and extStorageCapacity > 0 then
extFillLevel = extFillLevel + extStorageFillLevel
extCapacity = extCapacity + extStorageCapacity
end
end
end
if capacity > 0 or (isStorageActive and extCapacity > 0) then
if not isStorageVisible then
table.insert(hudInfo, {
title = storageTitle,
text  = storageText,
accentuate = true,
accentuateColor = storageTitleColor
})
isStorageVisible = true
end
end
if isStorageVisible and (fillLevel > 0 or (isStorageActive and extFillLevel > 0)) then
local fillTypeInfo = THUtils.getFillType(fillType)
if fillTypeInfo ~= nil then
local fillTypeTitle = THUtils.getNoNil(fillTypeInfo.title, "")
if fillTypeTitle == "" then
fillTypeTitle = "??"
end
if fillLevel > 0 then
local fillLevelText = i18n:formatVolume(fillLevel, nil,nil, true, nil, fillTypeInfo.index)
table.insert(hudInfo, {
title = " - "..fillTypeTitle,
text  = fillLevelText,
accentuate = not isStorageActive,
accentuateColor = THMain.COLOR.UI_DISABLED
})
end
if isStorageActive and extFillLevel > 0 then
local extFillLevelText = i18n:formatVolume(extFillLevel, nil,nil, true, nil, fillTypeInfo.index)
table.insert(hudInfo, {
title = " - "..fillTypeTitle,
text = extFillLevelText,
accentuate = true,
accentuateColor = THMain.COLOR.UI_GREEN
})
end
isStorageEmpty = false
end
end
end
if isStorageVisible then
if isStorageEmpty then
local fillLevelText = i18n:getText("scUI_empty")
table.insert(hudInfo, {
title = " - "..fillLevelText,
text = "",
accentuate = not isStorageActive,
accentuateColor = THMain.COLOR.UI_DISABLED
})
end
end
end
end
local storageList, numStorages = self:getStorageList()
if numStorages > 0 then
for i = 1, numStorages do
addStorageInfo(storageList[i])
end
end
end
function SCStateController:updateVisuals()
if self.isClient then
for stateTypeIndex = 1, SCStateController.MAX_STATE_TYPES do
local controlStateList, numControlStates = self:getControlStateList(stateTypeIndex)
if numControlStates > 0 then
local currentStateInfo = self:getCurrentControlState(stateTypeIndex)
for stateIndex = 1, numControlStates do
if currentStateInfo == nil or stateIndex ~= currentStateInfo.index then
local stateInfo = controlStateList[stateIndex]
ObjectChangeUtil.setObjectChanges(stateInfo.objectChanges, false)
end
end
if currentStateInfo ~= nil then
ObjectChangeUtil.setObjectChanges(currentStateInfo.objectChanges, true)
end
end
end
end
end
function SCStateController:updateStorage()
local storageSystem = self.storageSystem
THUtils.clearTable(self.activeStorages)
THUtils.clearTable(self.activeStoragesArray)
THUtils.clearTable(self.activeFillTypes)
THUtils.clearTable(self.activeFillTypesArray)
for stateTypeIdx = 1, SCStateController.MAX_STATE_TYPES do
local stateInfo = self:getCurrentControlState(stateTypeIdx)
if stateInfo ~= nil then
local storageList, numStorages = stateInfo:getLinkedStorageList()
local fillTypeList, numFillTypes = stateInfo:getStorageFillTypeList()
if numStorages > 0 then
for storageIdx = 1, numStorages do
local storageInfo = storageList[storageIdx]
if not self.activeStorages[storageInfo] then
table.insert(self.activeStoragesArray, storageInfo)
self.activeStorages[storageInfo] = true
end
end
end
if numFillTypes > 0 then
for fillTypeIdx = 1, numFillTypes do
local fillType = fillTypeList[fillTypeIdx]
if not self.activeFillTypes[fillType] then
table.insert(self.activeFillTypesArray, fillType)
self.activeFillTypes[fillType] = true
end
end
end
end
end
local numSellingStations = #self.sellingStations
if numSellingStations > 0 then
for stationIdx = 1, numSellingStations do
local stationInfo, stationData = self:getSellingStation(stationIdx)
local storageArray, numStorages = stationData:getLinkedStorageList()
if stationData ~= nil and stationData.syncStorage then
if numStorages > 0 then
for storageIdx = 1, numStorages do
local storageInfo = storageArray[storageIdx]
if self:getIsStorageActive(storageInfo, SCStateController.STATE_TYPE.INPUT) then
if not stationInfo.targetStorages[storageInfo] then
storageSystem:addStorageToUnloadingStation(storageInfo, stationInfo)
end
else
if stationInfo.targetStorages[storageInfo] then
storageSystem:removeStorageFromUnloadingStations(storageInfo, {stationInfo})
end
end
end
end
local activeFillTypeList, numActiveFillTypes = self:getActiveFillTypeList(SCStateController.STATE_TYPE.INPUT, true)
if stationInfo.unloadTriggers ~= nil then
for _, triggerInfo in pairs(stationInfo.unloadTriggers) do
local triggerData = g_thMain:getDataTable(triggerInfo)
if triggerData ~= nil then
THUtils.clearTable(triggerInfo.fillTypes)
if numActiveFillTypes > 0 then
for fillType in pairs(activeFillTypeList) do
if triggerData.allowedFillTypes[fillType] then
triggerInfo.fillTypes[fillType] = true
end
end
end
end
end
end
stationInfo:updateSupportedFillTypes()
end
end
end
local numLoadingStations = #self.loadingStations
if numLoadingStations > 0 then
for stationIdx = 1, numLoadingStations do
local stationInfo, stationData = self:getLoadingStation(stationIdx)
local storageArray, numStorages = stationData:getLinkedStorageList()
if stationData ~= nil and stationData.syncStorage then
if numStorages > 0 then
for storageIdx = 1, numStorages do
local storageInfo = storageArray[storageIdx]
if self:getIsStorageActive(storageInfo, SCStateController.STATE_TYPE.OUTPUT) then
if not stationInfo.sourceStorages[storageInfo] then
storageSystem:addStorageToLoadingStation(storageInfo, stationInfo)
end
else
if stationInfo.sourceStorages[storageInfo] then
storageSystem:removeStorageFromLoadingStations(storageInfo, {stationInfo})
end
end
end
end
local activeFillTypeList, numActiveFillTypes = self:getActiveFillTypeList(SCStateController.STATE_TYPE.OUTPUT, true)
if stationInfo.basicFillTypes ~= nil then
THUtils.clearTable(stationInfo.basicFillTypes)
if numActiveFillTypes > 0 then
for fillType in pairs(activeFillTypeList) do
if stationData.allowedFillTypes[fillType] then
stationInfo.basicFillTypes[fillType] = true
end
end
end
end
if stationInfo.loadTriggers ~= nil then
for _, triggerInfo in pairs(stationInfo.loadTriggers) do
local triggerData = g_thMain:getDataTable(triggerInfo)
if triggerData ~= nil then
THUtils.clearTable(triggerInfo.fillTypes)
if numActiveFillTypes > 0 then
for fillType in pairs(activeFillTypeList) do
if triggerData.allowedFillTypes[fillType] then
triggerInfo.fillTypes[fillType] = true
end
end
end
end
end
end
stationInfo:updateSupportedFillTypes()
local isLiquidManureStation = false
for _, otherStationInfo in pairs(g_currentMission.liquidManureLoadingStations) do
if otherStationInfo == stationInfo then
isLiquidManureStation = true
break
end
end
if stationInfo:getIsFillTypeSupported(FillType.LIQUIDMANURE)
or stationInfo:getIsFillTypeSupported(FillType.DIGESTATE)
then
if not isLiquidManureStation then
g_currentMission:addLiquidManureLoadingStation(stationInfo)
end
else
if isLiquidManureStation then
g_currentMission:removeLiquidManureLoadingStation(stationInfo)
end
end
end
end
end
self.messageCenter:publish(SCStateController.MESSAGE_TYPE.STORAGE_UPDATED, self)
end
function SCStateController:updateExtendedStorage()
local storageSystem = self.storageSystem
local accessHandler = self.accessHandler
local ownerFarmId   = self:getOwnerFarmId()
THUtils.clearTable(self.extendedStorages)
THUtils.clearTable(self.extendedStorageMapping)
local sx,sy,sz = getWorldTranslation(self.rootNode)
for stateTypeIdx = 1, SCStateController.MAX_STATE_TYPES do
local stateInfo = self:getCurrentControlState(stateTypeIdx)
if stateInfo ~= nil then
THUtils.clearTable(stateInfo.extendedStorages)
THUtils.clearTable(stateInfo.extendedStorageMapping)
end
end
if self.allowExtendedStorage then
for extStorageInfo in pairs(storageSystem.storageExtensions) do
if accessHandler:canFarmAccess(ownerFarmId, extStorageInfo)
and THUtils.getNoNil(extStorageInfo.rootNode, 0) ~= 0
then
local extStorageData = g_thMain:getDataTable(extStorageInfo)
local extFillTypeList = extStorageInfo:getSupportedFillTypes()
local extController = nil
local allowAddExtStorage = true
if extStorageData ~= nil and THUtils.getIsType(extStorageData, SCStorage) then
extController = extStorageData.stateController
if extController == nil or extController == self or not extController:getIsEnabled() then
allowAddExtStorage = false
end
end
if allowAddExtStorage then
local ex,ey,ez = getWorldTranslation(extStorageInfo.rootNode)
local distToStorage = THUtils.getVector3Distance(sx,sy,sz, ex,ey,ez)
for stateTypeIdx = 1, SCStateController.MAX_STATE_TYPES do
local stateInfo = self:getCurrentControlState(stateTypeIdx)
if  stateInfo ~= nil and stateInfo.allowExtendedStorage
and distToStorage <= stateInfo.extendedStorageRange
and (extController == nil or extController:getIsStorageActive(extStorageInfo, stateInfo.type))
then
for extFillType in pairs(extFillTypeList) do
if self:getIsExtensionFillType(extFillType, stateInfo.type) then
if stateInfo.extendedStorageMapping[extStorageInfo] == nil then
table.insert(stateInfo.extendedStorages, extStorageInfo)
stateInfo.extendedStorageMapping[extStorageInfo] = #stateInfo.extendedStorages
end
if self.extendedStorageMapping[extStorageInfo] == nil then
table.insert(self.extendedStorages, extStorageInfo)
self.extendedStorageMapping[extStorageInfo] = #self.extendedStorages
end
break
end
end
end
end
end
end
end
end
for _, stationInfo in pairs(self.sellingStations) do
if stationInfo.supportsExtension then
local stationData = g_thMain:getDataTable(stationInfo)
local storagesInRange = storageSystem:getStorageExtensionsInRange(stationInfo, ownerFarmId)
local syncStorage = stationData ~= nil and stationData.syncStorage == true
if syncStorage then
for storageInfo in pairs(stationInfo.targetStorages) do
if not self:getIsStorageActive(storageInfo, SCStateController.STATE_TYPE.INPUT) then
storageSystem:removeStorageFromUnloadingStations(storageInfo, {stationInfo})
end
end
end
if storagesInRange ~= nil then
for _, extStorageInfo in ipairs(storagesInRange) do
local extStorageData = g_thMain:getDataTable(extStorageInfo)
local allowAddExtStorage = true
if extStorageData ~= nil and THUtils.getIsType(extStorageData, SCStorage) then
local extController = extStorageData.stateController
if extController == nil or extController == self or not extController:getIsEnabled() then
allowAddExtStorage = false
elseif syncStorage then
if not extController:getIsStorageActive(extStorageInfo, SCStateController.STATE_TYPE.INPUT) then
allowAddExtStorage = false
end
end
end
if allowAddExtStorage and not stationInfo.targetStorages[extStorageInfo] then
storageSystem:addStorageToUnloadingStation(extStorageInfo, stationInfo)
end
end
end
end
end
for _, stationInfo in pairs(self.loadingStations) do
if stationInfo.supportsExtension then
local stationData = g_thMain:getDataTable(stationInfo)
local storagesInRange = storageSystem:getStorageExtensionsInRange(stationInfo, ownerFarmId)
local syncStorage = stationData ~= nil and stationData.syncStorage == true
if syncStorage then
for storageInfo in pairs(stationInfo.sourceStorages) do
if not self:getIsStorageActive(storageInfo, SCStateController.STATE_TYPE.OUTPUT) then
storageSystem:removeStorageFromLoadingStations(storageInfo, {stationInfo})
end
end
end
if storagesInRange ~= nil then
for _, extStorageInfo in ipairs(storagesInRange) do
local extStorageData = g_thMain:getDataTable(extStorageInfo)
local allowAddExtStorage = true
if extStorageData ~= nil and THUtils.getIsType(extStorageData, SCStorage) then
local extController = extStorageData.stateController
if extController == nil or extController == self or not extController:getIsEnabled() then
allowAddExtStorage = false
elseif syncStorage then
if not extController:getIsStorageActive(extStorageInfo, SCStateController.STATE_TYPE.OUTPUT) then
allowAddExtStorage = false
end
end
end
if allowAddExtStorage and not stationInfo.sourceStorages[extStorageInfo] then
storageSystem:addStorageToLoadingStation(extStorageInfo, stationInfo)
end
end
end
end
end
return true
end
SCStateControllerActivatable = {}
local SCStateControllerActivatable_mt = Class(SCStateControllerActivatable)
function SCStateControllerActivatable.new(controller, customMt)
customMt = THUtils.getNoNil(customMt, SCStateControllerActivatable_mt)
if  THUtils.argIsValid(controller ~= nil and THUtils.getIsType(controller, SCStateController), "controller", controller, true)
and THUtils.argIsValid(type(customMt) == "table", "customMt", customMt, true)
then
local self = setmetatable({}, customMt)
if self ~= nil then
self.i18n = controller.i18n
self.isServer = controller.isServer
self.isClient = controller.isClient
self.stateController = controller
self.activateEventIds = {}
self.activateText = ""
end
return self
end
end
function SCStateControllerActivatable:registerCustomInput(inputContext, ...)
local function protectedFunc(...)
local controller = self.stateController
if controller:getIsEnabled() then
for stateTypeIdx = 1, SCStateController.MAX_STATE_TYPES do
local _, numStates = controller:getControlStateList(stateTypeIdx)
if numStates > 1 then
local stateTypeInfo = controller:getStateType(stateTypeIdx)
local inputAction = stateTypeInfo.activateAction
local _, eventId = g_inputBinding:registerActionEvent(inputAction, self, self.actionSelectControlState, false, true, false, true, stateTypeIdx)
if eventId ~= nil then
g_inputBinding:setActionEventText(eventId, stateTypeInfo.activateText)
g_inputBinding:setActionEventTextVisibility(eventId, true)
g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
self.activateEventIds[stateTypeIdx] = eventId
end
end
end
self:updateActionEvents()
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCStateControllerActivatable:removeCustomInput(inputContext, ...)
local function protectedFunc(...)
g_inputBinding:removeActionEventsByTarget(self)
THUtils.clearTable(self.activateEventIds)
end
return g_thMain:call(protectedFunc, ...)
end
function SCStateControllerActivatable:getIsActivatable(...)
local function protectedFunc(...)
local controller = self.stateController
if controller:getIsEnabled() then
if THUtils.getHasPlayerPermission("manageProductions") then
return true
end
end
return false
end
return g_thMain:call(protectedFunc, ...)
end
function SCStateControllerActivatable:activate(...)
local function protectedFunc(...)
local controller = self.stateController
if controller:getIsEnabled() then
if self.isClient then
g_currentMission:addDrawable(self)
end
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCStateControllerActivatable:deactivate(...)
local function protectedFunc(...)
if self.isClient then
g_currentMission:removeDrawable(self)
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCStateControllerActivatable:update(dt, ...)
local function protectedFunc(...)
local controller = self.stateController
if controller:getIsEnabled() then
self:updateActionEvents()
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCStateControllerActivatable:draw(...)
local function protectedFunc(...)
local controller = self.stateController
if controller:getIsEnabled() then
local hudBox  = controller.hudBox
local hudInfo = controller.hudInfo
if controller.isInTrigger then
controller:updateHudInfo(hudInfo)
local numHudEntries = #hudInfo
if numHudEntries > 0 then
hudBox:clear()
hudBox:setTitle(controller.infoTitle)
for i = 1, numHudEntries do
local hudElement = hudInfo[i]
hudBox:addLine(hudElement.title, hudElement.text, hudElement.accentuate, hudElement.accentuateColor)
hudInfo[i] = nil
end
hudBox:showNextFrame()
end
end
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCStateControllerActivatable:actionSelectControlState(actionName, inputValue, stateType, ...)
local function protectedFunc(...)
local controller = self.stateController
if controller:getIsEnabled() then
controller:selectControlState(nil, stateType)
end
end
return g_thMain:call(protectedFunc, ...)
end
function SCStateControllerActivatable:updateActionEvents()
end