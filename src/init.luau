--!native
--!strict

--[[
	@module: StringBuilder
	@version: 1.1.1
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
const function errorfmt(format: string, ...) builtin_error(PRINT_PREFIX..string.format(format,...), ERROR_LEVEL); end
-------------------------------------------


--[[
	Function for resizing the buffer if necessary.
	Errors if the resize fails (e.g., hits MaxCapacity limit).
]]
local function ResizeBuffer(self: StringBuilder, newLength: number)
	local currentCapacity = self._Capacity

	if newLength <= currentCapacity then 
		return true 
	end

	local targetCapacity = math.max(currentCapacity * 2, newLength + DEFAULT_CAPACITY)

	targetCapacity = math.min(targetCapacity, self._MaxCapacity)

	if targetCapacity < newLength then
		errorfmt(
			"buffer resize failed. requested=%d, max=%d",
			newLength,
			self._MaxCapacity
		)
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
	local n = math.floor(Capacity)
	if n ~= Capacity then
		error("new: Capacity is not a whole number!")
	end
	n = math.floor(MaxCapacity)
	if n ~= MaxCapacity then
		error("new: MaxCapacity is not a whole number!")
	end
	Capacity = math.max(MIN_CAPACITY, Capacity)
	MaxCapacity = math.max(MIN_MAX_CAPACITY, Capacity, MaxCapacity)

	MaxCapacity = math.min(MaxCapacity,MAX_SB_BUFFER_SIZE)
	Capacity = math.min(Capacity,MAX_SB_BUFFER_SIZE)

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
	if not data then return nil end
	local decompressed;
	local compressedLength = EncodingService:GetDecompressedBufferSize(data, COMPRESSION_ALGORITHM)
	if not compressedLength then
		decompressed = data
	else
		local success, newdata = pcall(EncodingService.DecompressBuffer, EncodingService, data, COMPRESSION_ALGORITHM)
		if not success then return nil end
		decompressed = newdata
	end
	local buflen = buffer.len(decompressed)
	if buflen < HEADER_SIZE then return nil end
	if buflen > MAX_ROBLOX_BUFFER_SIZE then return nil end

	local identifier = buffer.readu16(decompressed,0)
	if identifier ~= PACKED_BIT then return nil end
	-- The ID matches our global packed_bit, so this is a valid buffer.

	local capacity = buffer.readu32(decompressed, PACKED_CAPACITY_OFFSET)
	local maxCapacity = buffer.readu32(decompressed, PACKED_MAX_CAPACITY_OFFSET)
	local length = buffer.readu32(decompressed, PACKED_LENGTH_OFFSET)

	if capacity < MIN_CAPACITY then
		error("FromBuffer: malformed buffer, capacity cant be less than MIN_CAPACITY")
	elseif capacity > MAX_SB_BUFFER_SIZE then
		error("FromBuffer: malformed buffer, capacity cant be more than MAX_SB_BUFFER_SIZE!")
	end
	if maxCapacity < MIN_MAX_CAPACITY then
		error("FromBuffer: malformed buffer, maxCapacity cant be less than MIN_MAX_CAPACITY")
	elseif maxCapacity > MAX_SB_BUFFER_SIZE then
		error("FromBuffer: malformed buffer, maxCapacity cant be more than MAX_SB_BUFFER_SIZE!")
	end
	if length > MAX_SB_BUFFER_SIZE then
		error("FromBuffer: malformed buffer, length cant be more than MAX_SB_BUFFER_SIZE!")
	end

	-- More if statements to block garbage buffers
	if length > capacity then return nil end
	if capacity > maxCapacity then return nil end
	if HEADER_SIZE + length ~= buflen then return nil end

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

	-- Tier 1 (Fastest - reading 4 bytes at a time)
	local u32_Limit = length // 4 -- ( "//" op divides and rounds down )
	for _ = 1, u32_Limit do
		if buffer.readu32(buf1, cursor) ~= buffer.readu32(buf2, cursor) then 
			return false 
		end
		cursor += 4
	end
	-- Tier 2 (Slower - reading 2 bytes at a time)
	if (length - cursor) >= 2 then
		if buffer.readu16(buf1, cursor) ~= buffer.readu16(buf2, cursor) then
			return false
		end
		cursor += 2
	end
	-- Tier 3 (Slowest - reading 1 byte at a time)
	if (length - cursor) == 1 then
		if buffer.readu8(buf1, cursor) ~= buffer.readu8(buf2, cursor) then
			return false
		end
	end

	return true
end

-- Allow using == operator on StringBuilders
StringBuilderMeta.__eq = StringBuilder.Compare

--[[
    Get specific character(s) starting from index
    By default, returns a single character at the given index.
    Count is optional (default: 1) and can be positive or negative.
    (Returned string won't be reversed by a negative Count)
]]
function StringBuilder.GetCharacters(self: StringBuilder, Index: number, Count: number?): string
	if not Index or Index < 0 then
		return ""
	end

	local n = math.floor(Index)
	if n ~= Index then
		error("GetCharacters: Index is not a whole number!")
	end

	Count = if not Count or Count == 0 then 1 else Count
	n = math.floor(Count)
	if n ~= Count then
		error("GetCharacters: Count is not a whole number!")
	end

	local Length = self._Length

	local index_a, index_b = math.clamp(Index, 0, Length), math.clamp(Index + Count, 0, Length)

	local start, finish = math.min(index_a, index_b), math.max(index_a, index_b)
	local size = finish - start

	if size > 0 then
		return buffer.readstring(self._Buffer, start, size)
	end

	return ""
end

--[[
    Set character(s) starting from index
    Data can be a string or any tostring convertable type
]]
function StringBuilder.SetCharacters(self: StringBuilder, Index: number, Data: any): StringBuilder
	if not Index or Data == nil or Index < 0 then
		return self
	end
	local n = math.floor(Index)
	if n ~= Index then
		error("SetCharacters: Index is not a whole number!")
	end
	local strData = tostring(Data)
	if not strData or strData == "" then return self end

	local Count = #strData
	local newLength = Index+Count
	local oldLength = self._Length

	if newLength > self._Capacity then
		ResizeBuffer(self, newLength)
	end

	if Index > oldLength then
		buffer.fill(self._Buffer, oldLength, 0, Index - oldLength)
	end

	buffer.writestring(self._Buffer,Index,strData,Count)

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
	local n = math.floor(EnsuredCapacity)
	if n ~= EnsuredCapacity then
		error("EnsureCapacity: EnsuredCapacity is not a whole number!")
	end
	n = math.clamp(EnsuredCapacity, 0, self._MaxCapacity)
	local success = pcall(ResizeBuffer, self, n)

	return success and EnsuredCapacity <= n, self._Capacity
end

--[[
	Manually and safely set the capacity.
	Resizes the buffer (out of bounds data gets cut off)
	Returns the new real capacity (capped by MaxCapacity and the default MIN_CAPACITY)
]]
function StringBuilder.SetCapacity(self: StringBuilder, Capacity: number): number
	if not Capacity then return self._Capacity end

	local n = math.floor(Capacity)
	if n ~= Capacity then
		error("SetCapacity: Capacity is not a whole number!")
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
	if not MaxCapacity then return end
	local n = math.floor(MaxCapacity)
	if n ~= MaxCapacity then
		error("SetMaxCapacity: MaxCapacity is not a whole number!")
	end
	if MaxCapacity < self._Capacity then
		error("SetMaxCapacity: MaxCapacity cant be less than Capacity!")
	end
	if MaxCapacity < MIN_MAX_CAPACITY then return end
	if MaxCapacity > MAX_SB_BUFFER_SIZE then 
		MaxCapacity = MAX_SB_BUFFER_SIZE
	end
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
	Throws an error if passed length is higher than MaxCapacity or not a whole number.
]]
function StringBuilder.SetLength(self: StringBuilder, Length: number): StringBuilder
	if Length < 0 then
		error("SetLength: Length cant be less than than 0!")
	end
	local n = math.floor(Length)
	if n ~= Length then
		error("SetLength: Length is not a whole number!")
	end
	Length = n
	if Length > self._MaxCapacity then
		error("SetLength: Length cant be more than MaxCapacity!")
	end

	-- a,b comparison is faster than a function call
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
	local strData = Data
	if type(strData) ~= "string" then
		strData = tostring(strData)
	end
	local dataSize = #strData
	if dataSize == 0 then return self end

	local currentLength = self._Length
	local newLength = currentLength + dataSize

	if newLength > self._Capacity then
		ResizeBuffer(self, newLength)
	end

	buffer.writestring(self._Buffer, currentLength, strData, dataSize)
	self._Length = newLength

	return self
end

--[[
    same as StringBuilder.Append except adds a line terminator at the end.
    (appends and creates a new line using "\n")
]]
function StringBuilder.AppendLine(self: StringBuilder, Data: any?): StringBuilder
	StringBuilder.Append(self,Data)
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
]]
function StringBuilder.Remove(self: StringBuilder, Index: number, Count: number): StringBuilder
	if not Index then return self end
	if not Count or Count <= 0 then return self end

	Index = math.floor(Index)
	Count = math.floor(Count)

	if Index < 0 or Index >= self._Length then return self end

	-- So we dont try to remove more characters than exist after the index
	local actualCount = math.min(Count, self._Length - Index)

	local moveSource = Index + actualCount
	local bytesToMove = self._Length - moveSource

	if bytesToMove > 0 then
		-- We shift the buffer down
		buffer.copy(self._Buffer, Index, self._Buffer, moveSource, bytesToMove)
	end

	self._Length -= actualCount

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
	if not Index then return self end
	Index = math.floor(Index)
	if Index < 0 then return self end
	if Index > self._Length then return self end

	if Data == nil then return self end
	if type(Data) ~= "string" then
		Data = tostring(Data)
	end
	if Data == "" then return self end

	-- Clamp Index so theres no gaps
	Index = math.min(Index, self._Length)


	local DataSize = #Data
	local AvailableSpace = self._MaxCapacity - self._Length

	-- Capacity check
	if AvailableSpace < 1 then
		error("Insert: No available space!")
	end
	if DataSize > AvailableSpace then
		error("Insert: Data cant fully fit!")
	end

	local newLength = self._Length + DataSize
	-- a,b comparison is faster than a function call
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
	Replaces all occurences of [Target] with [Replacement].
]]
function StringBuilder.Replace(self: StringBuilder, search: string, replacement: string): StringBuilder
	if type(search) ~= "string" then error("Replace: search is not a string!") end
	if type(replacement) ~= "string" then error("Replace: replacement is not a string!") end
	if search == replacement then return self end
	local length = self._Length
	local searchLength = #search
	if length == 0 or searchLength == 0 then return self end
	local baseString = buffer.readstring(self._Buffer, 0, length)
	local starts = table.create(16) :: {number}
	local count = 0
	local cursor = 1

	while true do
		local startPos = string.find(baseString, search, cursor, true)
		if not startPos then break end

		count += 1
		starts[count] = startPos - 1
		cursor = startPos + searchLength
	end

	if count == 0 then return self end

	local replacementLength = #replacement
	local newLength = length + count * (replacementLength - searchLength)

	if newLength > self._Capacity then
		ResizeBuffer(self, newLength)
	end

	local newBuf = buffer.create(self._Capacity)
	local readCursor = 0
	local writeCursor = 0

	for i = 1, count do
		local startPos = starts[i]
		local segmentLength = startPos - readCursor

		if segmentLength > 0 then
			buffer.copy(newBuf, writeCursor, self._Buffer, readCursor, segmentLength)
			writeCursor += segmentLength
		end

		if replacementLength > 0 then
			buffer.writestring(newBuf, writeCursor, replacement, replacementLength)
			writeCursor += replacementLength
		end

		readCursor = startPos + searchLength
	end

	local remaining = length - readCursor
	if remaining > 0 then
		buffer.copy(newBuf, writeCursor, self._Buffer, readCursor, remaining)
	end

	self._Buffer = newBuf
	self._Length = newLength

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


return StringBuilder
