--!strict
--!native
--!optimize 2

-- Growable binary writer over Luau's `buffer` type. Capacity doubles on
-- overflow instead of reallocating per-write, so appends are amortized O(1).

local create = buffer.create
local len = buffer.len
local copy = buffer.copy
local writeu8 = buffer.writeu8
local writeu16 = buffer.writeu16
local writeu32 = buffer.writeu32
local writei8 = buffer.writei8
local writei16 = buffer.writei16
local writei32 = buffer.writei32
local writef32 = buffer.writef32
local writef64 = buffer.writef64
local writestring = buffer.writestring

local DEFAULT_CAPACITY = 64

type Internal = {
	_buf: buffer,
	_len: number,
	_cap: number,
}

local Writer = {}
Writer.__index = Writer

export type Writer = typeof(setmetatable({} :: Internal, Writer))

function Writer.new(initialCapacity: number?): Writer
	local cap = initialCapacity or DEFAULT_CAPACITY
	return setmetatable({
		_buf = create(cap),
		_len = 0,
		_cap = cap,
	}, Writer)
end

local function reserve(self: Writer, extra: number)
	local required = self._len + extra
	local cap = self._cap
	if required <= cap then
		return
	end
	repeat
		cap *= 2
	until cap >= required
	local newBuf = create(cap)
	copy(newBuf, 0, self._buf, 0, self._len)
	self._buf = newBuf
	self._cap = cap
end

function Writer.u8(self: Writer, value: number)
	reserve(self, 1)
	writeu8(self._buf, self._len, value)
	self._len += 1
end

function Writer.u16(self: Writer, value: number)
	reserve(self, 2)
	writeu16(self._buf, self._len, value)
	self._len += 2
end

function Writer.u32(self: Writer, value: number)
	reserve(self, 4)
	writeu32(self._buf, self._len, value)
	self._len += 4
end

function Writer.i8(self: Writer, value: number)
	reserve(self, 1)
	writei8(self._buf, self._len, value)
	self._len += 1
end

function Writer.i16(self: Writer, value: number)
	reserve(self, 2)
	writei16(self._buf, self._len, value)
	self._len += 2
end

function Writer.i32(self: Writer, value: number)
	reserve(self, 4)
	writei32(self._buf, self._len, value)
	self._len += 4
end

function Writer.f32(self: Writer, value: number)
	reserve(self, 4)
	writef32(self._buf, self._len, value)
	self._len += 4
end

function Writer.f64(self: Writer, value: number)
	reserve(self, 8)
	writef64(self._buf, self._len, value)
	self._len += 8
end

function Writer.bool(self: Writer, value: boolean)
	reserve(self, 1)
	writeu8(self._buf, self._len, if value then 1 else 0)
	self._len += 1
end

-- Unsigned LEB128. Small values (the common case for ids/counts/indices)
-- cost a single byte.
function Writer.varint(self: Writer, value: number)
	assert(value >= 0 and value < math.huge, "value must be a non-negative finite number")
	reserve(self, 10)
	local buf = self._buf
	local pos = self._len
	local v = value
	while true do
		local byte = v % 128
		v = (v - byte) // 128
		if v > 0 then
			writeu8(buf, pos, byte + 128)
			pos += 1
		else
			writeu8(buf, pos, byte)
			pos += 1
			break
		end
	end
	self._len = pos
end

-- Zigzag-encoded signed varint, for values centered around zero (deltas).
function Writer.varintSigned(self: Writer, value: number)
	local zigzag = if value >= 0 then value * 2 else -value * 2 - 1
	self:varint(zigzag)
end

function Writer.string(self: Writer, value: string)
	local n = #value
	reserve(self, 10 + n)
	local buf = self._buf
	local pos = self._len
	local v = n
	while true do
		local byte = v % 128
		v = (v - byte) // 128
		if v > 0 then
			writeu8(buf, pos, byte + 128)
			pos += 1
		else
			writeu8(buf, pos, byte)
			pos += 1
			break
		end
	end
	writestring(buf, pos, value, n)
	self._len = pos + n
end

-- Writes raw bytes without a length prefix (caller tracks length via schema).
function Writer.bytes(self: Writer, data: buffer, length: number?)
	local n = length or len(data)
	reserve(self, n)
	copy(self._buf, self._len, data, 0, n)
	self._len += n
end

function Writer.len(self: Writer): number
	return self._len
end

function Writer.toBuffer(self: Writer): buffer
	local out = create(self._len)
	copy(out, 0, self._buf, 0, self._len)
	return out
end

function Writer.toString(self: Writer): string
	return buffer.readstring(self._buf, 0, self._len)
end

return Writer
