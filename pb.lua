-- Copyright (c) 2010-2011 by Robert G. Jakabosky <bobby@neoawareness.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

local io = io
local fopen = io.open
local assert = assert
local sformat = string.format
local print = print

local dir_sep = package.config:sub(1,1)
local path_sep = package.config:sub(3,3)
local path_mark = package.config:sub(5,5)
local path_match = "([^" .. path_sep .. "]*)" .. path_sep

local default_proto_path = ''
-- Use modified 'package.path' as search path for .poto files.
if package and package.path then
	-- convert '.lua' -> '.proto'
	for path in package.path:gmatch(path_match) do
		-- don't include "*/init.lua" paths
		if not path:match("init.lua$") then
			path = path:gsub('\.lua$','\.proto')
			default_proto_path = default_proto_path .. path .. ';'
		end
	end
else
	default_proto_path = '.' .. dir_sep .. path_mark .. '.proto;'
end

local mod_name = ...

local parser = require(mod_name .. ".proto.parser")

-- backend cache.
local backends = {}
local default_backend = 'standard'

local function new_backend(name, compile, encode, decode)
	local backend = {compile = compile, encode = encode, decode = decode, cache = {}}
	backends[name] = backend
	return backend
end

local function get_backend(name)
	name = name or default_backend
	backend = backends[name]
	if not backend then
		-- load new backend
		local mod = require(mod_name .. '.' .. name)
		backend = new_backend(name, mod.compile, mod.encode, mod.decode)
	end
	return backend
end

local function find_proto(name, search_path)
	local err_list = ''
	-- convert dotted name to directory path.
	name = name:gsub('%.', dir_sep)
	-- try each path in search path.
	for path in search_path:gmatch(path_match) do
		local fname = path:gsub(path_mark, name)
		local file, err = fopen(fname)
		-- return opened file
		if file then return file end
		-- append error and continue
		err_list = err_list .. sformat("\n\tno file %q", fname)
	end
	return nil, err_list
end

local function proto_file_to_name(file)
	local name = file:gsub("%.proto$", '')
	return name:gsub('/', '.')
end

module(...)

-- .proto search path.
_M.path = default_proto_path

_M.new_backend = new_backend

function set_default_backend(name)
	local old = default_backend
	-- test backend
	assert(get_backend(name) ~= nil)
	default_backend = name
	return old
end

function load_proto(text, backend, require)
	local b = get_backend(backend)

	-- parse .proto into AST tree
	local ast = parser.parse(text)

	-- process imports
	local imports = ast.imports
	if imports then
		require = require or _M.require
		for i=1,#imports do
			local import = imports[i]
			local name = proto_file_to_name(import.file)
			import.name = name
			-- recurively load imports.
			import.proto = require(name, backend)
		end
	end

	-- compile AST tree into Message definitions
	return b.compile(ast)
end

local loading = "loading...."
function require(name, backend)
	local b = get_backend(backend)
	-- check cache for compiled .proto
	local proto = b.cache[name]
	assert(proto ~= loading, "Import loop!")
	-- return compiled .proto, if cached
	if proto then return proto end

	-- Use sentinel mark in cache. (to detect import loops).
	b.cache[name] = loading

	-- load .proto file.
	local f=assert(find_proto(name, _M.path))
	local text = f:read("*a")
	f:close()

	-- compile AST tree into Message definitions
	proto = load_proto(text, backend, require)

	-- cache compiled .proto
	b.cache[name] = proto
	return proto
end

function encode(msg)
	local encode_msg = msg['.encode']
	return encode_msg(msg)
end

-- Raw Message for Raw decoding.
local raw

function decode(msg, data)
	if not msg then
		if not raw then
			-- need to load Raw message definition.
			local proto = load_proto("message Raw {}")
			raw = proto.Raw
		end
		-- Raw message decoding
		msg = raw()
	end
	local decode_msg = msg['.decode']
	return decode_msg(msg, data)
end
