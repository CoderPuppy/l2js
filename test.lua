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
	while false or true do
		break
	end

	do
		print('hi')
	end

	repeat
		local a = b
		break
	until (true or false) and true

	if false then
		local a = b

	elseif hi then
	else
	end

	print('hello' .. ' ' .. 'world')
]])
-- pp(ast)
local js = l2js.compile(ast)
print(l2js.header)
print('(function*() {')
print(js)
print('})().next()')
