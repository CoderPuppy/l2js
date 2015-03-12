local require = require 'nsrq'()
_G.pp = (function(pretty)
   return function(...)
     for _, v in ipairs({...}) do
       print(pretty.write(v))
     end
   end
 end)(require 'pl.pretty')
local l2js = require './'
local ast = l2js.parse([[
]])
-- pp(ast)
local js = l2js.compile(ast)
print(l2js.header)
print('var g = (function*() {')
print(js)
print('})(); var res; do { res = g.next([]) } while(!res.done)')
