-- Copyright ©2023 by Todd Hundersmarck (ThundR)
-- All Rights Reserved

THMain = {}
local THMain_mt = Class(THMain, THCore)
THMain.COLOR = {
UI_MAIN      = {0.0227, 0.5346, 0.8519, 1},
UI_ALTERNATE = {0.9900, 0.4640, 0.0010, 1},
UI_GREEN     = {0.3763, 0.6038, 0.0782, 1},
UI_DISABLED  = {0.4, 0.4, 0.4, 1}
}
THMain.MESSAGE_TYPE = {
STORAGE_EXTENSION_ADDED   = nextMessageTypeId(),
STORAGE_EXTENSION_REMOVED = nextMessageTypeId(),
FILL_LEVEL_CHANGED        = nextMessageTypeId()
}
function THMain.new(xmlDataKey, customMt)
customMt = THUtils.getNoNil(customMt, THMain_mt)
local self = THCore.new(xmlDataKey, customMt)
if self ~= nil then
end
return self
end
THMain.StorageSystem = {}
function THMain.StorageSystem:hook_addStorage(superFunc, parent, storageInfo, ...)
local function appendFunc(rSuccess, ...)
local function protectedChunk()
if rSuccess and type(storageInfo) == "table" and storageInfo.isExtension then
self.messageCenter:publish(THMain.MESSAGE_TYPE.STORAGE_EXTENSION_ADDED, storageInfo)
end
end
self:call(protectedChunk)
return rSuccess, ...
end
return appendFunc(superFunc(parent, storageInfo, ...))
end
function THMain.StorageSystem:hook_removeStorage(superFunc, parent, storageInfo, ...)
local function appendFunc(rSuccess, ...)
local function protectedChunk()
if rSuccess and type(storageInfo) == "table" and storageInfo.isExtension then
self.messageCenter:publish(THMain.MESSAGE_TYPE.STORAGE_EXTENSION_REMOVED, storageInfo)
end
end
self:call(protectedChunk)
return rSuccess, ...
end
return appendFunc(superFunc(parent, storageInfo, ...))
end
THMain.Storage = {}
function THMain.Storage:hook_setFillLevel(superFunc, parent, fillLevel, fillType, ...)
local oldFillLevel = 0
local function prependFunc(...)
oldFillLevel = parent:getFillLevel(fillType)
end
local function appendFunc(...)
local function protectedChunk()
local newFillLevel = parent:getFillLevel(fillType)
if newFillLevel ~= oldFillLevel then
if math.abs(newFillLevel - oldFillLevel) >= SCStorage.MIN_STORAGE_VALUE then
self.messageCenter:publish(THMain.MESSAGE_TYPE.FILL_LEVEL_CHANGED, parent, fillType, oldFillLevel, newFillLevel)
end
end
end
self:call(protectedChunk)
return ...
end
self:call(prependFunc, ...)
return appendFunc(superFunc(parent, fillLevel, fillType, ...))
end
g_thMain = THMain.new("thStateController")
if g_thMain ~= nil then
local function runScript()
local globalEnv = THUtils.getGlobalEnv()
local modName   = g_thMain.modName
local modPath   = g_thMain.modPath
source(modPath.."scripts/objects/SCStateController.lua")
source(modPath.."scripts/objects/SCStorage.lua")
source(modPath.."scripts/objects/SCSellingStation.lua")
source(modPath.."scripts/objects/SCLoadingStation.lua")
source(modPath.."scripts/objects/SCProductionPoint.lua")
source(modPath.."scripts/events/SCSelectControlStateEvent.lua")
source(modPath.."scripts/events/SCUpdateProductionRecipeEvent.lua")
source(modPath.."scripts/gui/SCInGameMenuProductionFrame.lua")
g_thMain:addSpecialization("placeable", "productionController", "SCPlaceableProductionController", "scripts/placeables/specializations/SCPlaceableProductionController.lua")
g_thMain:setFunctionHook("StorageSystem", "addStorage", THMain.StorageSystem)
g_thMain:setFunctionHook("StorageSystem", "removeStorage", THMain.StorageSystem)
g_thMain:setFunctionHook("Storage", "setFillLevel", THMain.Storage)
end
g_thMain:call(runScript)
end