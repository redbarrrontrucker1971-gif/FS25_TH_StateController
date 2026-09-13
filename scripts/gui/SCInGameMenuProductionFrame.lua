-- Copyright ©2023 by Todd Hundersmarck (ThundR)
-- All Rights Reserved

SCInGameMenuProductionFrame = {}
SCInGameMenuProductionFrame_mt = Class(SCInGameMenuProductionFrame, THData)
function SCInGameMenuProductionFrame:initialize()
self.getParent = function(pSelf)
return SCProductionPoint:superClass().getParent(pSelf)
end
self.messageCenter = g_thMain.messageCenter
self.areRecipesDirty = false
local parent = self:getParent()
g_thMain:setFunctionHook(parent, "update",                       SCInGameMenuProductionFrame, nil, self)
g_thMain:setFunctionHook(parent, "populateCellForItemInSection", SCInGameMenuProductionFrame, nil, self)
self.messageCenter:subscribe(SCProductionPoint.MESSAGE_TYPE.RECIPE_UPDATED, self.onRecipeUpdated, self)
return true
end
function SCInGameMenuProductionFrame:onRecipeUpdated(recipeInfo, recipeData, ...)
local function protectedFunc()
self.areRecipesDirty = true
end
return g_thMain:call(protectedFunc, ...)
end
function SCInGameMenuProductionFrame.hook_onFrameOpen(superFunc, parent, ...)
local function prependFunc(...)
g_thMain:createDataTable(parent, false, nil,nil, SCInGameMenuProductionFrame_mt)
end
g_thMain:call(prependFunc, ...)
return superFunc(parent, ...)
end
function SCInGameMenuProductionFrame:hook_update(superFunc, parent, dt, ...)
local function appendFunc(...)
local function protectedChunk()
if self.areRecipesDirty then
parent:updateDetails()
self.areRecipesDirty = false
end
end
g_thMain:call(protectedChunk)
return ...
end
return appendFunc(superFunc(parent, dt, ...))
end
function SCInGameMenuProductionFrame:hook_populateCellForItemInSection(superFunc, parent, list, section, index, cell, ...)
local function appendFunc(...)
local function protectedChunk()
if list == parent.productionList then
local productionList = parent:getProductionPoints()
if productionList ~= nil and section ~= nil then
local productionData = g_thMain:getDataTable(productionList[section])
if productionData ~= nil and cell ~= nil and index ~= nil then
local controller = productionData.stateController
if controller ~= nil and controller:getIsEnabled() then
local _, recipeData = productionData:getProductionRecipe(index)
if recipeData ~= nil then
if recipeData.iconFilename ~= nil then
cell:getAttribute("icon"):setImageFilename(recipeData.iconFilename)
end
end
end
end
end
else
local productionData, production = g_thMain:getDataTable(parent.selectedProductionPoint)
if productionData ~= nil and cell ~= nil and index ~= nil then
local controller = productionData.stateController
if controller ~= nil and controller:getIsEnabled() then
local fillType, stateType, isInput = nil,nil,nil
local i18n = controller.i18n
if section == 1 then
fillType = production.inputFillTypeIdsArray[index]
stateType = SCStateController.STATE_TYPE.INPUT
isInput = true
elseif section == 2 then
fillType = production.outputFillTypeIdsArray[index]
stateType = SCStateController.STATE_TYPE.OUTPUT
isInput = false
end
if fillType ~= nil and fillType ~= FillType.UNKNOWN then
local fillLevel = controller:getStorageValue("fillLevel", stateType, fillType)
local capacity = controller:getStorageValue("capacity", stateType, fillType)
local fillPercent = 0
if capacity <= 0 then
fillLevel = 0
else
fillPercent = MathUtil.clamp(fillLevel / capacity, 0, 1)
end
local fillLevelText = i18n:formatVolume(fillLevel, nil,nil, true, nil, fillType)
local statusBar = cell:getAttribute("bar")
cell:getAttribute("fillLevel"):setText(fillLevelText)
parent:setStatusBarValue(statusBar, fillPercent, isInput)
end
end
end
end
end
g_thMain:call(protectedChunk)
return ...
end
return appendFunc(superFunc(parent, list, section, index, cell, ...))
end
local function runScript()
g_thMain:setFunctionHook("InGameMenuProductionFrame", "onFrameOpen", SCInGameMenuProductionFrame, nil, false)
end
g_thMain:call(runScript)