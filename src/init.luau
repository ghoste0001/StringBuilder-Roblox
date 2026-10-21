--!native
--!strict

--[[
	@module: StringBuilder
	@version: 1.2.0
	@author: Ghost (withoutruless)
	@description: Blazing-fast string builder library similar to C#, faster than Luau's native string concat.
	
	Nearly full coverage of StringBuilder's (C#) functions,
	memory efficient, powerful AND way faster than Roblox's string concatenation
	
	StringBuilder also supports being packed into a buffer that can be unpacked back into a StringBuilder object
	And supports compressing that said buffer for a smaller footprint (for datastores or sending over network)
	
	Inspired by depthso's original concept. 
	Remade from the ground up using buffers for maximum memory efficiency and feature compatibility.
	
	
	SOURCE: https://github.com/ghoste0001/StringBuilder-Roblox
	
	LICENSE: Source code is licensed under Eclipse Public License - v2.0
	
	THE ACCOMPANYING PROGRAM IS PROVIDED UNDER THE TERMS OF THIS ECLIPSE
	PUBLIC LICENSE ("AGREEMENT"). ANY USE, REPRODUCTION OR DISTRIBUTION
	OF THE PROGRAM CONSTITUTES RECIPIENT'S ACCEPTANCE OF THIS AGREEMENT.
]]

--[[ ## Example (Usable code) ##

    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local StringBuilder = require(ReplicatedStorage:WaitForChild("StringBuilder"))
    
    local textBuilder = StringBuilder.new() -- You can specify the builder's size in bytes if needed
    
    -- Right now the textBuilder is empty, but we can add some text to it:
    textBuilder:Append("Hello, World!")
    
    -- Now the textBuilder contains "Hello, World!", so if we do:
    print(textBuilder) -- or print(textBuilder:ToString())
    -- The output is going to be: "Hello, World!"
    
    -- Lets replace every occurrence of the word "World" with my name
    textBuilder:Replace("World", "Ghost")
    
    -- Now, if we print again:
    print(textBuilder)
    -- The output this time will be: "Hello, Ghost!"
    
    -- Also, instead of calling methods with ":" (like :Append()),
    -- we can call them directly like this:
    StringBuilder.Append(textBuilder, " Let's continue this string!")
    
    -- This avoids method call overhead, but is a bit less intuitive/readable
    -- So just pick your poison (very little overhead anyways)
    
    -- By the way, Append adds exactly what you give it
    -- It does NOT add spaces automatically
    -- Use " " manually or textBuilder:Space() if needed:
    
    textBuilder:Append(" <- Like this") -- space is included manually here
    textBuilder:Space() -- appends a space character
    textBuilder:Append("<- Or like this!") -- no need to add a space, Space() already handled it.
    
    -- StringBuilder also has chaining support:
    textBuilder:Append("Hello,"):Space():Append("Again!")
	print(textBuilder) -- output: "Hello, Again!"
]]

local EncodingService = game:GetService("EncodingService")
local StringBuilder = {}

local StringBuilderMeta = {
	__type = "StringBuilder",
	__index = StringBuilder,
}

--// Types

type StringBuilder = setmetatable<{
	_Buffer: buffer,
	_MaxCapacity: number,
	_Capacity: number,
	_Length: number,
}, typeof(StringBuilderMeta)>


--// Defaults
const COMPRESSION_ALGORITHM = Enum.CompressionAlgorithm.Zstd -- Default: Zstd (its the only one available)
const COMPRESSION_LEVEL = 0 -- Default: 0 (-7 to 22, higher = more compression at the cost of performance)
const DEFAULT_MAX_CAPACITY = 4*1024*1024 -- Default: 4*1024*1024 (byte > kilobyte > megabyte)
const DEFAULT_CAPACITY = 64 -- Default: 64 (In bytes)
const MIN_MAX_CAPACITY = 1 -- Default: 1 (In bytes)
const MIN_CAPACITY = 1 -- Default: 1 (In bytes)

--// Hard Values
const MAX_ROBLOX_BUFFER_SIZE = 1024*1024*1024 -- 1073741824 bytes (1GB), this is the max size a buffer in roblox can be.
const ERROR_LEVEL = 2

--/ Buffer related

--/ U8 values
const BUF_SPACE = 32 -- " "
const BUF_NEWLINE = 10 -- "\n"

--/ Compression values and offsets
const U16 = 2
const U32 = 4

const PACKED_BIT = 59371 -- Identifier to use for packed buffers (0-65535)
const PACKED_CAPACITY_OFFSET = U16
const PACKED_MAX_CAPACITY_OFFSET = PACKED_CAPACITY_OFFSET+U32
const PACKED_LENGTH_OFFSET = PACKED_MAX_CAPACITY_OFFSET+U32
const HEADER_SIZE = U16+U32+U32+U32

const MAX_SB_BUFFER_SIZE = MAX_ROBLOX_BUFFER_SIZE - HEADER_SIZE
--/ Print related
const PRINT_PREFIX = "[StringBuilder]: "

const builtin_error = error
const function error(message: any) builtin_error(PRINT_PREFIX..message, ERROR_LEVEL); end
-------------------------------------------


--[[
	Function for resizing the buffer if necessary.
	Errors if the resize fails (e.g., hits MaxCapacity limit).
]]
local function ResizeBuffer(self: StringBuilder, newLength: number)
	local currentCapacity = self._Capacity

	if newLength <= currentCapacity then return true end

	local targetCapacity = math.max(currentCapacity * 2, newLength + DEFAULT_CAPACITY)
	targetCapacity = math.min(targetCapacity, self._MaxCapacity)

	if targetCapacity < newLength then
		error("buffer resize failed. requested="..newLength..", max="..self._MaxCapacity)
	end

	local oldBuf = self._Buffer
	local newBuf = buffer.create(targetCapacity)

	buffer.copy(newBuf, 0, oldBuf, 0, self._Length)

	self._Buffer = newBuf
	self._Capacity = targetCapacity

	return true
end

-------------------------------------------

--[[
	Returns a new StringBuilder object.
]]
function StringBuilder.new(Capacity: number?, MaxCapacity: number?): StringBuilder
	Capacity = Capacity or DEFAULT_CAPACITY
	MaxCapacity = MaxCapacity or DEFAULT_MAX_CAPACITY
	if Capacity % 1 ~= 0 then
        error("new: invalid Capacity!")
    end
	if MaxCapacity % 1 ~= 0 then
        error("new: invalid MaxCapacity!")
    end
	Capacity = math.clamp(Capacity, MIN_CAPACITY, MAX_SB_BUFFER_SIZE)
	MaxCapacity = math.max(MIN_MAX_CAPACITY, Capacity, MaxCapacity)
	MaxCapacity = math.min(MaxCapacity, MAX_SB_BUFFER_SIZE)

	return setmetatable({
		_Buffer = buffer.create(Capacity),
		_MaxCapacity = MaxCapacity,
		_Capacity = Capacity,
		_Length = 0,
	},StringBuilderMeta)
end

--[[
    Function for packing data and metadata together into a buffer.
    Metadata: Capacity, MaxCapacity, Length
    Mostly for compression internally but its here if you want it.
    This is the layout for the buffer:
	
    [ID][CAPACITY][MAX_CAPACITY][LENGTH][STRING]
    In data types: [U16][U32][U32][U32][STRING]
]]
function StringBuilder.Pack(self: StringBuilder): buffer
	local dataSize = self._Length

	local out = buffer.create(HEADER_SIZE + dataSize)

	buffer.writeu16(out, 0, PACKED_BIT) -- Id is always at 0 offset
	buffer.writeu32(out, PACKED_CAPACITY_OFFSET, self._Capacity)
	buffer.writeu32(out, PACKED_MAX_CAPACITY_OFFSET, self._MaxCapacity)
	buffer.writeu32(out, PACKED_LENGTH_OFFSET, self._Length)

	buffer.copy(out, HEADER_SIZE, self._Buffer, 0, dataSize)

	return out
end

--[[
    Returns a StringBuilder object from a compressed (or packed) StringBuilder.
	nil if the given buffer is not a StringBuilder.
]]
function StringBuilder.FromBuffer(data: buffer): StringBuilder?
	if not data then return end
	local decompressed;
	local compressedLength = EncodingService:GetDecompressedBufferSize(data, COMPRESSION_ALGORITHM)
	if not compressedLength then
		decompressed = data
	else
		local success, newdata = pcall(EncodingService.DecompressBuffer, EncodingService, data, COMPRESSION_ALGORITHM)
		if not success then return end
		decompressed = newdata
	end
	local buflen = buffer.len(decompressed)
	if buflen < HEADER_SIZE then return end
	if buflen > MAX_ROBLOX_BUFFER_SIZE then return end

	local identifier = buffer.readu16(decompressed,0)
	if identifier ~= PACKED_BIT then return end
	-- The ID matches our global packed_bit, so this is a valid buffer.

	local capacity = buffer.readu32(decompressed, PACKED_CAPACITY_OFFSET)
	local maxCapacity = buffer.readu32(decompressed, PACKED_MAX_CAPACITY_OFFSET)
	local length = buffer.readu32(decompressed, PACKED_LENGTH_OFFSET)

	if capacity < MIN_CAPACITY then
		error("FromBuffer: malformed buffer, capacity cant be less than MIN_CAPACITY!")
	elseif capacity > MAX_SB_BUFFER_SIZE then
		error("FromBuffer: malformed buffer, capacity cant be more than MAX_SB_BUFFER_SIZE!")
	end
	if maxCapacity < MIN_MAX_CAPACITY then
		error("FromBuffer: malformed buffer, maxCapacity cant be less than MIN_MAX_CAPACITY!")
	elseif maxCapacity > MAX_SB_BUFFER_SIZE then
		error("FromBuffer: malformed buffer, maxCapacity cant be more than MAX_SB_BUFFER_SIZE!")
	end
	if length > MAX_SB_BUFFER_SIZE then
		error("FromBuffer: malformed buffer, length cant be more than MAX_SB_BUFFER_SIZE!")
	end

	-- More if statements to block garbage buffers
	if length > capacity then return end
	if capacity > maxCapacity then return end
	if HEADER_SIZE + length ~= buflen then return end

	local self = StringBuilder.new(capacity, maxCapacity)
	self._Length = length
	buffer.copy(self._Buffer, 0, decompressed, HEADER_SIZE, length)

	return self
end

--[[
    Compresses the StringBuilder with the default compression algorithm
    Higher CompressionLevel = more compression at the cost of more time
    CompressionLevel is optional and must range from (-7 to 22)
    Returns a packed and compressed StringBuilder (as a buffer)
]]
function StringBuilder.Compress(self: StringBuilder, CompressionLevel: number?): buffer
	local packed = StringBuilder.Pack(self)
	local success, compressed = pcall(EncodingService.CompressBuffer, EncodingService, packed, COMPRESSION_ALGORITHM, CompressionLevel or COMPRESSION_LEVEL)
	if not success then
		return packed
	end
	-- Lets not return a bigger buffer than the original
	if buffer.len(compressed) < buffer.len(packed) then
		return compressed
	else
		return packed
	end
end

--[[
	Returns the capacity (in bytes)
	(self._Capacity)
]]
function StringBuilder.GetCapacity(self: StringBuilder): number
	return self._Capacity
end

--[[
	Returns the max capacity (in bytes)
	(self._MaxCapacity)
]]
function StringBuilder.GetMaxCapacity(self: StringBuilder): number
	return self._MaxCapacity
end

--[[
	Returns available writable space in bytes.
	(self._Capacity - self._Length)
]]
function StringBuilder.GetFreeSpace(self: StringBuilder): number
	return self._Capacity - self._Length
end

--[[
	Returns max writable space in bytes.
	(self._MaxCapacity - self._Length)
]]
function StringBuilder.GetTotalFreeSpace(self: StringBuilder): number
	return self._MaxCapacity - self._Length
end

--[[
	Returns how many more bytes the capacity can grow by.
	(self._MaxCapacity - self._Capacity)
]]
--function StringBuilder.GetExpansionRoom(self: StringBuilder): number
--	return self._MaxCapacity - self._Capacity
--end

--[[
    Compares 2 StringBuilders
    Returns true if their contents are matching
]]
function StringBuilder.Compare(self: StringBuilder, self2: StringBuilder): boolean
	if not self or not self2 then return false end
	local length = self._Length
	if length ~= self2._Length then return false end
	if rawequal(self, self2) then return true end

	local buf1 = self._Buffer
	local buf2 = self2._Buffer
	local cursor = 0

	-- Main loop (reading 4 bytes at a time)
	local u32_Limit = length // 4 -- ("//" op divides and rounds down)
	for _ = 1, u32_Limit do
		if buffer.readu32(buf1, cursor) ~= buffer.readu32(buf2, cursor) then 
			return false 
		end
		cursor += 4
	end
	-- reading 2 bytes
	if (length - cursor) >= 2 then
		if buffer.readu16(buf1, cursor) ~= buffer.readu16(buf2, cursor) then
			return false
		end
		cursor += 2
	end
	-- reading the last byte
	if (length - cursor) == 1 then
		if buffer.readu8(buf1, cursor) ~= buffer.readu8(buf2, cursor) then
			return false
		end
	end

	return true
end

--[[
    Get specific character(s) starting from index
    By default, returns a single character at the given index.
    Count is optional (default: 1) and can be positive or negative.
    (Returned string won't be reversed by a negative Count)
]]
function StringBuilder.GetCharacters(self: StringBuilder, Index: number, Count: number?): string
    Count = Count or 1
	
	if Index % 1 ~= 0 or Count % 1 ~= 0 then
        error("GetCharacters: invalid Index!")
    end
	
	local Length = self._Length
    local EndIndex = Index + Count

    if Index < 0 or Index > Length or EndIndex < 0 or EndIndex > Length then
        error("GetCharacters: access out of bounds!")
    end

    if Count == 0 then
        return ""
    end

    return buffer.readstring(self._Buffer, math.min(Index, EndIndex), math.abs(Count))
end

--[[
    Set character(s) starting from index
    Data can be a string or any tostring convertable type
]]
function StringBuilder.SetCharacters(self: StringBuilder, Index: number, Data: any): StringBuilder
	if not Index or Data == nil then
		return self
	end
	Data = tostring(Data)
	if Data == "" then return self end

    if Index < 0 or Index % 1 ~= 0 then
        error("SetCharacters: invalid Index!")
    end

	local Count = #Data
	local newLength = Index + Count
	local oldLength = self._Length

	if newLength > self._Capacity then
		ResizeBuffer(self, newLength)
	end

	if Index > oldLength then
		buffer.fill(self._Buffer, oldLength, 0, Index - oldLength)
	end

	buffer.writestring(self._Buffer, Index, Data, Count)

	if newLength > oldLength then
		self._Length = newLength
	end

	return self
end

--[[
    Ensures that the buffer is at least the given Capacity
    Resizes the buffer if needed.
    Returns: success, capacity
]]
function StringBuilder.EnsureCapacity(self: StringBuilder, EnsuredCapacity: number): (boolean, number)
	if not EnsuredCapacity or EnsuredCapacity < 0
		or EnsuredCapacity > self._MaxCapacity or EnsuredCapacity % 1 ~= 0 then
        error("EnsureCapacity: invalid EnsuredCapacity!")
    end
	local success = pcall(ResizeBuffer, self, EnsuredCapacity)

	return success and EnsuredCapacity <= self._Capacity, self._Capacity
end

--[[
	Manually and safely set the capacity.
	Resizes the buffer (out of bounds data gets cut off)
	Returns the new real capacity (capped by MaxCapacity and the default MIN_CAPACITY)
]]
function StringBuilder.SetCapacity(self: StringBuilder, Capacity: number): number
	if not Capacity then return self._Capacity end

	if Capacity % 1 ~= 0 then
        error("SetCapacity: invalid Capacity!")
    end
	Capacity = math.clamp(Capacity, MIN_CAPACITY, MAX_SB_BUFFER_SIZE)
	Capacity = math.min(Capacity, self._MaxCapacity)

	if self._Capacity == Capacity then return Capacity end

	local oldBuf = self._Buffer
	local newBuffer = buffer.create(Capacity)

	local copyCount = math.min(self._Length, Capacity)
	buffer.copy(newBuffer, 0, oldBuf, 0, copyCount)

	self._Buffer = newBuffer
	self._Capacity = Capacity
	self._Length = copyCount
	return Capacity
end

--[[
	Manually set the max capacity (safely).
	Throws an error if MaxCapacity is less than self._Capacity.
]]
function StringBuilder.SetMaxCapacity(self: StringBuilder, MaxCapacity: number)
	if not MaxCapacity or MaxCapacity % 1 ~= 0 then
        error("SetMaxCapacity: invalid MaxCapacity!")
    end
	if MaxCapacity < self._Capacity then
		error("SetMaxCapacity: MaxCapacity cant be less than Capacity!")
	end
	if MaxCapacity < MIN_MAX_CAPACITY then return end
	MaxCapacity = math.min(MaxCapacity, MAX_SB_BUFFER_SIZE)

	self._MaxCapacity = MaxCapacity
end

-- Returns the current length of the string in bytes
function StringBuilder.GetLength(self: StringBuilder): number
	return self._Length
end

--[[
    Manually sets the length of the string.
    If smaller, it instantly truncates the string.
    If larger than (self._Capacity), it forces a buffer expansion.
    Returns self.
	Throws an error if passed length is higher than MaxCapacity, or not a whole number.
]]
function StringBuilder.SetLength(self: StringBuilder, Length: number): StringBuilder
	if not Length or Length < 0 or Length > self._MaxCapacity or Length % 1 ~= 0 then
		error("SetLength: invalid Length!")
	end

	if Length > self._Capacity then
		ResizeBuffer(self, Length)
	end
	local oldLength = self._Length

	-- clear any old data if the set length is higher than the old length.
	if Length > oldLength then
		buffer.fill(self._Buffer, oldLength, 0, Length - oldLength)
	end

	self._Length = Length
	return self
end

--[[
    Appends any tostring() convertable data at the end.
	nil is ignored; use tostring(nil) to append the literal "nil".
]]
function StringBuilder.Append(self: StringBuilder, Data: any): StringBuilder
	if Data == nil then return self end
	if type(Data) ~= "string" then
		Data = tostring(Data)
	end
	local dataSize = #Data
	if dataSize == 0 then return self end

	local currentLength = self._Length
	local newLength = currentLength + dataSize

	if newLength > self._Capacity then
		ResizeBuffer(self, newLength)
	end

	buffer.writestring(self._Buffer, currentLength, Data, dataSize)
	self._Length = newLength
	return self
end

--[[
    same as StringBuilder.Append except adds a line terminator at the end.
    (appends and creates a new line using "\n")
]]
function StringBuilder.AppendLine(self: StringBuilder, Data: any?): StringBuilder
	StringBuilder.Append(self, Data)
	StringBuilder.Newline(self)
	return self
end

--[[
    same as StringBuilder.Append except with formatting.
]]
function StringBuilder.AppendFormat(self: StringBuilder, Format: string, ...): StringBuilder
	if Format then
		local Data = string.format(Format, ...)
		StringBuilder.Append(self, Data)
	end
	return self
end

--[[
    Concatenates and appends provided arguments.
    Way faster than chained appends, but it only supports strings and numbers.
    Will error if anything else is provided (and not return self as a result)
]]
function StringBuilder.AppendList(self: StringBuilder, ...): StringBuilder
	local str = table.concat({...})
	local len = #str
	if len == 0 then return self end

	local pos = self._Length
	local newPos = pos + len

	if newPos > self._Capacity then
		ResizeBuffer(self, newPos)
	end

	buffer.writestring(self._Buffer, pos, str, len)
	self._Length = newPos
	return self
end

--[[
    Concatenates an array of strings and numbers, 
    placing a specific separator between each one (like commas).
]]
function StringBuilder.AppendJoin(self: StringBuilder, Data: {any?}, Separator: string?): StringBuilder
	if not Data or #Data == 0 then return self end
	local str = table.concat(Data,Separator)
	local len = #str
	local pos = self._Length
	local newPos = pos + len

	if newPos > self._Capacity then
		ResizeBuffer(self, newPos)
	end

	buffer.writestring(self._Buffer, pos, str, len)
	self._Length = newPos
	return self
end

--[[
    Removes [Count] amount of letters starting from index
	Count is optional (default: 1)
]]
function StringBuilder.Remove(self: StringBuilder, Index: number, Count: number?): StringBuilder
	local Length = self._Length
	if not Index or Index < 0 or Index >= Length or Index % 1 ~= 0 then
        error("Remove: invalid Index!")
    end
	Count = Count or 1
	if Count < 0 or Count % 1 ~= 0 then
        error("Remove: invalid Count!")
    end
	if Count == 0 then return self end

	-- So we dont try to remove more characters than exist after the index
	if Count > Length - Index then
		error("Remove: end index out of bounds!")
	end

	local moveSource = Index + Count
	local bytesToMove = Length - moveSource

	if bytesToMove > 0 then
		-- We shift the buffer down
		buffer.copy(self._Buffer, Index, self._Buffer, moveSource, bytesToMove)
	end

	self._Length -= Count
	return self
end

--[[
    Reverses the string using raw buffer functions
    just as accurate as Reverse() in english letters 
    but lacks emoji and other language reversal support
    also faster than Reverse
]]
function StringBuilder.ReverseBytes(self: StringBuilder): StringBuilder
	local length = self._Length
	if length <= 1 then return self end

	-- Iterate half-way
	for i = 0, math.floor(length * 0.5) - 1 do
		local leftIndex = i
		local rightIndex = length - 1 - i

		-- Read bytes
		local leftByte = buffer.readu8(self._Buffer, leftIndex)
		local rightByte = buffer.readu8(self._Buffer, rightIndex)

		-- Swap them
		buffer.writeu8(self._Buffer, leftIndex, rightByte)
		buffer.writeu8(self._Buffer, rightIndex, leftByte)
	end

	return self
end

--[[
    Reverses the string using utf8.graphemes
    slower than ReverseBytes() but is the default as it has emoji and multi-language support
]]
function StringBuilder.Reverse(self: StringBuilder): StringBuilder
	local length = self._Length
	if length <= 1 then return self end

	local baseString = buffer.readstring(self._Buffer, 0, length)
	local newBuf = buffer.create(self._Capacity)
	local writeCursor = 0

	-- Only requires size of 'length', saving massive table space
	local endpoints = table.create(length) :: {number}
	local count = 0

	for _, endPos in utf8.graphemes(baseString) do
		count += 1
		endpoints[count] = endPos
	end

	-- Process backward using math to extract the lengths dynamically
	for i = count, 1, -1 do
		local currentEnd = endpoints[i]
		local prevEnd = i > 1 and endpoints[i - 1] or 0
		
		local cLen = currentEnd - prevEnd
		local sourceStart = prevEnd -- 0-based index match

		buffer.copy(newBuf, writeCursor, self._Buffer, sourceStart, cLen)
		writeCursor += cLen
	end

	self._Buffer = newBuf
	return self
end

--[[
	Inserts data at the given index and pushes the rest to the right.
	Errors if there's not enough available max capacity, or if the data can't fit.
]]
function StringBuilder.Insert(self: StringBuilder, Index: number, Data: any): StringBuilder
	if not Index or Index < 0 or Index > self._Length or Index % 1 ~= 0 then
		error("Insert: invalid Index!")
	end
	if Data == nil then return self end
	if type(Data) ~= "string" then
		Data = tostring(Data)
	end
	
	local DataSize = #Data
	if DataSize == 0 then return self end
	local AvailableSpace = self._MaxCapacity - self._Length

	-- Capacity check
	if AvailableSpace < 1 then
		error("Insert: no available space!")
	end
	if DataSize > AvailableSpace then
		error("Insert: data cant fully fit!")
	end

	local newLength = self._Length + DataSize

	if newLength > self._Capacity then
		ResizeBuffer(self, newLength)
	end

	local bytesToMove = self._Length - Index
	if bytesToMove > 0 then
		buffer.copy(self._Buffer, Index + DataSize, self._Buffer, Index, bytesToMove)
	end
	-- Write the new text (clamped by DataSize)
	buffer.writestring(self._Buffer, Index, Data, DataSize)

	self._Length = newLength

	return self
end

--[[
	Looks for the first match of target in the StringBuilder
	returns the indices of the string where the occurrence starts and ends.
]]
function StringBuilder.Find(self: StringBuilder, target: string, start: number?): (number?, number?)
	const length = self._Length
	if start then
		if start < 0 or start > length or start % 1 ~= 0 then
			error("Find: invalid start!")
		end
	else start = 0 end
	const targetLength = #target
	if targetLength == 0 then return end
	const buf = self._Buffer

	local pbytes = table.create(targetLength)
	for i = 0, targetLength - 1 do
		pbytes[i] = string.byte(target, i + 1)
	end

	-- special fast cases for 1 & 2 byte string searches
	if targetLength == 1 then
		local byte = pbytes[0]
		for i = math.max(0, start or 0), length - 1 do
			if buffer.readu8(buf, i) == byte then
				return i, i + 1
			end
		end
		return
	elseif targetLength == 2 then
		local b0, b1 = pbytes[0], pbytes[1]
		local limit = length - 2
		for i = math.max(0, start or 0), limit do
			if buffer.readu8(buf, i) == b0
				and buffer.readu8(buf, i + 1) == b1 then
				return i, i + 2
			end
		end
		return
	end

	local lps = table.create(targetLength, 0)
	local len = 0
	local i = 1

	while i < targetLength do
		if pbytes[i] == pbytes[len] then
			len += 1
			lps[i + 1] = len
			i += 1
		elseif len ~= 0 then
			len = lps[len]
		else
			lps[i + 1] = 0
			i += 1
		end
	end

	i = math.max(0, start or 0)
	local j = 0

	while i < length do
		if pbytes[j] == buffer.readu8(buf, i) then
			i += 1
			j += 1
			if j == targetLength then
				local startIdx = i - j
				return startIdx, startIdx + targetLength
			end
		elseif j ~= 0 then
			j = lps[j]
		else
			i += 1
		end
	end

	return
end

--[[
	Looks for the first match of target in the StringBuilder
	returns the indices of the string where the occurrence starts and ends.

	Wrapper for string.find which is way faster than Find()
	plain defaults to true unless set otherwise.

	Note:
    To use string.find, this first converts the buffer into a 
	temporary string that's (self._Length) bytes, adding to GC pressure.
    Use sparingly with large StringBuilders or frequent calls.
]]
function StringBuilder.FindNative(self: StringBuilder, pattern: string, start: number?, plain: boolean?): (number?, number?)
	const length = self._Length
	if start then
		if start < 0 or start > length or start % 1 ~= 0 then
			error("FindNative: invalid start!")
		end
	else start = 0 end
	if pattern == "" then return end
	local sIdx, eIdx = string.find(buffer.readstring(self._Buffer, start, length - start), pattern, 0, plain == nil and true or plain)
	if sIdx then
		return sIdx + start - 1, eIdx + start
	end
	return
end

--[[
	Replaces all occurences of [target] with [replacement] from [start].
]]
function StringBuilder.Replace(self: StringBuilder, target: string, replacement: string, start: number?): StringBuilder
	if type(target) ~= "string" then error("Replace: target is not a string!") end
	if type(replacement) ~= "string" then error("Replace: replacement is not a string!") end
	const length = self._Length
	if start then
		if start < 0 or start > length or start % 1 ~= 0 then
			error("Replace: invalid start!")
		end
	else start = 0 end
	if target == replacement then return self end

	local targetLength = #target
	if length == 0 or targetLength == 0 then return self end

	local lps = table.create(targetLength, 0)
	local pbytes = table.create(targetLength)
	for i = 0, targetLength - 1 do
		pbytes[i] = string.byte(target, i + 1)
	end

	local buf = self._Buffer
	local starts = {}
	local count = 0
	local len = 0
	local i = 1
	local j = 0

	while i < targetLength do
		if pbytes[i] == pbytes[len] then
			len += 1
			lps[i + 1] = len
			i += 1
		elseif len ~= 0 then
			len = lps[len]
		else
			lps[i + 1] = 0
			i += 1
		end
	end

	i = start
	while i < length do
		if pbytes[j] == buffer.readu8(buf, i) then
			i += 1
			j += 1
			if j == targetLength then
				count += 1
				starts[count] = i - targetLength
				j = 0
			end
		elseif j ~= 0 then
			j = lps[j]
		else
			i += 1
		end
	end

	if count == 0 then return self end

	local replacementLength = #replacement
	local newLength = length + count * (replacementLength - targetLength)
	if newLength > self._MaxCapacity then
		error("Replace: result exceeds MaxCapacity!")
	end
	local newCapacity = math.max(newLength, self._Capacity)
	local destBuf = buffer.create(newCapacity)
	local readCursor = 0
	local writeCursor = 0

	for idxCount = 1, count do
		local startPos = starts[idxCount]
		local segmentLength = startPos - readCursor

		if segmentLength > 0 then
			buffer.copy(destBuf, writeCursor, buf, readCursor, segmentLength)
			writeCursor += segmentLength
		end

		if replacementLength > 0 then
			buffer.writestring(destBuf, writeCursor, replacement, replacementLength)
			writeCursor += replacementLength
		end

		readCursor = startPos + targetLength
	end

	local remaining = length - readCursor
	if remaining > 0 then
		buffer.copy(destBuf, writeCursor, buf, readCursor, remaining)
	end

	self._Buffer = destBuf
	self._Length = newLength
	self._Capacity = newCapacity

	return self
end

--[[
	Appends a space (" ") at the end.
]]
function StringBuilder.Space(self: StringBuilder): StringBuilder
	local pos = self._Length
	local newPos = pos+1
	if newPos > self._Capacity then
		ResizeBuffer(self, newPos)
	end
	buffer.writeu8(self._Buffer,pos,BUF_SPACE)
	self._Length = newPos
	return self
end

--[[
	Appends a newline ("\n") at the end.
]]
function StringBuilder.Newline(self: StringBuilder): StringBuilder
	local pos = self._Length
	local newPos = pos+1
	if newPos > self._Capacity then
		ResizeBuffer(self, newPos)
	end
	buffer.writeu8(self._Buffer,pos,BUF_NEWLINE)
	self._Length = newPos
	return self
end

--[[
	Returns the fully built string.
]]
function StringBuilder.ToString(self: StringBuilder): string
	return buffer.readstring(self._Buffer,0,self._Length)
end

--[[
	Clears the buffer (Or more accurately, it resets the end cursor).
	Basically free to call.
]]
function StringBuilder.Clear(self: StringBuilder): StringBuilder
	self._Length = 0
	return self
end

--[[
	Destroys the StringBuilder object.
]]
function StringBuilder.Destroy(self: StringBuilder)
	-- Leaves the Buffer to be cleaned up by the gc automatically.
	-- (Theres no way to do it manually).
	table.clear(self)
	setmetatable(self,nil)
end


-- Hidden Metamethods:

--[[
	For calling print(StringBuilder) or tostring(StringBuilder)
	Instead of StringBuilder:tostring() or StringBuilder.tostring(builder)
]]
function StringBuilderMeta.__tostring(self: StringBuilder): string
	return buffer.readstring(self._Buffer,0,self._Length)
end

-- Allow using == operator on StringBuilders
StringBuilderMeta.__eq = StringBuilder.Compare

return StringBuilder
