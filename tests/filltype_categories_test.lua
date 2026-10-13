dofile('scripts/core/THUtils.lua')
local types = {[1]={name='MAIZE'},[2]={name='MAIZE2'},[3]={name='PROPANE'}}
g_fillTypeManager={getFillTypeByIndex=function(_,i)return types[i]end,
getFillTypesByCategoryNames=function(_,s)
 assert(s==nil or type(s)=='string','category names must be text')
 if s=='farmSilo' then return {1,2} end
 if s=='farmSilo LIQUID' then return {1,2,3} end
 return {}
end}
local cats, fills = {'farmSilo'}, {'PROPANE'}
local result=THUtils.getFillTypeNamesByCategories(cats,fills)
assert(type(result)=='table' and table.concat(result,' ')=='PROPANE MAIZE MAIZE2')
assert(#fills==1 and #cats==1 and result~=fills)
assert(THUtils.getFillTypeNamesByCategories('farmSilo','PROPANE')=='PROPANE MAIZE MAIZE2')
assert(THUtils.getFillTypeNamesByCategories(cats,'PROPANE')=='PROPANE MAIZE MAIZE2')
assert(table.concat(THUtils.getFillTypeNamesByCategories('farmSilo',fills),' ')=='PROPANE MAIZE MAIZE2')
assert(#THUtils.getFillTypeNamesByCategories({'farmSilo','LIQUID'},fills)==3)
assert(THUtils.getFillTypeNamesByCategories(nil,nil)==nil)
assert(#THUtils.getFillTypeNamesByCategories({}, {})==0)
g_fillTypeManager=nil
assert(THUtils.getFillTypeNamesByCategories(cats,'PROPANE')=='PROPANE')
print('PASS: array/string combinations, XML array preservation, duplicate removal, empty and absent manager')
