--!native
--!strict

--[[
	@module StringBuilder
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
local COMPRESSION_ALGORITHM = Enum.CompressionAlgorithm.Zstd -- Default: Zstd (its the only one available)
local COMPRESSION_LEVEL = 0 -- Default: 0 (-7 to 22, higher = more compression at the cost of performance)
local DEFAULT_MAX_CAPACITY = 1*1024*1024 -- Default: 1*1024*1024 (byte > kilobyte > megabyte)
local DEFAULT_CAPACITY = 64 -- Default: 64 (In bytes)
local MIN_MAX_CAPACITY = 1 -- Default: 1 (In bytes)
local MIN_CAPACITY = 1 -- Default: 1 (In bytes)

--// Constants
local MAX_ROBLOX_BUFFER_SIZE = 1024*1024*1024 -- 1073741824 bytes (1GB), this is the max size a buffer in roblox can be.

--/ Compression related magic numbers
local U16 = 2
local U32 = 4

local PACKED_BIT = 59371 -- Identifier to use for packed buffers (0-65535)
local PACKED_CAPACITY_OFFSET = U16
local PACKED_MAX_CAPACITY_OFFSET = PACKED_CAPACITY_OFFSET+U32
local PACKED_LENGTH_OFFSET = PACKED_MAX_CAPACITY_OFFSET+U32
local HEADER_SIZE = U16+U32+U32+U32

--/ Print related
local PRINT_PREFIX = "[StringBuilder]: "

--// Functions

--/ Buffer
local bufferlen = buffer.len
local create = buffer.create
local copy = buffer.copy
-- Read
local readstring = buffer.readstring
local readu32 = buffer.readu32
local readu16 = buffer.readu16
local readu8 = buffer.readu8
-- Write
local writestring = buffer.writestring
local writeu32 = buffer.writeu32
local writeu16 = buffer.writeu16
local writeu8 = buffer.writeu8

--/ Math
local clamp = math.clamp
local floor = math.floor
local min = math.min
local max = math.max

--/ String
local format = string.format
local tostring = tostring
local find = string.find
local sub = string.sub

--/ Table
local insert = table.insert
local concat = table.concat

--/ Other
local type = type

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

	local targetCapacity = max(currentCapacity * 2, newLength + DEFAULT_CAPACITY)

	targetCapacity = min(targetCapacity, self._MaxCapacity)

	if targetCapacity < newLength then
		error(table.concat({
			PRINT_PREFIX,
			"buffer resize failed.",
			" requested=",
			newLength,
			" max=",
			self._MaxCapacity
		}))
	end

	local oldBuf = self._Buffer
	local newBuf = create(targetCapacity)

	copy(newBuf, 0, oldBuf, 0, self._Length)

	self._Buffer = newBuf
	self._Capacity = targetCapacity

	return true
end

-------------------------------------------

--[[
	Returns a new StringBuilder object.
]]
function StringBuilder.new(Capacity: number?, MaxCapacity: number?): StringBuilder
	Capacity = max(MIN_CAPACITY, Capacity or DEFAULT_CAPACITY)
	MaxCapacity = max(MIN_MAX_CAPACITY, Capacity, MaxCapacity or DEFAULT_MAX_CAPACITY)

	MaxCapacity = min(MaxCapacity,MAX_ROBLOX_BUFFER_SIZE) -- Clamp to 1GB
	Capacity = min(Capacity,MAX_ROBLOX_BUFFER_SIZE) -- Same here

	return setmetatable({
		_Buffer = create(Capacity),
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

	local out = create(HEADER_SIZE + dataSize)

	writeu16(out, 0, PACKED_BIT) -- Id is always at 0 offset
	writeu32(out, PACKED_CAPACITY_OFFSET, self._Capacity)
	writeu32(out, PACKED_MAX_CAPACITY_OFFSET, self._MaxCapacity)
	writeu32(out, PACKED_LENGTH_OFFSET, self._Length)

	copy(out, HEADER_SIZE, self._Buffer, 0, dataSize)

	return out
end

--[[
    Returns a StringBuilder object from a compressed (or packed) StringBuilder
]]
function StringBuilder.FromBuffer(data: buffer): StringBuilder?
	if not data then return nil end
	local success, decompressed = pcall(EncodingService.DecompressBuffer, EncodingService, data, COMPRESSION_ALGORITHM)
	if not success then decompressed = data end -- If its not compressed, use it as is.
	if bufferlen(decompressed) < HEADER_SIZE then return nil end -- Return if the buffer is smaller then the header size
	
	local identifier = readu16(decompressed,0)
	if identifier ~= PACKED_BIT then return nil end
	-- The ID matches our global packed_bit, so this is a valid buffer.

	local capacity = readu32(decompressed, PACKED_CAPACITY_OFFSET)
	local maxCapacity = readu32(decompressed, PACKED_MAX_CAPACITY_OFFSET)
	local length = readu32(decompressed, PACKED_LENGTH_OFFSET)
	
	-- More if statements to block garbage buffers
	if length > capacity then return nil end
	if capacity > maxCapacity then return nil end
	if HEADER_SIZE + length > bufferlen(decompressed) then return nil end

	local self = setmetatable({
		_Buffer = create(capacity),
		_Capacity = capacity,
		_MaxCapacity = maxCapacity,
		_Length = length,
	}, StringBuilderMeta)
	
	-- Copy data after the header into the new StringBuilder
	copy(self._Buffer, 0, decompressed, HEADER_SIZE, length)

	return self
end

--[[
    Compresses the internal string buffer with the default compression algorithm
    Default CompressionLevel is at the top of the module
    CompressionLevel must range from (-7 to 22)
    Higher CompressionLevel = more compression at the cost of performance
    Returns a packed and compressed buffer
]]
function StringBuilder.Compress(self: StringBuilder, CompressionLevel: number): buffer
	local packed = StringBuilder.Pack(self)
	local compressed = EncodingService:CompressBuffer(packed, COMPRESSION_ALGORITHM, CompressionLevel or COMPRESSION_LEVEL)
	-- Lets not return a bigger buffer than the original
	if bufferlen(compressed) < bufferlen(packed) then
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
	if self == self2 then return true end

	local buf1 = self._Buffer
	local buf2 = self2._Buffer
	local cursor = 0

	-- Tier 1
	local u32_Limit = length // 4
	for _ = 1, u32_Limit do
		if buffer.readu32(buf1, cursor) ~= buffer.readu32(buf2, cursor) then 
			return false 
		end
		cursor += 4
	end

	-- Tier 2
	if (length - cursor) >= 2 then
		if buffer.readu16(buf1, cursor) ~= buffer.readu16(buf2, cursor) then
			return false
		end
		cursor += 2
	end
	-- Tier 3
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
    Count is optional and can be positive or negative.
    (Returned string won't be reversed by a negative Count)
]]
function StringBuilder.GetCharacters(self: StringBuilder, Index: number, Count: number?): string
	if not Index or Index < 0 then
		return ""
	end
	local Count = if not Count or Count == 0 then 1 else Count
	local Length = self._Length
	
	local index_a, index_b = clamp(Index, 0, Length), clamp(Index + Count, 0, Length)

	local start, finish = min(index_a, index_b), max(index_a, index_b)
	local size = finish - start

	if size > 0 then
		return readstring(self._Buffer, start, size)
	else 
		return ""
	end
end

--[[
    Set character(s) starting from index
    Data can be a string or any tostring convertable type
]]
function StringBuilder.SetCharacters(self: StringBuilder, Index: number, Data: any): StringBuilder
	if not Index or Index < 0 then
		return self
	end
	if Data == nil then return self end
	local strData = tostring(Data)
	if not strData or strData == "" then return self end
	
	local Count = #strData
	local NewLength = Index+Count
	
	if NewLength > self._Capacity then
		ResizeBuffer(self, NewLength)
	end
	
	writestring(self._Buffer,Index,strData,Count)
	
	if NewLength > self._Length then
		self._Length = NewLength
	end
	return self
end

--[[
    Ensures that the buffer is at least the given Capacity
    Resizes the buffer if needed.
    Returns: success, capacity
]]
function StringBuilder.EnsureCapacity(self: StringBuilder, EnsuredCapacity: number): (boolean, number)
	if not EnsuredCapacity then return false, self._Capacity end
	local CurrentCapacity = self._Capacity
	if CurrentCapacity >= EnsuredCapacity then return true, CurrentCapacity end

	local newSize = min( max(CurrentCapacity * 2, EnsuredCapacity), self._MaxCapacity )

	if CurrentCapacity == newSize then return false, CurrentCapacity end

	local newBuffer = create(newSize)

	copy(newBuffer, 0, self._Buffer, 0, CurrentCapacity)

	self._Buffer = newBuffer
	self._Capacity = newSize

	return true, newSize
end

--[[
	Manually and safely set the capacity.
	Resizes the buffer (out of bounds data gets cut off)
	Returns the new real capacity (capped by MaxCapacity and the default MIN_CAPACITY)
]]
function StringBuilder.SetCapacity(self: StringBuilder, Capacity: number): number
	if not Capacity then return self._Capacity end

	Capacity = floor(Capacity)
	Capacity = clamp(Capacity, MIN_CAPACITY, MAX_ROBLOX_BUFFER_SIZE)
	Capacity = min(Capacity, self._MaxCapacity)

	if self._Capacity == Capacity then return Capacity end

	local oldBuf = self._Buffer
	local newBuffer = create(Capacity)

	local copyCount = min(self._Length, Capacity)
	copy(newBuffer, 0, oldBuf, 0, copyCount)

	self._Buffer = newBuffer
	self._Capacity = Capacity
	self._Length = copyCount
	return Capacity
end

--[[
	Manually set the max capacity (safely).
	Can't be less than self._Capacity (it will get silently ignored).
]]
function StringBuilder.SetMaxCapacity(self: StringBuilder, MaxCapacity: number)
	if not MaxCapacity then return end
	if MaxCapacity < self._Capacity then return end
	if MaxCapacity < MIN_MAX_CAPACITY then return end
	if MaxCapacity > MAX_ROBLOX_BUFFER_SIZE then 
		MaxCapacity = MAX_ROBLOX_BUFFER_SIZE
	end
	-- Floor in case it isnt an integer
	self._MaxCapacity = floor(MaxCapacity)
end

-- Returns the current length of the string in bytes
function StringBuilder.GetLength(self: StringBuilder): number
	return self._Length
end

--[[
    Manually sets the length of the string.
    If smaller, it instantly truncates the string.
    If larger than (self._Capacity), it forces a buffer expansion.
    Returns true if successful, false if not.
]]
function StringBuilder.SetLength(self: StringBuilder, Length: number): boolean
	if Length < 0 then return false end
	Length = min(floor(Length), self._MaxCapacity)

	-- a,b comparison is faster than a function call
	if Length > self._Capacity then
		ResizeBuffer(self, Length)
	end

	self._Length = Length
	return true
end

--[[
    Appends any tostring() convertable data at the end.
]]
function StringBuilder.Append(self: StringBuilder, Data: any): StringBuilder
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

	writestring(self._Buffer, currentLength, strData, dataSize)
	self._Length = newLength

	return self
end

--[[
    same as StringBuilder.Append except adds a line terminator at the end.
    (appends and creates a new line using "\n")
]]
function StringBuilder.AppendLine(self: StringBuilder, Data: any?): StringBuilder
	self:Append(Data)
	self:Newline()
	return self
end

--[[
    same as StringBuilder.Append except with formatting.
]]
function StringBuilder.AppendFormat(self: StringBuilder, Format: string, ...): StringBuilder
	if Format then
		local Data = format(Format, ...)
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
	local str = concat({...})
	local len = #str
	if len == 0 then return self end
	
	local pos = self._Length
	local newPos = pos + len

	if newPos > self._Capacity then
		ResizeBuffer(self, newPos)
	end

	writestring(self._Buffer, pos, str, len)
	self._Length = newPos
	return self
end

--[[
    Concatenates an array or collection of items, 
    placing a specific separator between each one (like commas).
]]
function StringBuilder.AppendJoin(self: StringBuilder, Data: {any?}, Sep: string?): StringBuilder
	local str = concat(Data,Sep)
	local len = #str
	local pos = self._Length
	local newPos = pos + len

	if newPos > self._Capacity then
		ResizeBuffer(self, newPos)
	end

	writestring(self._Buffer, pos, str, len)
	self._Length = newPos
	return self
end

--[[
    Removes [Count] amount of letters starting from index
]]
function StringBuilder.Remove(self: StringBuilder, Index: number, Count: number): StringBuilder
	if not Index then return self end
	if not Count or Count <= 0 then return self end

	Index = floor(Index)
	Count = floor(Count)

	if Index < 0 or Index >= self._Length then return self end

	-- So we dont try to remove more characters than exist after the index
	local actualCount = min(Count, self._Length - Index)

	local moveSource = Index + actualCount
	local bytesToMove = self._Length - moveSource

	if bytesToMove > 0 then
		-- We shift the buffer down
		copy(self._Buffer, Index, self._Buffer, moveSource, bytesToMove)
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
	for i = 0, floor(length * 0.5) - 1 do
		local leftIndex = i
		local rightIndex = length - 1 - i

		-- Read bytes
		local leftByte = readu8(self._Buffer, leftIndex)
		local rightByte = readu8(self._Buffer, rightIndex)

		-- Swap them
		writeu8(self._Buffer, leftIndex, rightByte)
		writeu8(self._Buffer, rightIndex, leftByte)
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

	local baseString = readstring(self._Buffer, 0, length)
	local graphemes = {}

	-- Collect all characters
	for start, stop in utf8.graphemes(baseString) do
		insert(graphemes, sub(baseString, start, stop))
	end

	-- Write them in reverse order
	local currentPos = 0
	for i = #graphemes, 1, -1 do
		local char = graphemes[i]
		writestring(self._Buffer, currentPos, char)
		currentPos += #char
	end

	return self
end

--[[
	Inserts data at the given index and pushes the rest to the right.
]]
function StringBuilder.Insert(self: StringBuilder, Index: number, Data: any): StringBuilder
	if not Index then return self end
	Index = floor(Index)
	if Index < 0 then return self end
	if Index > self._Length then return self end

	if Data == nil then return self end
	Data = tostring(Data)
	if not Data or Data == "" then return self end
	
	-- Clamp Index so theres no gaps
	Index = min(Index, self._Length)


	local DataSize = #Data
	local AvailableSpace = self._MaxCapacity - self._Length

	-- Capacity check
	if AvailableSpace < 1 then return self end
	if DataSize > AvailableSpace then
		DataSize = AvailableSpace
	end

	local newLength = self._Length + DataSize
	-- a,b comparison is faster than a function call
	if newLength > self._Capacity then
		ResizeBuffer(self, newLength)
	end

	local bytesToMove = self._Length - Index
	if bytesToMove > 0 then
		copy(self._Buffer, Index + DataSize, self._Buffer, Index, bytesToMove)
	end
	-- Write the new text (clamped by DataSize)
	writestring(self._Buffer, Index, Data, DataSize)

	self._Length = newLength

	return self
end

--[[
	Replaces all occurences of [Target] with [Replacement].
]]
function StringBuilder.Replace(self: StringBuilder, Target: string, Replacement: string): StringBuilder
	if not Target or not Replacement then return self end
	if Target == "" then return self end

	local targetSize = #Target
	local replacementSize = #Replacement
	local delta = replacementSize - targetSize

	-- Read the buffer once to find our match indices
	local baseString = readstring(self._Buffer, 0, self._Length)

	local searchIndex = 1
	local currentOffset = 0

	while true do
		-- Plain search
		local startIdx, endIdx = find(baseString, Target, searchIndex, true)
		if not startIdx or not endIdx then break end

		-- string.find is 1> indexed, buffers are 0> indexed.
		-- We add currentOffset to account for previous replacements.
		local adjustedIndex = (startIdx - 1) + currentOffset

		if delta == 0 then
			-- If lengths are identical just overwrite the bytes directly
			writestring(self._Buffer, adjustedIndex, Replacement)
		else
			local moveSource = adjustedIndex + targetSize
			local moveDest = adjustedIndex + replacementSize
			local bytesToMove = self._Length - moveSource

			if delta > 0 then
				-- We resize if needed
				ResizeBuffer(self, self._Length + delta)
			end

			-- Shift the remaining data
			if bytesToMove > 0 then
				copy(self._Buffer, moveDest, self._Buffer, moveSource, bytesToMove)
			end

			-- Write the new replacement string into the gap
			writestring(self._Buffer, adjustedIndex, Replacement)

			self._Length += delta
			currentOffset += delta
		end

		searchIndex = endIdx + 1
	end

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
	writeu8(self._Buffer,pos,32) -- 32 is a space " "
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
	writeu8(self._Buffer,pos,10) -- 10 is \n
	self._Length = newPos
	return self
end

--[[
	Returns the fully built string.
]]
function StringBuilder.ToString(self: StringBuilder): string
	return readstring(self._Buffer,0,self._Length)
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
	return readstring(self._Buffer,0,self._Length)
end


return StringBuilder
