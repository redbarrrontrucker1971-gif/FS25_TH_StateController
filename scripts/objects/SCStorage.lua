-- Copyright ©2023 by Todd Hundersmarck (ThundR)
-- All Rights Reserved

SCStorage = {}
SCStorage_mt = Class(SCStorage, THData)
SCStorage.MIN_STORAGE_VALUE = 0.01
function SCStorage.initialize(dataTable, controller, customEnv)
local self = dataTable
self.getParent = function(pSelf)
return SCStorage:superClass().getParent(pSelf)
end
if THUtils.argIsValid(THUtils.getIsType(controller, SCStateController), "controller", controller, true) then
self.stateController = controller
self.messageCenter = controller.messageCenter
self.id = ""
self.name = ""
self.title = ""
self.index = 0
self.customEnv = customEnv
local parent = self:getParent()
g_thMain:setFunctionHook(parent, "load",         SCStorage, nil, self)
g_thMain:setFunctionHook(parent, "setFillLevel", SCStorage, nil, self)
return true
end
return false
end
function SCStorage.registerXMLPaths(schema, path)
local xmlDataKey = g_thMain.xmlDataKey
local storageDataPath = path.."."..xmlDataKey
THUtils.registerXMLPath(schema, XMLValueType.STRING, storageDataPath, "#id", "Storage internal id")
THUtils.registerXMLPath(schema, XMLValueType.STRING, storageDataPath, "#title", "Storage title")
Storage.registerXMLPaths(schema, path)
end
function SCStorage.registerSavegameXMLPaths(schema, path)
local xmlDataKey = g_thMain.xmlDataKey
local storageDataPath = path.."."..xmlDataKey
THUtils.registerXMLPath(schema, XMLValueType.STRING, storageDataPath, "#id", "Storage internal id")
Storage.registerSavegameXMLPaths(schema, path)
end
function SCStorage:hook_load(superFunc, parent, components, xmlFile, xmlKey, i3dMappings, ...)
local function appendFunc(success, ...)
local function protectedChunk()
if success then
local controller = self.stateController
local placeable  = controller:getParentPlaceable()
local xmlDataKey = g_thMain.xmlDataKey
local storageDataKey = xmlKey.."."..xmlDataKey
local i18n = controller.i18n
local storageId    = xmlFile:getValue(storageDataKey.."#id")
local storageTitle = xmlFile:getValue(storageDataKey.."#title")
if storageId == nil or storageId == "" then
THUtils.errorMsg(false, "Failed to load extended storage (missing id)")
success = false
elseif controller:getStorage(storageId) ~= nil then
THUtils.errorMsg(false, "Failed to load extended storage %q (duplicate id)", storageId)
success = false
else
self.id    = storageId:upper()
self.name  = storageId
self.index = 0
if storageTitle ~= nil and storageTitle ~= "" then
self.title = i18n:convertText(storageTitle, self.customEnv)
else
self.title = self.name
end
end
if THUtils.getNoNil(parent.rootNode, 0) == 0 then
parent.rootNode = placeable.rootNode
end
parent.supportsMultipleFillTypes = false
parent:empty()
end
end
g_thMain:call(protectedChunk)
return success, ...
end
return appendFunc(superFunc(parent, components, xmlFile, xmlKey, i3dMappings, ...))
end
function SCStorage:hook_setFillLevel(superFunc, parent, fillLevel, fillType, ...)
local oldFillLevel, allowSet = 0, true
local function prependFunc(...)
if fillLevel ~= nil and fillType ~= nil then
oldFillLevel = parent:getFillLevel(fillType)
allowSet = true
if fillLevel < oldFillLevel and fillLevel < SCStorage.MIN_STORAGE_VALUE then
fillLevel = 0
end
if not parent.supportsMultipleFillTypes then
if fillLevel > 0 then
local otherFillLevelsList = parent:getFillLevels()
for otherFillType, otherFillLevel in pairs(otherFillLevelsList) do
if otherFillType ~= fillType and otherFillLevel > 0 then
if fillLevel > otherFillLevel and otherFillLevel < SCStorage.MIN_STORAGE_VALUE then
superFunc(parent, 0, otherFillType)
else
allowSet = false
end
end
end
end
end
if not allowSet then
if oldFillLevel < SCStorage.MIN_STORAGE_VALUE then
fillLevel = 0
else
fillLevel = oldFillLevel
end
end
end
end
g_thMain:call(prependFunc, ...)
return superFunc(parent, fillLevel, fillType, ...)
end