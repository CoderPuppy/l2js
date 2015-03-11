local pretty = require 'pl.pretty'.write

local compilers = {}

local function compile(node, status)
	if not status then
		status = {
			locals = {_ENV = true};
		}
	end
	if type(node) ~= 'table' or type(node.tag) ~= 'string' then error('Invalid AST node: ' .. pretty(node)) end
	local compiler = compilers[node.tag]
	if type(compiler) ~= 'function' then error('No compiler for AST node: ' .. pretty(node)) end
	return compiler(node, status)
end

function compilers.Block(node, status)
	local out = 'var L2JS$TMP;\n'
	for _, n in ipairs(node, status) do
		out = out .. compile(n, status) .. ';\n'
	end
	return out
end

function compilers.Js(node, status)
	return node[1]
end

function compilers.Call(node, status)
	local out = 'yield* L2JS$CALL('
	for i, n in ipairs(node, status) do
		out = out .. compile(n, status)
		if i == 1 then
			out = out .. ', [].concat('
		elseif i < #node then
			out = out .. ', '
		end
	end
	out = out .. '))'
	return out
end

function compilers.Invoke(node, status)
	local callNode = {unpack(node)}
	callNode[1] = {
		{'L2JS$TMP', tag = 'Js'};
		callNode[2];
		tag = 'Index';
	}
	callNode[2] = {'L2JS$TMP', tag = 'Js'}
	callNode.tag = 'Call'
	return 'L2JS$TMP = ' .. compile(node[1], status) .. '; ' .. compile(callNode, status)
end

function compilers.Id(node, status)
	if status.locals[node[1]] then
		return node[1]
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

function compilers.String(node, status)
	return pretty(node[1])
end

function compilers.Number(node, status)
	return pretty(node[1])
end

function compilers.True(node, status)
	return 'true'
end

function compilers.False(node, status)
	return 'false'
end

function compilers.Index(node, status)
	return 'yield* L2JS$GET(' .. compile(node[1], status) .. ', ' .. compile(node[2], status) .. ')'
end

function compilers.Local(node, status)
	local out = 'var '
	for i, id in ipairs(node[1]) do
		out = out .. id[1]
		if i < #node[1] then
			out = out .. ','
		end
		status.locals[id[1]] = true
	end
	out = out .. '; '
	out = out .. compilers.Set(node, status)
	return out
end

function compilers.Set(node, status)
	local out = 'L2JS$TMP = [].concat('
	for i, n in ipairs(node[2]) do
		out = out .. compile(n, status)
		if i < #node[2] then
			out = out .. ', '
		end
	end
	out = out .. '); '
	for i, n in ipairs(node[1]) do
		local val = 'L2JS$TMP[' .. i - 1 .. ']'
		if n.tag == 'Id' then
			local key = n[1]
			if status.locals[key] then
				out = out .. key .. ' = ' .. val .. ''
			else
				out = out .. 'yield* L2JS$SET(_ENV, ' .. pretty(key) .. ', ' .. val .. ')'
			end
		elseif n.tag == 'Index' then
			out = out .. 'yield* L2JS$SET(' .. compile(n[1]) .. ', ' .. compile(n[2]) .. ', ' .. val .. ')'
		else
			error('Unhandled node on left side of set: ' .. pretty(n))
		end
		if i < #node[1] then
			out = out .. '; '
		end
	end
	return out
end

function compilers.Return(node, status)
	local out = 'return [].concat('
	for i, n in ipairs(node) do
		out = out .. compile(n, status)
		if i < #node then
			out = out .. ', '
		end
	end
	out = out .. ')'
	return out
end

function compilers.Dots(node, status)
	return '[].slice.call(arguments)'
end

function compilers.Function(node, status)
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
	local block = compile(node[2])
	for line in block:gmatch('([^\n]+)') do
		out = out .. '\t' .. line .. '\n'
	end
	out = out .. '}'
	return out
end

function compilers.Paren(node, status)
	return compile(node[1], status)
end

function compilers.Table(node, status)
	local arr = {}
	local map = {}
	local kvs = {}
	for _, n in ipairs(node) do
		if n.tag == 'Pair' then
			map[compile(n[1], status)] = compile(n[2], status)
		else
			arr[#arr + 1] = compile(n, status)
		end
	end
	for k, v in pairs(map) do
		kvs[#kvs + 1] = {k, v}
	end
	local out = 'yield* L2JS$TABLE([\n'
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
for op in ('add|sub|mul|div|idiv|mod|pow|eq|lt|gt'):gmatch('([^|]+)') do
	binops[op] = true
end

function compilers.Op(node, status)
	if node[1] == 'len' then
		return 'yield* L2JS$LEN(' .. compile(node[2], status) .. ')'
	elseif node[1] == 'unm' then
		return 'yield* L2JS$UNM(' .. compile(node[2], status) .. ')'
	elseif binops[node[1]] then
		return 'yield* L2JS$' .. node[1]:upper() .. '(' .. compile(node[2], status) .. ', ' .. compile(node[3], status) .. ')'
	else
		error('Invalid op: ' .. node[1])
	end
end

return function(ast)
	return compile(ast)
end
