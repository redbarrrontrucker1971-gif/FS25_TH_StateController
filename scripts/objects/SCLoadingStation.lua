-- Copyright ©2023 by Todd Hundersmarck (ThundR)
-- All Rights Reserved

SCLoadingStation = {}
SCLoadingStation_mt = Class(SCLoadingStation, THData)
function SCLoadingStation.initialize(dataTable, controller)
local self = dataTable
self.getParent = function(pSelf)
return SCLoadingStation:superClass().getParent(pSelf)
end
if THUtils.argIsValid(THUtils.getIsType(controller, SCStateController), "controller", controller, true) then
self.stateController = controller
self.allowedFillTypes = {}
self.syncStorage = false
self.linkedStorages = {
byId     = {},
byIndex  = {},
byTarget = {}
}
local parent = self:getParent()
g_thMain:setFunctionHook(parent, "load", SCLoadingStation, nil, self)
return true
end
return false
end
function SCLoadingStation.registerXMLPaths(schema, xmlPath)
local xmlDataKey = g_thMain.xmlDataKey
local stationDataPath = xmlPath.."."..xmlDataKey
THUtils.registerXMLPath(schema, XMLValueType.STRING, stationDataPath, "#linkedStorageIds #linkedStorages", "Storages linked to this loadingStation")
THUtils.registerXMLPath(schema, XMLValueType.BOOL,   stationDataPath, "#syncStorage", "Synchronize linked storages with state controller", false)
LoadingStation.registerXMLPaths(schema, xmlPath)
end
function SCLoadingStation:getLinkedStorage(target)
local storageInfo = THUtils.getTargetInfo(self, "linkedStorages", target)
local storageData = g_thMain:getDataTable(storageInfo)
return storageInfo, storageData
end
function SCLoadingStation:getLinkedStorageList(byId)
local numStorages = #self.linkedStorages.byIndex
if byId == true then
return self.linkedStorages.byId, numStorages
end
return self.linkedStorages.byIndex, numStorages
end
function SCLoadingStation:hook_load(superFunc, station, components, xmlFile, key, customEnv, i3dMappings, ...)
local function appendFunc(success, ...)
local function protectedChunk()
if success then
local controller = self.stateController
local xmlDataKey = g_thMain.xmlDataKey
local stationDataKey = key.."."..xmlDataKey
self.syncStorage = xmlFile:getValue(stationDataKey.."#syncStorage", false)
self.allowedFillTypes = {}
local linkedStorageIds = THUtils.getXMLValue(xmlFile, stationDataKey, "#linkedStorageIds #linkedStorages")
if linkedStorageIds ~= nil then
local storageIdList = THUtils.splitString(linkedStorageIds, " ")
if storageIdList ~= nil and #storageIdList > 0 then
for _, storageId in pairs(storageIdList) do
local storage, storageData = controller:getStorage(storageId)
if storageData ~= nil and self:getLinkedStorage(storage) == nil then
table.insert(self.linkedStorages.byIndex, storage)
self.linkedStorages.byId[storageData.id] = storage
self.linkedStorages.byTarget[storage] = storage
end
end
end
end
for fillType in pairs(station.supportedFillTypes) do
self.allowedFillTypes[fillType] = true
end
if station.loadTriggers ~= nil then
for _, triggerInfo in pairs(station.loadTriggers) do
local triggerData = g_thMain:createDataTable(triggerInfo)
triggerData.allowedFillTypes = {}
for fillType in pairs(triggerInfo.fillTypes) do
triggerData.allowedFillTypes[fillType] = true
end
end
end
end
end
g_thMain:call(protectedChunk)
return success, ...
end
return appendFunc(superFunc(station, components, xmlFile, key, customEnv, i3dMappings, ...))
end