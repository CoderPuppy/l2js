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
	local t = {
		hi = '123';
		[123] = 'hi';
		'hello world';
	}
	function t:hi()

	end
	print(#t + 1 - 1 * 1 / 1 // 1 % 1 ^ 1 * -1 < 1 > 1 == false)
]])
-- pp(ast)
local js = l2js.compile(ast)
print(l2js.header)
print('(function*() {')
print(js)
print('})().next()')
