-- Copyright ©2023 by Todd Hundersmarck (ThundR)
-- All Rights Reserved

THUtils = {
MOD_NAME = g_currentModName,
MSG = {
INTERNAL_ERROR   = "An internal error has occurred",
ARGUMENT_INVALID = "Invalid argument %q (%s) in function call"
},
debugFlags = {},
globalDebug = false,
functionCache = {}
}
function THUtils.displayMsg(text, ...)
if text == "" then
print(text)
else
if text == nil or type(text) ~= "string" then
text = string.format("ERROR: Invalid displayMsg text, %q", text)
else
if select("#", ...) > 0 then
text = string.format(text, ...)
end
end
local modName = THUtils.MOD_NAME
local msgString = string.format("** [%s]: %s", modName, text)
print(msgString)
end
end
function THUtils.warningMsg(text, ...)
if type(text) == "string" then
text = "WARNING: "..text
end
THUtils.displayMsg(text, ...)
end
function THUtils.errorMsg(errorLevel, text, ...)
if errorLevel == true then errorLevel = 2 end
if type(errorLevel) == "number" or errorLevel == nil or errorLevel == false then
if type(text) == "string" then
text = "ERROR: "..text
end
local errorText = text
if select("#", ...) > 0 then
errorText = string.format(text, ...)
end
if errorLevel == nil or errorLevel == false then
THUtils.displayMsg(errorText)
if errorLevel == nil then
printCallstack()
end
else
error(errorText, errorLevel)
end
else
local errorText = string.format(THUtils.MSG.ARGUMENT_INVALID, "errorLevel", errorLevel)
error(errorText, 1)
end
end
function THUtils.assert(expression, raise, text, ...)
if not expression then
if raise ~= nil then
if raise == true then
raise = 3
elseif type(raise) == "number" then
raise = raise + 1
end
end
if raise == false then
THUtils.displayMsg(text, ...)
else
THUtils.errorMsg(raise, text, ...)
end
end
return expression
end
function THUtils.msgOnTrue(expression, raise, text, ...)
if expression then
if raise ~= nil then
if raise == true then
raise = 3
elseif type(raise) == "number" then
raise = raise + 1
end
end
if raise == false then
THUtils.displayMsg(text, ...)
else
THUtils.errorMsg(raise, text, ...)
end
return true
end
return false
end
function THUtils.argIsValid(expression, name, failedArg, raise)
if not expression then
if raise ~= nil then
if raise == false then
raise = nil
elseif raise == true then
raise = 3
elseif type(raise) == "number" then
raise = raise + 1
end
end
THUtils.errorMsg(raise, THUtils.MSG.ARGUMENT_INVALID, name, failedArg)
return false
end
return true
end
function THUtils.printTable(...)
if g_thDebugger ~= nil then
g_thDebugger:printTable(...)
end
end
function THUtils.setDebugFlag(target, isEnabled)
local targetType = type(target)
local flagId = nil
if target ~= nil and target ~= "" then
if targetType == "table" and target.debugFlagId ~= nil then
flagId = tostring(target.debugFlagId)
else
flagId = tostring(target)
end
else
flagId = "ALL"
end
isEnabled = THUtils.toBoolean(isEnabled)
local enabledText = "disabled"
if isEnabled == true then
enabledText = "enabled"
end
if flagId == nil then
THUtils.errorMsg(true, THUtils.MSG.ARGUMENT_INVALID, "target", target)
elseif flagId:upper() == "ALL" then
THUtils.globalDebug = isEnabled
for id in pairs(THUtils.debugFlags) do
THUtils.debugFlags[id] = isEnabled
end
THUtils.displayMsg("Global debug messages are %s", enabledText)
else
THUtils.debugFlags[flagId] = isEnabled
THUtils.displayMsg("Debug messages for %q are %s", flagId, enabledText)
end
end
function THUtils.debugMsg(target, text, ...)
local targetType = type(target)
local flagId = nil
if target ~= nil then
if targetType == "table" and target.debugFlagId ~= nil then
flagId = tostring(target.debugFlagId)
else
flagId = tostring(target)
end
end
if flagId == nil then
THUtils.errorMsg(true, THUtils.MSG.ARGUMENT.INVALID, "target", target)
elseif THUtils.globalDebug or THUtils.debugFlags[flagId] then
if type(text) == "string" and text ~= "" then
text = "DEBUG: "..text
end
THUtils.displayMsg(text, ...)
end
end
function THUtils.getGlobalEnv()
local globalEnv = _G
local mt = getmetatable(_G)
if mt ~= nil and mt.__index ~= nil then
globalEnv = mt.__index
end
return globalEnv
end
function THUtils.pack(...)
return {n = select("#", ...), ...}
end
function THUtils.unpack(target, index, endIndex)
if endIndex == nil and target.n ~= nil then
index = THUtils.getNoNil(index, 1)
endIndex = target.n
end
return unpack(target, index, endIndex)
end
function THUtils.pcall(target, pa,pb,pc,pd,pe,pf,pg,ph,pi,pj,pk,pl,pm,pn,po,pp,pq,pr,ps,pt)
local targetType = type(target)
local function errHandler(errMsg)
errMsg = THUtils.getNoNil(errMsg, THUtils.MSG.INTERNAL_ERROR)
if type(errMsg) == "string" then
THUtils.errorMsg(nil, errMsg)
else
printCallstack()
end
end
local function protectedFunc()
if targetType == "function" then
return target(pa,pb,pc,pd,pe,pf,pg,ph,pi,pj,pk,pl,pm,pn,po,pp,pq,pr,ps,pt)
elseif targetType == "table" then
if type(target[pa] == "function") then
return target[pa](target, pb,pc,pd,pe,pf,pg,ph,pi,pj,pk,pl,pm,pn,po,pp,pq,pr,ps,pt)
else
local errMsg = string.format(THUtils.MSG.ARGUMENT_INVALID, "funcKey", pa)
return error(errMsg, 2)
end
else
local errMsg = string.format(THUtils.MSG.ARGUMENT_INVALID, "target", target)
return error(errMsg, 2)
end
end
return xpcall(protectedFunc, errHandler)
end
function THUtils.call(target, arg1, ...)
local function appendFunc(success, ret1, ...)
if success == true then
return ret1, ...
end
end
return appendFunc(THUtils.pcall(target, arg1, ...))
end
function THUtils.toBoolean(value)
if value == true or value == false then
return value
elseif type(value) == "string" then
local upperVal = value:upper()
if upperVal == "TRUE" then
return true
elseif upperVal == "FALSE" then
return false
end
end
end
function THUtils.getNoNil(target, replacement, includeEmptyStrings)
if target == nil or (target == "" and includeEmptyStrings == true) then
return replacement
end
return target
end
function THUtils.getIsType(value, typeEntry)
local valueType = type(value)
if valueType == typeEntry then
return true
end
local compareType = type(typeEntry)
if compareType == "table" then
if valueType == "table" and value.isa ~= nil and value:isa(typeEntry) then
return true
end
elseif compareType == "string" then
if string.find(typeEntry, "^"..valueType.." ")
or string.find(typeEntry, " "..valueType.."$")
or string.find(typeEntry, " "..valueType.." ")
then
return true
end
else
THUtils.errorMsg(true, THUtils.MSG.ARGUMENT_INVALID, "typeEntry", typeEntry)
end
return false
end
function THUtils.floor(value, precision)
precision = THUtils.getNoNil(precision, 0)
local factor = 10 ^ precision
return math.floor(value * factor) / factor
end
function THUtils.ceil(value, precision)
precision = THUtils.getNoNil(precision, 0)
local factor = 10 ^ precision
return math.ceil(value * factor) / factor
end
function THUtils.round(value, precision)
precision = THUtils.getNoNil(precision, 0)
local factor = 10 ^ precision
return math.floor((value * factor) + 0.5) / factor
end
function THUtils.getVector2Distance(sx,sz, ex,ez)
return math.sqrt(((ex-sx) ^ 2) + ((ez-sz) ^ 2))
end
function THUtils.getVector3Distance(sx,sy,sz, ex,ey,ez)
return math.sqrt(((ex-sx) ^ 2) + ((ey-sy) ^ 2) + ((ez-sz) ^ 2))
end
function THUtils.splitString(text, separator)
local splitTable = string.split(text, separator)
if splitTable == nil then
splitTable = {}
end
return splitTable, #splitTable
end
function THUtils.properCase(text, removeSpaces)
if text == nil then
return
end
local retText = text
retText = string.gsub(retText, "^%l", string.upper)
retText = string.gsub(retText, " %l", string.upper)
if removeSpaces == true then
retText = string.gsub(retText, " ", "")
end
return retText
end
function THUtils.clearTable(target)
for key in pairs(target) do
target[key] = nil
end
return target
end
function THUtils.copyTable(srcTable, depth, upValue)
depth = THUtils.getNoNil(depth, 0)
local newTable = {}
if THUtils.argIsValid(type(srcTable) == "table", "srcTable", srcTable, true) then
for key, val in pairs(srcTable) do
if type(val) == "table" and depth > 0 then
newTable[key] = THUtils.copyTable(val, depth-1)
else
newTable[key] = val
end
end
if upValue ~= nil then
setmetatable(newTable, {__index = upValue})
end
end
return newTable
end
function THUtils.sortTable(target, sortKey, funcName)
local utilFunc = nil
if funcName ~= nil then
utilFunc = THUtils[funcName]
end
local function sortFunc(value1, value2)
if utilFunc ~= nil then
sortKey = THUtils.getNoNil(sortKey, "index")
value1  = utilFunc(value1)
value2  = utilFunc(value2)
elseif sortKey ~= nil then
value1 = target[value1]
value2 = target[value2]
end
if sortKey ~= nil and type(value1) == "table" and type(value2) == "table" then
value1 = value1[sortKey]
value2 = value2[sortKey]
end
if value1 ~= nil and value2 ~= nil then
return value1 < value2
end
return false
end
table.sort(target, sortFunc)
return target
end
function THUtils.getTableLength(target)
local numEntries = 0
for _ in pairs(target) do
numEntries = numEntries + 1
end
return numEntries
end
function THUtils.getTableIsArray(target)
local isArray = target[1] ~= nil
if isArray then
local numEntries = #target
if numEntries > 0 and type(target[1]) == "boolean" then
if numEntries > 2 or target[1] == target[2] or type(target[2]) ~= "boolean" then
isArray = false
end
end
if isArray then
local idx = 1
for _ in pairs(target) do
if target[idx] == nil then
isArray = false
break
end
idx = idx + 1
end
end
end
return isArray
end
function THUtils.getTargetInfo(sourceTable, sourceKey, target, verbose, raise)
local targetType = type(target)
local targetTable = sourceTable[sourceKey]
local targetInfo = nil
if targetType == "table" then
targetInfo = targetTable.byTarget[target]
elseif targetType == "string" then
targetInfo = targetTable.byId[target:upper()]
elseif targetType == "number" then
targetInfo = targetTable.byIndex[target]
elseif target ~= nil then
verbose = true
raise = THUtils.getNoNil(raise, verbose)
end
if targetInfo == nil and verbose == true then
THUtils.errorMsg(raise, "Could not find target (%s) in table %q", target, sourceKey)
end
return targetInfo
end
function THUtils.makeSelfCallback(targetFunc, caller)
local retFunc = function(...)
return targetFunc(caller, ...)
end
return retFunc
end
function THUtils.getFunctionData(target, funcKey, recursive)
local targetName = target
if type(targetName) == "string" then
local globalEnv = THUtils.getGlobalEnv()
target = globalEnv[targetName]
end
local trueTable = target
local oldFunc = trueTable[funcKey]
local rawFunc = rawget(trueTable, funcKey)
if type(oldFunc) == "function" then
if not recursive or oldFunc == rawFunc then
return trueTable, oldFunc, rawFunc
end
if type(trueTable.class) == "function" then
trueTable = trueTable:class()
while type(trueTable) == "table" do
rawFunc = rawget(trueTable, funcKey)
if rawFunc == oldFunc then
return trueTable, oldFunc, rawFunc
end
if type(trueTable.superClass) ~= "function" then
break
end
trueTable = trueTable:superClass()
end
end
end
return trueTable
end
function THUtils.hookFunction(target, funcKey, newFunc, extraArg)
local trueTable, oldFunc, rawFunc = THUtils.getFunctionData(target, funcKey)
if  THUtils.argIsValid(type(trueTable) == "table", "target", target, true)
and THUtils.argIsValid(type(oldFunc) == "function", "funcKey", funcKey, true)
and THUtils.argIsValid(type(newFunc) == "function", "newFunc", newFunc, true)
then
rawset(trueTable, funcKey, function(...)
if extraArg ~= nil then
return newFunc(oldFunc, extraArg, ...)
else
return newFunc(oldFunc, ...)
end
end)
return trueTable, oldFunc, rawFunc
end
end
function THUtils.hasTempHook(caller, arg1, arg2)
local target = arg1
local funcKey = arg2
if arg2 == nil then
target = caller
funcKey = arg1
end
if target ~= caller and type(target) == "string" then
local globalEnv = THUtils.getGlobalEnv()
local targetName = target
target = globalEnv[targetName]
if target == nil then
THUtils.errorMsg(nil, THUtils.MSG.ARGUMENT_INVALID, "target", targetName)
return false
end
end
if  THUtils.argIsValid(caller ~= nil, "caller", caller, true)
and THUtils.argIsValid(funcKey ~= nil, "funcKey", funcKey, true)
then
if target == nil then
return false
end
if  THUtils.argIsValid(type(target) == "table", "target", target, true)
and THUtils.assert(type(target[funcKey]) == "function", true, "Source function %q does not exist", funcKey)
then
local callerData = THUtils.functionCache[caller]
if callerData ~= nil then
local targetData = callerData[target]
if targetData ~= nil then
local cacheEntry = targetData[funcKey]
if cacheEntry ~= nil then
return true, targetData, funcKey
end
end
end
return false
end
end
end
function THUtils.makeTempHook(caller, arg1, arg2, arg3, arg4)
local target = arg1
local funcKey = arg2
local newFunc = arg3
local extraArg = arg4
if type(arg2) == "function" then
target = caller
funcKey = arg1
newFunc = arg2
extraArg = arg3
if arg4 ~= nil then
THUtils.errorMsg(true, THUtils.MSG.ARGUMENT_INVALID, "extraArg", extraArg, true)
return
end
end
if target ~= caller and type(target) == "string" then
local globalEnv = THUtils.getGlobalEnv()
local targetName = target
target = globalEnv[targetName]
if target == nil then
THUtils.errorMsg(nil, THUtils.MSG.ARGUMENT_INVALID, "target", targetName)
return
end
end
local hasHook = THUtils.hasTempHook(caller, target, funcKey)
if hasHook ~= false then
if hasHook == true then
THUtils.errorMsg(true, "Temporary hook %q already exists", funcKey)
end
return
end
local trueTable, oldFunc, rawFunc = THUtils.hookFunction(target, funcKey, newFunc, extraArg)
if trueTable ~= nil and oldFunc ~= nil then
local callerData = THUtils.functionCache[caller]
if callerData == nil then
callerData = {}
THUtils.functionCache[caller] = callerData
end
local targetData = callerData[target]
if targetData == nil then
targetData = {}
callerData[target] = targetData
end
local cacheEntry = targetData[funcKey]
if cacheEntry == nil then
cacheEntry = {}
targetData[funcKey] = cacheEntry
end
cacheEntry.parent = caller
cacheEntry.target = target
cacheEntry.trueTable = trueTable
cacheEntry.funcKey = funcKey
cacheEntry.oldFunc = oldFunc
cacheEntry.rawFunc = rawFunc
return trueTable, cacheEntry
end
end
function THUtils.restoreFunction(caller, arg1, arg2)
local success, targetData, funcKey = THUtils.hasTempHook(caller, arg1, arg2)
if success then
local cacheEntry = targetData[funcKey]
local trueTable = cacheEntry.trueTable
local rawFunc = cacheEntry.rawFunc
rawset(trueTable, funcKey, rawFunc)
targetData[funcKey] = nil
return true
end
return false
end
function THUtils.registerXMLPath(schema, xmlValueType, basePath, xmlKeys, ...)
local xmlKeyType = type(xmlKeys)
local xmlKeyList = nil
if xmlKeyType == "string" then
if string.find(xmlKeys, " ") then
xmlKeyList = THUtils.splitString(xmlKeys, " ")
else
schema:register(xmlValueType, basePath..xmlKeys, ...)
return
end
elseif xmlKeyType == "table" then
xmlKeyList = xmlKeys
else
THUtils.errorMsg(true, THUtils.MSG.ARGUMENT_INVALID, "xmlKeys", xmlKeys)
return
end
if xmlKeyList ~= nil and #xmlKeyList > 0 then
for _, xmlKey in ipairs(xmlKeyList) do
schema:register(xmlValueType, basePath..xmlKey, ...)
end
end
end
function THUtils.getXMLValue(xmlFile, basePath, xmlKeys, defaultValue, ...)
local xmlKeyType = type(xmlKeys)
local xmlKeyList = nil
if xmlKeyType == "string" then
if string.find(xmlKeys, " ") then
xmlKeyList = THUtils.splitString(xmlKeys, " ")
else
return xmlFile:getValue(basePath..xmlKeys, defaultValue, ...)
end
elseif xmlKeyType == "table" then
xmlKeyList = xmlKeys
else
THUtils.errorMsg(true, THUtils.MSG.ARGUMENT_INVALID, "xmlKeys", xmlKeys)
return
end
if xmlKeyList ~= nil and #xmlKeyList > 0 then
for i, xmlKey in ipairs(xmlKeyList) do
local retValue, ra,rb,rc,rd,re,rf,rg,rh,ri,rj = xmlFile:getValue(basePath..xmlKey, nil, ...)
if retValue ~= nil then
if i > 1 then
local msgKey1 = basePath..xmlKey
local msgKey2 = string.gsub(xmlKeyList[1], "^#", "")
THUtils.warningMsg("Outdated xml key (%s), please use %q instead", msgKey1, msgKey2)
end
return retValue, ra,rb,rc,rd,re,rf,rg,rh,ri,rj
end
end
end
return defaultValue
end
function THUtils.loadDataFromMapXML(mission, dataType, loadTarget, loadFunc, xmlSchema, customEnv, baseDirectory, ...)
if  THUtils.argIsValid(THUtils.getIsType(mission, Mission00), "mission", mission)
and THUtils.argIsValid(type(loadFunc) == "function", "loadFunc", loadFunc)
then
local xmlFileId = mission.xmlFile
local xmlFileKey = "map."..dataType
local xmlFilename = getXMLString(xmlFileId, xmlFileKey.."#filename")
if xmlFilename == nil then
return false
end
xmlFilename = Utils.getFilename(xmlFilename, baseDirectory)
local xmlFile = XMLFile.loadIfExists(dataType, xmlFilename, xmlSchema)
if xmlFile ~= nil then
local success = false
if loadTarget == nil then
success = loadFunc(xmlFile, xmlFileKey, mission, customEnv, baseDirectory, ...)
else
success = loadFunc(loadTarget, xmlFile, xmlFileKey, mission, customEnv, baseDirectory, ...)
end
xmlFile:delete()
return success
end
end
return false
end
function THUtils.getElementByProfileName(baseElement, profileName, recursive)
if profileName == nil then
return
end
if profileName == baseElement.profile then
return baseElement
end
local elementList = baseElement.elements
if elementList and #elementList > 0 then
for idx = 1, #elementList do
local element = elementList[idx]
if recursive then
local foundElement = THUtils.getElementByProfileName(element, profileName, recursive)
if foundElement then
return foundElement
end
elseif profileName == element.profile then
return element
end
end
end
end
function THUtils.getPlayerFarmId(connection)
if g_currentMission ~= nil then
return g_currentMission:getFarmId(connection)
end
end
function THUtils.getIsMasterUser()
if g_currentMission ~= nil then
return g_currentMission.isMasterUser
end
return false
end
function THUtils.getHasPlayerPermission(permission, connection, farmId, checkClient)
if g_currentMission ~= nil then
return g_currentMission:getHasPlayerPermission(permission, connection, farmId, checkClient)
end
return false
end
function THUtils.getFillType(fillType, verbose, raise)
local manager = g_fillTypeManager
local fillTypeInfo = nil
if manager ~= nil then
local valType = type(fillType)
if valType == "table" then
if fillType.name ~= nil then
fillTypeInfo = manager:getFillTypeByName(fillType.name)
if fillTypeInfo ~= fillType then
fillTypeInfo = nil
end
end
elseif valType == "string" then
fillTypeInfo = manager:getFillTypeByName(fillType)
elseif valType == "number" then
fillTypeInfo = manager:getFillTypeByIndex(fillType)
elseif fillType ~= nil then
verbose = true
end
end
THUtils.msgOnTrue(fillTypeInfo == nil and verbose == true, raise, THUtils.MSG.ARGUMENT_INVALID, "fillType", fillType)
return fillTypeInfo
end
function THUtils.getFillTypeIndex(target, verbose, raise)
local fillTypeInfo = THUtils.getFillType(target, verbose, raise)
if fillTypeInfo ~= nil then
return fillTypeInfo.index
end
end
function THUtils.getFillTypeList()
if g_fillTypeManager ~= nil then
return g_fillTypeManager:getFillTypes()
end
return {}
end
function THUtils.getFillTypeCategories(fillType)
local fillTypeInfo = THUtils.getFillType(fillType)
local categoryList = {}
local numCategories = 0
if fillTypeInfo ~= nil then
local manager = g_fillTypeManager
for categoryName, fillTypeList in pairs(manager.categoryNameToFillTypes) do
local categoryId = categoryName:upper()
if fillTypeList[fillTypeInfo.index] then
categoryList[categoryId] = true
numCategories = numCategories + 1
end
end
end
return categoryList, numCategories
end
function THUtils.getFillTypeNamesByCategories(categoryNames, fillTypeNames)
local manager = g_fillTypeManager
if manager ~= nil then
local fillTypeList = manager:getFillTypesByCategoryNames(categoryNames)
if fillTypeList ~= nil then
for _, fillType in pairs(fillTypeList) do
local fillTypeInfo = THUtils.getFillType(fillType)
if fillTypeInfo ~= nil then
if fillTypeNames == nil then
fillTypeNames = fillTypeInfo.name
else
fillTypeNames = fillTypeNames.." "..fillTypeInfo.name
end
end
end
end
end
return fillTypeNames
end
function THUtils.getFruitType(fruitType, verbose, raise)
local manager = g_fruitTypeManager
local fruitTypeInfo = nil
if manager ~= nil then
local valType = type(fruitType)
if valType == "table" then
if fruitType.name ~= nil then
fruitTypeInfo = manager:getFruitTypeByName(fruitType.name)
if fruitTypeInfo ~= fruitType then
fruitTypeInfo = nil
end
end
elseif valType == "string" then
fruitTypeInfo = manager:getFruitTypeByName(fruitType)
elseif valType == "number" then
fruitTypeInfo = manager:getFruitTypeByIndex(fruitType)
elseif fruitType ~= nil then
verbose = true
end
end
THUtils.msgOnTrue(fruitTypeInfo == nil and verbose == true, raise, THUtils.MSG.ARGUMENT_INVALID, "fruitType", fruitType)
return fruitTypeInfo
end
function THUtils.getSprayType(sprayType, verbose, raise)
local manager = g_sprayTypeManager
local sprayTypeInfo = nil
if manager ~= nil then
local valType = type(sprayType)
if valType == "table" then
if sprayType.name ~= nil then
sprayTypeInfo = manager:getSprayTypeByName(sprayType.name)
if sprayTypeInfo ~= sprayType then
sprayTypeInfo = nil
end
end
elseif valType == "string" then
sprayTypeInfo = manager:getSprayTypeByName(sprayType)
elseif valType == "number" then
sprayTypeInfo = manager:getSprayTypeByIndex(sprayType)
elseif sprayType ~= nil then
verbose = true
end
end
THUtils.msgOnTrue(sprayTypeInfo == nil and verbose == true, raise, THUtils.MSG.ARGUMENT_INVALID, "sprayType", sprayType)
return sprayTypeInfo
end