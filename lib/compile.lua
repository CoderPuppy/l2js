local pretty = require 'pl.pretty'.write

local compilers = {}

local nextBID = 0
local function block(locals)
	local bid = nextBID
	nextBID = nextBID + 1
	local data = setmetatable({}, {__index = locals;})
	return setmetatable({}, {
		__index = data;
		__newindex = function(self, key, val)
			if type(val) == 'string' then
				data[key] = val
			elseif val == true then
				data[key] = 'v' .. tostring(bid) .. '_' .. key
			elseif val == nil or val == false then
				data[key] = nil
			end
		end;
	})
end

local function compile(node, locals)
	if not locals then
		locals = block({_ENV = '_ENV'})
	end
	if type(node) ~= 'table' or type(node.tag) ~= 'string' then error('Invalid AST node: ' .. pretty(node)) end
	local compiler = compilers[node.tag]
	if type(compiler) ~= 'function' then error('No compiler for AST node: ' .. pretty(node)) end
	return compiler(node, locals)
end

function compilers.Block(node, locals)
	local out = 'var L2JS$TMP;\n'
	for _, n in ipairs(node, locals) do
		out = out .. compile(n, locals) .. ';\n'
	end
	return out
end

function compilers.Js(node, locals)
	return node[1]
end

function compilers.Call(node, locals)
	local out = 'yield* L2JS$CALL('
	for i, n in ipairs(node, locals) do
		out = out .. compile(n, locals)
		if i == 1 then
			out = out .. ', [].concat('
		elseif i < #node then
			out = out .. ', '
		end
	end
	out = out .. '))'
	return out
end

function compilers.Invoke(node, locals)
	local callNode = {unpack(node)}
	callNode[1] = {
		{'L2JS$TMP', tag = 'Js'};
		callNode[2];
		tag = 'Index';
	}
	callNode[2] = {'L2JS$TMP', tag = 'Js'}
	callNode.tag = 'Call'
	return 'L2JS$TMP = ' .. compile(node[1], locals) .. '; ' .. compile(callNode, status)
end

function compilers.Id(node, locals)
	if locals[node[1]] then
		return locals[node[1]]
	else
		return compilers.Index({
			{
				'_ENV';
				tag = 'Id';
			}, {
				node[1];
				tag = 'String';
			}
		})
	end
end

function compilers.String(node, locals)
	return pretty(node[1])
end

function compilers.Number(node, locals)
	return pretty(node[1])
end

function compilers.True(node, locals)
	return 'true'
end

function compilers.False(node, locals)
	return 'false'
end

function compilers.Index(node, locals)
	return 'yield* L2JS$GET(' .. compile(node[1], locals) .. ', ' .. compile(node[2], status) .. ')'
end

function compilers.Local(node, locals)
	local out = 'var '
	for i, id in ipairs(node[1]) do
		locals[id[1]] = true
		out = out .. locals[id[1]]
		if i < #node[1] then
			out = out .. ','
		end
	end
	out = out .. '; '
	out = out .. compilers.Set(node, locals)
	return out
end

function compilers.Set(node, locals)
	local out = 'L2JS$TMP = [].concat('
	for i, n in ipairs(node[2]) do
		out = out .. compile(n, locals)
		if i < #node[2] then
			out = out .. ', '
		end
	end
	out = out .. '); '
	for i, n in ipairs(node[1]) do
		local val = 'L2JS$TMP[' .. i - 1 .. ']'
		if n.tag == 'Id' then
			local key = n[1]
			if locals[key] then
				out = out .. locals[key] .. ' = ' .. val .. ''
			else
				out = out .. 'yield* L2JS$SET(_ENV, ' .. pretty(key) .. ', ' .. val .. ')'
			end
		elseif n.tag == 'Index' then
			out = out .. 'yield* L2JS$SET(' .. compile(n[1], locals) .. ', ' .. compile(n[2], status) .. ', ' .. val .. ')'
		else
			error('Unhandled node on left side of set: ' .. pretty(n))
		end
		if i < #node[1] then
			out = out .. '; '
		end
	end
	return out
end

function compilers.Return(node, locals)
	local out = 'return [].concat('
	for i, n in ipairs(node) do
		out = out .. compile(n, locals)
		if i < #node then
			out = out .. ', '
		end
	end
	out = out .. ')'
	return out
end

function compilers.Dots(node, locals)
	return '[].slice.call(arguments)'
end

function compilers.Function(node, locals)
	local out = 'function*('
	for i, n in ipairs(node[1]) do
		if n.tag == 'Id' then
			out = out .. n[1]
			if i < #node[1] and node[1][#node[1]].tag ~= 'Dots' then
				out = out .. ', '
			end
		elseif n.tag == 'Dots' then
		else
			error('Invalid node in function arguments: ' .. pretty(n))
		end
	end
	out = out .. ') {\n'
	local contents = compile(node[2], block(locals))
	for line in contents:gmatch('([^\n]+)') do
		out = out .. '\t' .. line .. '\n'
	end
	out = out .. '}'
	return out
end

function compilers.Paren(node, locals)
	return compile(node[1], locals)
end

function compilers.Table(node, locals)
	local arr = {}
	local map = {}
	local kvs = {}
	for _, n in ipairs(node) do
		if n.tag == 'Pair' then
			map[compile(n[1], locals)] = compile(n[2], status)
		else
			arr[#arr + 1] = compile(n, locals)
		end
	end
	for k, v in pairs(map) do
		kvs[#kvs + 1] = {k, v}
	end
	local out = 'L2JS$TABLE([\n'
	local contents = ''
	for n, kv in ipairs(kvs) do
		contents = contents .. '[' .. kv[1] .. ', ' .. kv[2] .. ']'
		if n < #kvs then
			contents = contents .. ','
		end
		contents = contents .. '\n'
	end
	for line in contents:gmatch('([^\n]+)') do
		out = out .. '\t' .. line .. '\n'
	end
	out = out .. '], [\n'
	local contents = ''
	for i, n in ipairs(arr) do
		contents = contents .. n
		if i < #arr then
			contents = contents .. ','
		end
		contents = contents .. '\n'
	end
	for line in contents:gmatch('([^\n]+)') do
		out = out .. '\t' .. line .. '\n'
	end
	out = out .. '])'
	return out
end

local binops = {}
for op in ('add|sub|mul|div|mod|pow|eq|lt|gt|concat'):gmatch('([^|]+)') do
	binops[op] = true
end

function compilers.Op(node, locals)
	if node[1] == 'len' then
		return '(yield* L2JS$LEN(' .. compile(node[2], locals) .. '))'
	elseif node[1] == 'unm' then
		return '(yield* L2JS$UNM(' .. compile(node[2], locals) .. '))'
	elseif node[1] == 'and' then
		return '(' .. compile(node[2], locals) .. ' && ' .. compile(node[3], locals) .. ')'
	elseif node[1] == 'or' then
		return '(' .. compile(node[2], locals) .. ' || ' .. compile(node[3], locals) .. ')'
	elseif binops[node[1]] then
		return '(yield* L2JS$' .. node[1]:upper() .. '(' .. compile(node[2], locals) .. ', ' .. compile(node[3], status) .. '))'
	else
		error('Invalid op: ' .. node[1])
	end
end

function compilers.Break(node, locals)
	return 'break'
end

function compilers.While(node, locals)
	local out = 'while(L2JS$TMP = ' .. compile(node[1], locals) .. ', L2JS$TMP !== undefined && L2JS$TMP !== null && L2JS$TMP !== false) {\n'
	local contents = compile(node[2], block(locals))
	for line in contents:gmatch('([^\n]+)') do
		out = out .. '\t' .. line .. '\n'
	end
	out = out .. '}'
	return out
end

function compilers.Do(node, locals)
	return compilers.Block(node, block(locals))
end

function compilers.Repeat(node, locals)
	local out = 'do {\n'
	local contents = compile(node[1], block(locals))
	for line in contents:gmatch('([^\n]+)') do
		out = out .. '\t' .. line .. '\n'
	end
	out = out .. '} while(' .. compile(node[2]) .. ')'
	return out
end

function compilers.If(node, locals)
	local out = ''
	local i = 1
	while i <= #node do
		local cond = node[i]
		local ifBlock = cond
		if cond.tag ~= 'Block' then
			out = out .. 'if(' .. compile(cond, locals) .. ') {\n'
			ifBlock = node[i + 1]
			i = i + 1
		else
			out = out .. '{\n'
		end

		local contents = compile(ifBlock, block(locals))
		for line in contents:gmatch('([^\n]+)') do
			out = out .. '\t' .. line .. '\n'
		end

		if i < #node then
			out = out .. '} else '
		end
		i = i + 1
	end
	out = out .. '}'
	return out
end

return compile
