-- Copyright ©2023 by Todd Hundersmarck (ThundR)
-- All Rights Reserved

THCore = {}
local THCore_mt = Class(THCore)
function THCore.new(xmlDataKey, customMt)
customMt = Utils.getNoNil(customMt, THCore_mt)
local self = setmetatable({}, customMt)
if  self ~= nil
and THUtils.argIsValid(type(xmlDataKey) == "string" and xmlDataKey ~= "", "xmlDataKey", xmlDataKey)
then
local missionInfo = g_mpLoadingScreen.missionInfo
local missionDynamicInfo = g_mpLoadingScreen.missionDynamicInfo
self.isServer = g_server ~= nil
self.isClient = g_client ~= nil
self.i18n = g_i18n
self.inputBinding  = g_inputBinding
self.messageCenter = g_messageCenter
self.taskManager   = g_asyncTaskManager
self.actionEventIds = {}
self.isMultiplayer  = missionDynamicInfo.isMultiplayer
self.isEnabled      = true
self.modList = missionDynamicInfo.mods
self.modInfo = nil
self.modName = g_currentModName
self.modPath = g_currentModDirectory
self.modTitle = ""
self.modVersion = ""
self.modEnvironments = {}
self.modSettingsPath = g_currentModSettingsDirectory
self.sdkPath = self.modPath.."sdk/"
self.xmlDataKey = xmlDataKey
self.loadedMods = {
byId     = {},
byIndex  = {},
byTarget = {}
}
local mapInfo = missionInfo.map
local mapName = mapInfo.id
if mapInfo.isModMap then
if THUtils.getNoNil(mapInfo.customEnvironment, "") ~= "" then
mapName = mapInfo.customEnvironment
end
end
if THUtils.getNoNil(mapName, "") ~= "" then
self.mapName = mapName
self.mapSettingsPath = self.modSettingsPath.."maps/"..mapName.."/"
end
self.mapInfo = mapInfo
self.mapTitle = ""
self.mapVersion = ""
self.mapIsMod = mapInfo.isModMap
self.mapXMLFile = mapInfo.mapXMLFilename
self.mapModInfo = nil
if self.mapIsMod then
self.mapPath = mapInfo.baseDirectory
end
self.specializations = {
byId      = {},
byType    = {},
byIndex   = {},
byTarget  = {},
idToIndex = {}
}
self.SPECIALIZATION = self.specializations.idToIndex
self.specTypes = {
byId      = {},
byIndex   = {},
byTarget  = {},
idToIndex = {}
}
table.insert(self.specTypes.byIndex, {name="vehicle"})
table.insert(self.specTypes.byIndex, {name="placeable"})
for i, specTypeInfo in ipairs(self.specTypes.byIndex) do
specTypeInfo.id = specTypeInfo.name:upper()
specTypeInfo.index = i
self.specTypes.byId[specTypeInfo.id] = specTypeInfo
self.specTypes.byTarget[specTypeInfo] = specTypeInfo
self.specTypes.idToIndex[specTypeInfo.id] = specTypeInfo.index
self.specializations.byType[specTypeInfo.index] = {}
end
self.SPEC_TYPE = self.specTypes.idToIndex
if self:init() then
return self
end
end
end
function THCore:init()
self:initLoadedMods()
self:addConsoleCommand("setDebugFlag", "Sets specified debug flag", "consoleCommandSetDebugFlag")
self:setFunctionHook("BaseMission",   "loadMapFinished",        THCore)
self:setFunctionHook("TypeManager",   "finalizeTypes",          THCore)
return true
end
function THCore:onRegisterActionEvents(mission)
end
function THCore:onUnregisterActionEvents(mission)
end
function THCore:consoleCommandSetDebugFlag(isEnabled, flagId)
local modName = self.modName
local usageMsg = "Usage: "..modName:gsub("^FS22_TH_", "th")..":setDebugFlag isEnabled flagId"
isEnabled = THUtils.toBoolean(isEnabled)
if isEnabled == nil then
printf(usageMsg)
else
THUtils.setDebugFlag(flagId, isEnabled)
end
end
function THCore:disable()
if self.isEnabled then
self.isEnabled = false
THUtils.displayMsg("Mod has been disabled...")
end
end
function THCore:call(target, arg1, ...)
local function appendFunc(success, ret1, ...)
if success == true then
return ret1, ...
end
self:disable()
end
if self.isEnabled then
if type(target) == "string" then
return appendFunc(THUtils.pcall(self, target, arg1, ...))
end
return appendFunc(THUtils.pcall(target, arg1, ...))
end
end
function THCore:addConsoleCommand(name, desc, callbackName)
local modName = self.modName
addConsoleCommand(modName:gsub("^FS22_TH_", "th")..":"..name, desc, callbackName, self)
end
function THCore:setFunctionHook(srcClass, srcFuncKey, tgtClass, tgtFuncKey, useSelf, extraArg)
useSelf = THUtils.getNoNil(useSelf, self)
if type(srcClass) == "string" then
local globalEnv = THUtils.getGlobalEnv()
srcClass = globalEnv[srcClass]
end
if tgtFuncKey == nil then
if type(srcFuncKey) == "string" then
tgtFuncKey = "hook_"..srcFuncKey
end
end
local selfType = type(useSelf)
local newSelf = nil
if selfType == "table" then
newSelf = useSelf
useSelf = true
elseif selfType ~= "boolean" then
THUtils.errorMsg(true, THUtils.MSG.ARGUMENT_INVALID, "useSelf", useSelf)
return
end
local srcFunc = srcClass[srcFuncKey]
local tgtFunc = tgtClass[tgtFuncKey]
if  THUtils.assert(type(srcFunc) == "function", true, "Invalid source function %q", srcFuncKey)
and THUtils.assert(type(tgtFunc) == "function", true, "Invalid target function %q", tgtFuncKey)
then
local function retFunc(p1, ...)
if self.isEnabled then
if useSelf == true then
if newSelf == nil then
if extraArg == nil then
return tgtFunc(p1, srcFunc, ...)
else
return tgtFunc(p1, srcFunc, extraArg, ...)
end
else
if extraArg == nil then
return tgtFunc(newSelf, srcFunc, p1, ...)
else
return tgtFunc(newSelf, srcFunc, extraArg, p1, ...)
end
end
else
if extraArg == nil then
return tgtFunc(srcFunc, p1, ...)
else
return tgtFunc(srcFunc, extraArg, p1, ...)
end
end
end
return srcFunc(p1, ...)
end
rawset(srcClass, srcFuncKey, retFunc)
return retFunc
end
end
function THCore:createDataTable(parent, clear, useRawGet, useRawSet, customMt, ...)
if parent == nil then
return
end
if THUtils.argIsValid(customMt == nil or type(customMt) == "table", "customMt", customMt, true) then
local tableKey = "data."..self.modName
local dataTable = self:getDataTable(parent, useRawGet)
if dataTable == nil or clear == true then
if dataTable ~= nil and clear == true then
if dataTable.delete ~= nil then
if not self:call(dataTable, "delete") then
if self.isEnabled then
THUtils.errorMsg(nil, "Could not delete data table")
self:disable()
end
end
end
end
if self.isEnabled then
dataTable = THData.new(parent, customMt)
if useRawSet == true then
rawset(parent, tableKey, dataTable)
else
parent[tableKey] = dataTable
end
end
if not dataTable.isInitFinished then
if dataTable.initialize ~= nil then
if not self:call(dataTable, "initialize", ...) then
if self.isEnabled then
THUtils.errorMsg(nil, "Failed to initialize data table")
self:disable()
end
end
end
dataTable.isInitFinished = true
end
return dataTable, parent
end
end
return nil, parent
end
function THCore:getDataTable(parent, useRawGet)
local tableKey = "data."..self.modName
local dataTable = nil
if parent ~= nil then
if useRawGet == true then
dataTable = rawget(parent, tableKey)
else
dataTable = parent[tableKey]
end
end
return dataTable, parent
end
function THCore:initLoadedMods()
local globalEnv = THUtils.getGlobalEnv()
for _, modInfo in ipairs(self.modList) do
local modName = THUtils.getNoNil(modInfo.modName, "")
if modName ~= "" then
local modEntry = {
id      = modName:upper(),
info    = modInfo,
name    = modName,
path    = modInfo.modDir,
file    = modInfo.modFile,
index   = #self.loadedMods.byIndex + 1,
title   = modInfo.title,
version = modInfo.version,
environment = globalEnv[modName]
}
self.loadedMods.byId[modEntry.id] = modEntry
self.loadedMods.byIndex[modEntry.index] = modEntry
self.loadedMods.byTarget[modEntry] = modEntry
if modName == self.modName then
self.modInfo    = modEntry
self.modTitle   = modEntry.title
self.modVersion = modEntry.version
end
if self.mapIsMod and self.mapName ~= nil and modName == self.mapName then
self.mapModInfo = modEntry
self.mapTitle   = modEntry.title
self.mapVersion = modEntry.version
end
end
end
end
function THCore:getLoadedMod(modName, verbose, raise)
local modEntry = nil
if type(modName) == "string" then
modEntry = self.loadedMods.byId[modName:upper()]
elseif modName ~= nil then
verbose = true
raise = THUtils.getNoNil(raise, true)
end
THUtils.msgOnTrue(modEntry == nil and verbose == true, raise, THUtils.MSG.ARGUMENT_INVALID, "modName", modName)
return modEntry
end
function THCore:getLoadedModByClassName(className, modName)
local modEntry = nil
if modName ~= nil then
modEntry = self:getLoadedMod(modName)
end
local function getModClass(pModEntry)
if pModEntry ~= nil and pModEntry.environment ~= nil then
local modClass = pModEntry.environment[className]
if type(modClass) == "table" then
return modClass
end
end
end
if modEntry == nil then
local loadedModList, numLoadedMods = self:getLoadedModList()
if numLoadedMods > 0 then
for i = 1, numLoadedMods do
modEntry = loadedModList[i]
local modClass = getModClass(modEntry)
if modClass ~= nil then
return modEntry, modClass
end
end
end
else
local modClass = getModClass(modEntry)
if modClass ~= nil then
return modEntry, modClass
end
end
end
function THCore:getLoadedModList(byId)
local numLoadedMods = #self.loadedMods.byIndex
if byId == true then
return self.loadedMods.byId, numLoadedMods
end
return self.loadedMods.byIndex, numLoadedMods
end
function THCore:getModVersion(modName, getNumeric)
local modEntry = self.modInfo
if modName ~= nil then
modEntry = self:getLoadedMod(modName)
end
if modEntry ~= nil then
if getNumeric ~= false then
return modEntry.version
end
return modEntry.numericVersion
end
end
function THCore:loadMissionMapData(mission, dataType, loadFunc, loadTarget, xmlSchema, ...)
local function protectedFunc(...)
mission = THUtils.getNoNil(mission, g_currentMission)
if type(loadFunc) == "string" then
loadTarget = THUtils.getNoNil(loadTarget, self)
loadFunc = loadTarget[loadFunc]
end
if mission == nil then
return false
end
if self.mapIsMod then
local mapModName = self.mapModInfo.name
local mapPath = self.mapPath
return THUtils.loadDataFromMapXML(mission, dataType, loadTarget, loadFunc, xmlSchema, mapModName, mapPath, ...)
end
return false
end
return self:call(protectedFunc, ...)
end
function THCore:getSpecializationType(specType, verbose, raise)
return THUtils.getTargetInfo(self, "specTypes", specType, verbose, raise)
end
function THCore:addSpecialization(specType, specName, className, filename)
local modName = self.modName
local modPath = self.modPath
local specTypeInfo = self:getSpecializationType(specType, true, true)
local specManager = nil
if specTypeInfo ~= nil then
if specTypeInfo.index == self.SPEC_TYPE.VEHICLE then
specManager = g_specializationManager
elseif specTypeInfo.index == self.SPEC_TYPE.PLACEABLE then
specManager = g_placeableSpecializationManager
end
end
if specManager ~= nil then
local internalSpecName = modName.."."..specName
local specEntry = specManager:getSpecializationByName(internalSpecName)
filename = modPath..filename
if  THUtils.assert(fileExists(filename), true, "Cannot load filename %s", filename)
and THUtils.assert(specEntry == nil, true, "Specialization %q already exists", specName)
then
local specInfo = self:getSpecialization(specName)
if specInfo == nil then
specInfo = {
id    = specName:upper(),
name  = specName,
index = #self.specializations.byIndex + 1,
type  = specTypeInfo.index
}
specManager:addSpecialization(specName, className, filename, modName)
specEntry = specManager:getSpecializationByName(internalSpecName)
local specClass = _G[className]
if THUtils.msgOnTrue(specEntry == nil, true, "Specialization %q was not added correctly", specName)
or THUtils.msgOnTrue(type(specClass) ~= "table", true, THUtils.MSG.ARGUMENT_INVALID, "className", className)
then
return
end
specInfo.entry = specEntry
specInfo.class = specClass
self.specializations.byId[specInfo.id] = specInfo
self.specializations.byIndex[specInfo.index] = specInfo
self.specializations.byTarget[specInfo] = specInfo
self.specializations.idToIndex[specInfo.id] = specInfo.index
table.insert(self.specializations.byType[specInfo.type], specInfo)
end
return specInfo
end
end
end
function THCore:getSpecialization(spec, verbose, raise)
return THUtils.getTargetInfo(self, "specializations", spec, verbose, raise)
end
function THCore:getSpecializationList(byId)
local numSpecs = #self.specializations.byIndex
if byId == true then
return self.specializations.byId, numSpecs
else
return self.specializations.byIndex, numSpecs
end
end
function THCore:getSpecializationListByType(specType, verbose, raise)
local specTypeInfo = self:getSpecializationType(specType, verbose, raise)
local numSpecs = 0
if specTypeInfo ~= nil then
numSpecs = #self.specializations.byType[specTypeInfo.index]
return self.specializations.byType[specTypeInfo.index], numSpecs
end
return nil, numSpecs
end
function THCore:getSpecTable(object, specName)
local specKey = "spec_"..self.modName.."."..specName
local specTable, objectData = nil,nil
if object ~= nil then
specTable = object[specKey]
objectData = self:getDataTable(object)
end
return specTable, objectData, object
end
function THCore:hook_loadMapFinished(superFunc, mission, ...)
local function appendFunc(...)
local function protectedChunk()
if not mission.cancelLoading then
end
end
self:call(protectedChunk)
return ...
end
return appendFunc(superFunc(mission, ...))
end
function THCore:hook_registerActionEvents(superFunc, mission, ...)
local function appendFunc(...)
local function protectedChunk()
self:onRegisterActionEvents(self)
end
self:call(protectedChunk)
return ...
end
return appendFunc(superFunc(mission, ...))
end
function THCore:hook_unregisterActionEvents(superFunc, mission, ...)
local function appendFunc(...)
local function protectedChunk()
self:onUnregisterActionEvents(self)
end
self:call(protectedChunk)
return ...
end
return appendFunc(superFunc(mission, ...))
end
function THCore:hook_finalizeTypes(superFunc, manager, ...)
local function prependFunc()
local typeList = manager:getTypes()
local specList, numSpecs = self:getSpecializationListByType(manager.typeName)
if numSpecs > 0 then
for typeName, typeEntry in pairs(typeList) do
for _, specInfo in ipairs(specList) do
local internalSpecName = specInfo.entry.name
local specClass = specInfo.class
if  typeEntry.specializationsByName[internalSpecName] == nil
and specClass.prerequisitesPresent(typeEntry.specializations)
then
manager:addSpecialization(typeName, internalSpecName)
end
end
end
end
end
self:call(prependFunc)
return superFunc(manager, ...)
end