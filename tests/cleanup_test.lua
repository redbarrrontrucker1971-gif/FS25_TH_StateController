-- Exercise the real controller deletion method with game resources stubbed.
function Class(class, parent)
    class.superClass = function() return parent end
    return {__index = class}
end
local count = {base = 0, trigger = 0, hud = 0, storage = 0, station = 0}
Object = {delete = function(self) count.base = count.base + 1; self.registered = false end}
InfoDisplayKeyValueBox = {}; ActivatableObject = {}
InitObjectClass = function() end
nextMessageTypeId = function() return 1 end
local liveTrigger = true
entityExists = function() return liveTrigger end
removeTrigger = function() assert(liveTrigger); count.trigger = count.trigger + 1 end
FillType = {LIQUIDMANURE = 1, DIGESTATE = 2}
local function noop() end
g_currentMission = {
    activatableObjectsSystem = {removeActivatable = noop},
    economyManager = {removeSellingStation = noop},
    hud = {infoDisplay = {destroyBox = function() count.hud = count.hud + 1 end}}
}
dofile("scripts/objects/SCStateController.lua")
local function controller()
    local storage = {isExtension = false, delete = function() count.storage = count.storage + 1 end}
    local station = {getIsFillTypeSupported = function() return false end,
        delete = function() count.station = count.station + 1 end}
    return setmetatable({
        triggerNode = 123, hudBox = {}, registered = true, activatable = {},
        parentPlaceable = {}, loadingStations = {station}, sellingStations = {station},
        storageSystem = {removeLoadingStation = noop, removeUnloadingStation = noop},
        messageCenter = {unsubscribeAll = noop},
        getStorageList = function() return {storage}, 1 end
    }, {__index = SCStateController})
end
local c = controller()
c:delete(); c:delete()
assert(count.base == 1 and count.trigger == 1 and count.hud == 1)
assert(count.storage == 1 and count.station == 2)
assert(c.triggerNode == nil and c.hudBox == nil and not c.registered)
print("PASS cleanup runs once and calls Object.delete to unregister")
liveTrigger = false
local second = controller()
second:delete()
assert(count.trigger == 1 and count.base == 2)
print("PASS stale scene trigger is not passed to removeTrigger")
