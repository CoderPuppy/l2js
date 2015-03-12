// TODO: tonumber

exports.type = function(self) {
	if(self === null || self === undefined) return 'nil'
	switch(typeof(self)) {
	case 'object':
		if(self.L2JS$TABLE)
			return 'table'
		else
			return 'js'

	case 'number':
	case 'string':
	case 'boolean':
	case 'function':
			return typeof(self)

	default:
		throw new Error('unhandled type: ' + typeof(self))
	}
}

exports.table = function(kvs, arr) {
	var table = {
		L2JS$TABLE: true,
		map: new Map(),
		arr: arr,
	}

	kvs.forEach(function(kv) {
		table.map.set(kv[1], kv[2])
	})

	return table
}

exports.rawget = function(self, key) {
	if(exports.type(self) != 'table') throw new Error('bad argument #1 to \'rawget\' (table expected, got ' + exports.type(self) + ')')
	if(typeof(key) == 'number' && key >= 1)
		return self.arr[key - 1]
	else
		return self.map.get(key)
}

exports.get = function*(self, key) {
	var type = exports.type(self)
	if(type == 'table') {
		var index, indexType
		if(self.mt && (indexType = type(index = yield* exports.get(self.mt, '__index'))) != 'nil') {
			if(indexType == 'function')
				return (yield* index(self, key))[0]
			else
				return yield* exports.get(index, key)
		} else {
			return exports.rawget(self, key)
		}
	} else if(type == 'string') {
		// TODO: string metatable
	} else {
		throw new Error('attempt to index a ' + type + ' value')
	}
}

exports.rawset = function(self, key, val) {
	if(exports.type(self) != 'table') throw new Error('bad argument #1 to \'rawset\' (table expected, got ' + exports.type(self) + ')')
	if(typeof(key) == 'number' && key >= 1)
		self.arr[key - 1] = val
	else
		self.map.set(key, val)
}

exports.set = function*(self, key, val) {
	var type = exports.type(self)
	if(type == 'table') {
		var index, indexType
		if(self.mt && (indexType = type(index = yield* exports.get(self.mt, '__newindex'))) != 'nil') {
			if(indexType == 'function')
				yield* index(self, key, val)
			else
				yield* exports.set(index, key, val)
		} else {
			exports.rawset(self, key, val)
		}
	} else {
		throw new Error('attempt to index a ' + type + ' value')
	}
}

exports.rawlen = function(self) {
	var type = exports.type(self)
	if(type == 'table') {
		var len = 0
		for(var i = 0; i < self.arr.length; i++) {
			if(exports.type(self.arr[i]) != 'nil') len++
		}
		return len
	} else if(type == 'string') {
		return self.length
	} else {
		throw new Error('attempt to get length of a ' + type + ' value')
	}
}

exports.len = function*(self) {
	var type = exports.type(self)
	var len, lenType
	if(type == 'table' && self.mt && (lenType = exports.type(len = yield* exports.get(self.mt, '__len'))) != 'nil')
		return (yield* exports.call(len, [self]))[0]
	else
		return exports.rawlen(self)
}

exports.tonumber = function(self, base) {
	if(typeof(self) == 'number') return self
	if(typeof(base) == 'string') {
		var origBase = base
		base = exports.tonumber(base)
		if(typeof(base) != 'number')
			throw new Error('bad argument #2 to \'tonumber\' (number expected, got ' + exports.type(origBase) + ')')
	}
	if(typeof(base) != 'number') base = 10
	if(typeof(self) != 'string') throw new Error('bad argument #1 to \'tonumber\' (string expected, got ' + exports.type(self) + ')')
	if(base > 36 || base < 2) throw new Error('bad argument #2 to \'tonumber\' (base out of range)')
	var bad = false
	var digits = self.toLowerCase().split('').reverse().map(function(c) {
		var n = c.charCodeAt(0)
		if(c >= '0' && c <= '9') return n - 48
		if(c >= 'a' && c <= 'z') return n - 97 + 10
		bad = true
	})
	if(bad || digits.some(function(n) { return n >= base })) return
	return digits.reduce(function(acc, v, i) {
		return acc + v * Math.pow(base, i)
	}, 0)
}

exports.rawunm = function(self) {
	var n = exports.tonumber(self)
	if(typeof(n) == 'number')
		return -n
	else
		throw new Error('attempt to perform arithmetic on a ' + exports.type(self) + ' value')
}

exports.unm = function*(self) {
	var type = exports.type(self)
	var unm, unmType
	if(type == 'table' && self.mt && (unmType = exports.type(unm = yield* exports.get(self.mt, '__unm'))) != 'nil')
		return (yield* exports.call(unm, [self]))[0]
	else
		return exports.rawunm(self)
}

function* getequalhandler(a, b) {
	var typeA = exports.type(a), typeB = exports.type(b)
	if(exports.type(a) != 'table' || exports.type(b) != 'table') return

	var mt1 = a.mt, mt2 = b.mt
	if(exports.type(mt1) == 'nil' || exports.type(mt2) == 'nil') return
	var mm1 = (yield* exports.get(mt1, '__eq')), mm2 = (yield* exports.get(mt2, '__eq'))
	if(mm1 == mm2) return mm1
}

exports.raweq = function(a, b) {
	return a == b
}

exports.eq = function*(a, b) {
	if(exports.raweq(a, b)) return true
	var h = yield* getequalhandler(a, b)
	if(exports.type(h) != 'nil')
		return !!(yield* exports.call(h, a, b))[0]
	else
		return false
}

function getbinhandler(a, b, op) {
	var ta = exports.type(a), tb = exports.type(b)
	var mm
	if(ta == 'table' && ta.mt && exports.type(mm = yield* exports.get(ta.mt, op)) != 'nil')
		return mm
	if(tb == 'table' && tb.mt && exports.type(mm = yield* exports.get(tb.mt, op)) != 'nil')
		return mm
}

;[['add', '+'], ['sub', '-'], ['mul', '*'], ['div', '/'], ['mod', '%']].forEach(function(v) {
	var name = v[0]
	var op = v[1]

	eval('exports.raw' + name + ' = function(a, b) {\n' +
	'\tvar na = exports.tonumber(a), nb = exports.tonumber(b)\n' +
	'\tif(typeof(na) == \'number\' && typeof(nb) == \'number\') {\n' +
	'\t\treturn na ' + op + ' nb\n' +
	'\t} else {\n' +
	'\t\tif(typeof(na) != \'number\')\n' +
	'\t\t\tthrow new Error(\'attempt to perform arithmetic on a \' + exports.type(a) + \' value\')\n' +
	'\t\telse if(typeof(nb) != \'number\')\n' +
	'\t\t\tthrow new Error(\'attempt to perform arithmetic on a \' + exports.type(b) + \' value\')\n' +
	'\t\telse\n' +
	'\t\t\tthrow new Error(\'bad\')\n' +
	'\t}\n' +
	'}')

	eval('exports.' + name + ' = function*(a, b) {\n' +
	'\ttry {\n' +
	'\t\treturn exports.raw' + name + '(a, b)\n' +
	'\t} catch(e) {\n' +
	'\t	var h = getbinhandler(a, b, \'__' + name + '\')\n' +
	'\t	if(exports.type(h) != \'nil\')\n' +
	'\t		return (yield* exports.call(h, [a, b]))[0]\n' +
	'\t	else\n' +
	'\t		throw e\n' +
	'\t}\n' +
	'}')
})

exports.rawpow = function(a, b) {
	var na = exports.tonumber(a), nb = exports.tonumber(b)
	if(typeof(na) == 'number' && typeof(nb) == 'number') {
		return Math.pow(na, nb)
	} else {
		if(typeof(na) != 'number')
			throw new Error('attempt to perform arithmetic on a ' + exports.type(a) + ' value')
		else if(typeof(nb) != 'number')
			throw new Error('attempt to perform arithmetic on a ' + exports.type(b) + ' value')
		else
			throw new Error('bad')
	}
}

exports.pow = function*(a, b) {
	try {
		return exports.rawpow(a, b)
	} catch(e) {
		var h = getbinhandler(a, b, '__pow')
		if(exports.type(h) != 'nil')
			return (yield* exports.call(h, [a, b]))[0]
		else
			throw e
	}
}

exports.rawconcat = function(a, b) {
	var sa = a, sb = b
	if(typeof(sa) == 'number') sa = sa + ''
	if(typeof(sb) == 'number') sb = sb + ''
	if(typeof(sa) == 'string' && typeof(sb) == 'string') {
		return sa + sb
	} else {
		if(typeof(sa) != 'string')
			throw new Error('attempt to concatenate a ' + exports.type(a) + ' value')
		else if(typeof(sb) != 'number')
			throw new Error('attempt to concatenate a ' + exports.type(b) + ' value')
		else
			throw new Error('bad')
	}
}

exports.concat = function*(a, b) {
	try {
		return exports.rawconcat(a, b)
	} catch(e) {
		var h = getbinhandler(a, b, '__concat')
		if(exports.type(h) != 'nil')
			return (yield* exports.call(h, [a, b]))[0]
		else
			throw e
	}
}

;[['lt', '<'], ['gt', '>']].forEach(function(v) {
	var name = v[0]
	var op = v[1]

	eval('exports.raw' + name + ' = function(a, b) {\n' +
	'\tvar ta = exports.type(a), tb = exports.type(b)\n' +
	'\tif(ta == tb && (ta == \'string\' || ta == \'number\')) {\n' +
	'\t\treturn a < b\n' +
	'\t} else {\n' +
	'\t\tif(ta == tb)\n' +
	'\t\t\tthrow new Error(\'attempt to compare two \' + ta + \' values\')\n' +
	'\t\telse\n' +
	'\t\t\tthrow new Error(\'attempt to compare \' + ta + \' with \' + tb)\n' +
	'\t}\n' +
	'}')

	eval('exports.' + name + ' = function*(a, b) {\n' +
	'\ttry {\n' +
	'\t\treturn exports.raw' + name + '(a, b)\n' +
	'\t} catch(e) {\n' +
	'\t	var h = getbinhandler(a, b, \'__' + name + '\')\n' +
	'\t	if(exports.type(h) != \'nil\')\n' +
	'\t		return (yield* exports.call(h, [a, b]))[0]\n' +
	'\t	else\n' +
	'\t		throw e\n' +
	'\t}\n' +
	'}')
})

exports.call = function*(self, args) {
	var type = exports.type(self)
	var mm, mmType
	if(type == 'function')
		return yield* self.apply(this, args)
	else if(type == 'table' && self.mt && exports.type(mm = yield* exports.get(self.mt, '__call')) == 'function')
		return yield* mm.apply(this, [self].concat(args))
	else
		throw new Error('attempt to call a ' + type + ' value')
}

exports._G = exports.table([], [])
exports.rawset(exports._G, 'print', function*() {
	for(var i = 0; i < arguments.length; i++) {
		console.log(arguments[i])
	}
})
