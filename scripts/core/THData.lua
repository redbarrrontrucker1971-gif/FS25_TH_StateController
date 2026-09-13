-- Copyright ©2023 by Todd Hundersmarck (ThundR)
-- All Rights Reserved

THData = {}
local THData_mt = Class(THData)
function THData.new(parent, customMt)
customMt = Utils.getNoNil(customMt, THData_mt)
if  THUtils.argIsValid(type(parent) == "table", "parent", parent)
and THUtils.argIsValid(type(customMt) == "table", "customMt", customMt)
then
local self = setmetatable({}, customMt)
if self ~= nil then
self.parentTable    = parent
self.defaultValues  = {}
self.isInitFinished = false
self:updateDefaultValues()
end
return self
end
end
function THData:getParent()
return self.parentTable
end
function THData:getParentValue(key)
local parent = self:getParent()
return parent[key]
end
function THData:updateDefaultValues(reset)
local parent = self:getParent()
if reset == true then
THUtils.clearTable(self.defaultValues)
end
for key, val in pairs(parent) do
self.defaultValues[key] = val
end
end
function THData:setDefaultValue(key)
local parent = self:getParent()
local defaultValue = parent[key]
self.defaultValues[key] = defaultValue
end
function THData:getDefaultValue(key)
return self.defaultValues[key]
end
function THData:restoreDefaultValue(key, force)
local parent = self:getParent()
local defaultValue = self.defaultValues[key]
if defaultValue ~= nil or force == true then
parent[key] = defaultValue
end
end
function THData:restoreDefaultValues(force)
local parent = self:getParent()
for key in pairs(parent) do
self:restoreDefaultValue(key, force)
end
end