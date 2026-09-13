-- Copyright ©2023 by Todd Hundersmarck (ThundR)
-- All Rights Reserved

SCSelectControlStateEvent = {}
local SCSelectControlStateEvent_mt = Class(SCSelectControlStateEvent, Event)
InitEventClass(SCSelectControlStateEvent, "SCSelectControlStateEvent")
function SCSelectControlStateEvent.emptyNew()
return Event.new(SCSelectControlStateEvent_mt)
end
function SCSelectControlStateEvent.new(controller, stateType, updateVis)
local self = SCSelectControlStateEvent.emptyNew()
if  THUtils.argIsValid(THUtils.getIsType(controller, SCStateController), "controller", controller, true)
and THUtils.argIsValid(not updateVis or updateVis == true, "updateVis", updateVis, true)
then
local stateTypeInfo = controller:getStateType(stateType)
if stateTypeInfo ~= nil then
if controller.isServer then
self.stateIndex = stateTypeInfo.currentControlState
if self.stateIndex == nil then
THUtils.errorMsg(true, "Invalid current %s state", stateTypeInfo.name)
return
end
end
self.controller     = controller
self.stateTypeIndex = stateTypeInfo.index
self.updateVis      = THUtils.getNoNil(updateVis, false)
return self
end
end
end
function SCSelectControlStateEvent:readStream(streamId, connection)
self.controller     = NetworkUtil.readNodeObject(streamId)
self.stateTypeIndex = streamReadUIntN(streamId, SCStateController.NUM_STATE_TYPE_BITS)
self.updateVis      = streamReadBool(streamId)
if streamReadBool(streamId) then
self.stateIndex = streamReadUIntN(streamId, SCStateController.NUM_STATE_BITS)
end
self:run(connection)
end
function SCSelectControlStateEvent:writeStream(streamId, connection)
NetworkUtil.writeNodeObject(streamId, self.controller)
streamWriteUIntN(streamId, self.stateTypeIndex, SCStateController.NUM_STATE_TYPE_BITS)
streamWriteBool(streamId, self.updateVis)
if streamWriteBool(streamId, self.stateIndex ~= nil) then
streamWriteUIntN(streamId, self.stateIndex, SCStateController.NUM_STATE_BITS)
end
end
function SCSelectControlStateEvent:run(connection)
local function protectedFunc()
local controller = self.controller
local stateIndex = self.stateIndex
local stateType  = self.stateTypeIndex
local updateVis  = self.updateVis
if connection:getIsServer() then
controller:selectControlState(stateIndex, stateType, updateVis, true)
else
controller:selectControlState(nil, stateType, updateVis)
end
end
return g_thMain:call(protectedFunc)
end
function SCSelectControlStateEvent.sendEvent(controller, stateType, updateVis)
local function protectedFunc()
local newEvent = SCSelectControlStateEvent.new(controller, stateType, updateVis)
if newEvent ~= nil then
if controller.isServer then
g_server:broadcastEvent(newEvent)
elseif controller.isClient then
g_client:getServerConnection():sendEvent(newEvent)
end
end
end
return g_thMain:call(protectedFunc)
end