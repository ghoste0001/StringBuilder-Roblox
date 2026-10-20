---
hide:
- navigation
---

# API Reference

Here's the full list of everything you can do with StringBuilder!

---

## Initialization

### `new`
```lua
StringBuilder.new(Capacity: number?, MaxCapacity: number?): StringBuilder
```
Returns a brand new `StringBuilder` object.

- **Capacity**: *(Optional)* The starting size in bytes. Defaults to `64`.
- **MaxCapacity**: *(Optional)* Absolute max capacity in bytes. Defaults to `4*1024*1024` (4MB).

Both capacities must be whole numbers. `Capacity` is clamped to the supported buffer-size range, and `MaxCapacity` is adjusted to be at least as large as `Capacity`.

---

## Modification

### `Append`
```lua
StringBuilder:Append(Data: any?): StringBuilder
```
Appends data at the end! Automatically converts non-string values to strings. Passing `nil` does nothing.

### `AppendLine`
```lua
StringBuilder:AppendLine(Data: any?): StringBuilder
```
Same as `Append`, except it adds a line terminator for you at the end (`"\n"`).

### `AppendFormat`
```lua
StringBuilder:AppendFormat(Format: string, ...): StringBuilder
```
Same as `Append`, except with formatting built-in!

### `AppendJoin`
```lua
StringBuilder:AppendJoin(Data: {any?}, Separator: string?): StringBuilder
```
Concatenates and appends an array of strings and/or numbers, placing your `Separator` right between each one (like commas).
!!! warning "As this uses `table.concat`, it will error if you pass anything other than strings and numbers!"

### `AppendList`
```lua
StringBuilder:AppendList(...): StringBuilder
```
Concatenates and appends a list of string and/or number arguments. Way faster than chaining appends together for building strings!
!!! warning "As this uses `table.concat`, it will error if you pass anything other than strings and numbers!"

### `Compare`
```lua
StringBuilder:Compare(self2: StringBuilder): boolean
```
Compares this StringBuilder with another one and returns `true` if their contents are fully identical!

*(Note: You can also use the native `==` operator directly between two StringBuilders thanks to `__eq` metamethod support.)*

### `GetCharacters`
```lua
StringBuilder:GetCharacters(Index: number, Count: number?): string
```
Grabs specific bytes starting from your given zero-based `Index`. `Count` defaults to `1`, but you can pass negative or positive numbers to grab more. Negative values don't return reversed strings; they just read the range in the opposite direction.

Throws an error if the requested range is out of bounds or either value isn't a whole number. A `Count` of `0` returns an empty string.

### `SetCharacters`
```lua
StringBuilder:SetCharacters(Index: number, Data: any): StringBuilder
```
Overwrites bytes starting at your `Index` directly with the new `Data`!

If the new data extends past the old length, the builder grows automatically. Gaps created past the old length are automatically zero-filled.

### `Insert`
```lua
StringBuilder:Insert(Index: number, Data: any): StringBuilder
```
Inserts your `Data` right at the given zero-based byte `Index` and safely pushes everything else to the right.

Throws an error if the index is invalid or there isn't enough available max capacity for the data to fit.

Passing `nil` or an empty string leaves the builder unchanged.

### `Replace`
```lua
StringBuilder:Replace(Target: string, Replacement: string, Start: number?): StringBuilder
```
Replaces all non-overlapping occurrences of `Target` with `Replacement`, starting from the optional zero-based `Start` index (defaults to `0`).

Anything before `Start` stays untouched!

Throws an error if `Target` or `Replacement` isn't a string, `Start` is invalid, or the resulting string exceeds your `MaxCapacity`.

Passing an empty `Target` leaves the builder unchanged.

### `Remove`
```lua
StringBuilder:Remove(Index: number, Count: number?): StringBuilder
```
Chops exactly `Count` bytes right out of the string starting from `Index`. `Count` defaults to `1`.

Throws an error if `Index` is invalid, `Count` is negative or isn't a whole number, or the requested range extends beyond the current length.

### `Reverse`
```lua
StringBuilder:Reverse(): StringBuilder
```
Reverses the string safely using `utf8.graphemes`. This is the default because it fully supports emojis and multi-language strings!
*(Note: It's slower than `ReverseBytes()`.)*

### `ReverseBytes`
```lua
StringBuilder:ReverseBytes(): StringBuilder
```
Reverses the string using raw buffer magic. Just as accurate as `Reverse()` for English letters and noticeably faster, but it lacks emoji and multi-language support. Use with caution!

### `Space`
```lua
StringBuilder:Space(): StringBuilder
```
Just appends a space (`" "`) at the end.

### `Newline`
```lua
StringBuilder:Newline(): StringBuilder
```
Just appends a newline (`"\n"`) at the end.

### `Clear`
```lua
StringBuilder:Clear(): StringBuilder
```
Clears the buffer! *(More accurately, it just resets the length, so it's basically free to call.)*

---

## Searching

### `Find`
```lua
StringBuilder:Find(Target: string, Start: number?): (number?, number?)
```
Searches for the first occurrence of `Target`, starting at the optional zero-based `Start` index (defaults to `0`).

Returns the zero-based start index and exclusive end index, or `nil` if nothing was found.

An empty target returns `nil`. Throws an error if `Start` is out of bounds (<0 or self._Length) or isn't a whole number.

Includes special fast cases for searching one and two-byte targets!

### `FindNative`
```lua
StringBuilder:FindNative(Pattern: string, Start: number?, Plain: boolean?): (number?, number?)
```

A wrapper for Luau's native `string.find`.

Searches from the optional zero-based `Start` index (defaults to `0`). `Plain` defaults to `true`, meaning it searches for the exact text instead of interpreting it as a Lua pattern. Set `Plain` to `false` if you want pattern matching.

Returns the zero-based start index and exclusive end index, or `nil` if nothing was found.

An empty pattern returns `nil`. Throws an error if `Start` is out of bounds (<0 or self._Length) or isn't a whole number.

!!! warning "This converts the searched buffer range into a string first, so use it sparingly with large StringBuilders or frequent calls!"

---

## Capacity and Size

!!! note "Capacity Details"
    Everything under the hood is buffers, so capacity and lengths are ALWAYS in bytes!

### `GetLength`
```lua
StringBuilder:GetLength(): number
```
Returns the current length of your string in bytes.

### `SetLength`
```lua
StringBuilder:SetLength(Length: number): StringBuilder
```
Manually sets the length of the string!
- If it's smaller, it instantly truncates your string.
- If it's larger than your current capacity, it forces a buffer expansion.
- Newly extended bytes are zero-filled.
- Throws an error if the length is negative, exceeds `MaxCapacity`, or isn't a whole number.

### `GetCapacity`
```lua
StringBuilder:GetCapacity(): number
```
Returns your current capacity in bytes.

### `EnsureCapacity`
```lua
StringBuilder:EnsureCapacity(EnsuredCapacity: number): (boolean, number)
```
Makes sure your buffer is at least as big as `EnsuredCapacity`!

Returns `success, capacity`, where `success` tells you whether the requested capacity was achieved, and `capacity` is your current capacity.

Throws an error if `EnsuredCapacity` is negative, exceeds `MaxCapacity`, or isn't a whole number.

*(Note: `EnsureCapacity(0)` is valid and succeeds as long as the current capacity is at least `0`.)*

### `SetCapacity`
```lua
StringBuilder:SetCapacity(Capacity: number): number
```
Manually sets the capacity safely! It resizes the buffer, and any data that no longer fits gets cut off.

Returns the new actual capacity, capped by your `MaxCapacity`.

### `GetMaxCapacity`
```lua
StringBuilder:GetMaxCapacity(): number
```
Returns the max capacity in bytes.

### `SetMaxCapacity`
```lua
StringBuilder:SetMaxCapacity(MaxCapacity: number)
```
Manually sets your absolute max capacity.
Throws an error if `MaxCapacity` is less than your current capacity or isn't a whole number.

The value is capped at the maximum supported buffer size.

### `GetFreeSpace`
```lua
StringBuilder:GetFreeSpace(): number
```
Returns your available writable space in bytes (`Capacity - Length`).

### `GetTotalFreeSpace`
```lua
StringBuilder:GetTotalFreeSpace(): number
```
Returns your total remaining writable space in bytes (`MaxCapacity - Length`).

---

## Extraction & Memory

### `ToString`
```lua
StringBuilder:ToString(): string
```
Returns the fully built string!

*(You can also just use `tostring(stringBuilder)` or `print(stringBuilder)`.)*

### `Destroy`
```lua
StringBuilder:Destroy()
```
Destroys the object. Leaves the buffer to be cleaned up by the garbage collector automatically since there's no way to do it manually!

---

## Packing & Compression

These are mostly for networking or datastores!

### `Pack`
```lua
StringBuilder:Pack(): buffer
```
Packs the StringBuilder's data and metadata all together into a buffer!

### `Compress`
```lua
StringBuilder:Compress(CompressionLevel: number?): buffer
```
Compresses the StringBuilder with Zstd.

`CompressionLevel` is optional and ranges from `-7` to `22`. Higher levels generally mean more compression at the cost of more time.

Returns a packed and compressed buffer, or falls back to the packed buffer if compression fails or the compressed result isn't smaller.

### `FromBuffer`
```lua
StringBuilder.FromBuffer(data: buffer): StringBuilder?
```
Returns a `StringBuilder` object right back from a packed or compressed StringBuilder buffer.

Returns `nil` if the buffer isn't recognized as a valid StringBuilder buffer or can't be decompressed. Throws descriptive validation errors if the buffer contains invalid capacity metadata.

!!! warning "Only pass buffers produced by `Pack()` or `Compress()` if you want to ensure the buffer has the expected format!"
