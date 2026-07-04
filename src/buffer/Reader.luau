--!strict
--!native
--!optimize 2

-- Cursor-based binary reader over Luau's `buffer` type. Mirrors Writer's
-- encoding exactly (see Writer.luau for format notes).

local len = buffer.len
local readu8 = buffer.readu8
local readu16 = buffer.readu16
local readu32 = buffer.readu32
local readi8 = buffer.readi8
local readi16 = buffer.readi16
local readi32 = buffer.readi32
local readf32 = buffer.readf32
local readf64 = buffer.readf64
local readstring = buffer.readstring

type Internal = {
	_buf: buffer,
	_pos: number,
	_len: number,
}

local Reader = {}
Reader.__index = Reader

export type Reader = typeof(setmetatable({} :: Internal, Reader))

function Reader.new(data: buffer, length: number?): Reader
	return setmetatable({
		_buf = data,
		_pos = 0,
		_len = length or len(data),
	}, Reader)
end

function Reader.u8(self: Reader): number
	local v = readu8(self._buf, self._pos)
	self._pos += 1
	return v
end

function Reader.u16(self: Reader): number
	local v = readu16(self._buf, self._pos)
	self._pos += 2
	return v
end

function Reader.u32(self: Reader): number
	local v = readu32(self._buf, self._pos)
	self._pos += 4
	return v
end

function Reader.i8(self: Reader): number
	local v = readi8(self._buf, self._pos)
	self._pos += 1
	return v
end

function Reader.i16(self: Reader): number
	local v = readi16(self._buf, self._pos)
	self._pos += 2
	return v
end

function Reader.i32(self: Reader): number
	local v = readi32(self._buf, self._pos)
	self._pos += 4
	return v
end

function Reader.f32(self: Reader): number
	local v = readf32(self._buf, self._pos)
	self._pos += 4
	return v
end

function Reader.f64(self: Reader): number
	local v = readf64(self._buf, self._pos)
	self._pos += 8
	return v
end

function Reader.bool(self: Reader): boolean
	local v = readu8(self._buf, self._pos)
	self._pos += 1
	return v ~= 0
end

function Reader.varint(self: Reader): number
	local buf = self._buf
	local pos = self._pos
	local result = 0
	local shift = 1
	local terminated = false
	for _ = 1, 5 do
		local byte = readu8(buf, pos)
		pos += 1
		result += (byte % 128) * shift
		if byte < 128 then
			terminated = true
			break
		end
		shift *= 128
	end
	assert(terminated, "Reader.varint: malformed varint (too many bytes / not terminated)")
	self._pos = pos
	return result
end

function Reader.varintSigned(self: Reader): number
	local zigzag = self:varint()
	local half = zigzag // 2
	if zigzag % 2 == 0 then
		return half
	else
		return -half - 1
	end
end

function Reader.string(self: Reader): string
	local n = self:varint()
	local v = readstring(self._buf, self._pos, n)
	self._pos += n
	return v
end

-- Reads raw bytes without a length prefix; caller supplies the length.
function Reader.bytes(self: Reader, length: number): buffer
	local out = buffer.create(length)
	buffer.copy(out, 0, self._buf, self._pos, length)
	self._pos += length
	return out
end

function Reader.pos(self: Reader): number
	return self._pos
end

function Reader.remaining(self: Reader): number
	return self._len - self._pos
end

return Reader
