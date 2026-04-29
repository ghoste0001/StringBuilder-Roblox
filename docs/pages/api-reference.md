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
- **MaxCapacity**: *(Optional)* Absolute max capacity in bytes. Defaults to `1*1024*1024` (1MB).

---

## Modification

### `Append`
```lua
StringBuilder:Append(Data: any?): StringBuilder
```
Appends data (string, number, bool) at the end!

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
Concatenates and appends an array of string & numbers, placing your `Separator` right between each one (like commas).
!!! warning "As this uses `table.concat`, it will error if you pass anything other than strings and numbers!"

### `AppendList`
```lua
StringBuilder:AppendList(...): StringBuilder
```
Concatenates and appends a list of string and/or number arguments. Way faster than chaining appends together!
!!! warning "As this uses `table.concat`, it will error if you pass anything other than strings and numbers!"

### `Compare`
```lua
StringBuilder:Compare(self2: StringBuilder): boolean
```
Compares this StringBuilder with another one and returns `true` if their contents are fully identical!

### `GetCharacters`
```lua
StringBuilder:GetCharacters(Index: number, Count: number?): string
```
Grabs specific character(s) starting from your given `Index`. `Count` defaults to 1, but you can pass negative or positive numbers to grab more (negative values dont return reversed strings).

### `SetCharacters`
```lua
StringBuilder:SetCharacters(Index: number, Data: any): StringBuilder
```
Overwrites any character(s) starting at your `Index` directly with the new `Data`!

### `Insert`
```lua
StringBuilder:Insert(Data: any?, Index: number): StringBuilder
```
Inserts your `Data` right at the given `Index` and safely pushes everything else to the right.

### `Replace`
```lua
StringBuilder:Replace(Target: string, Replacement: string): StringBuilder
```
Replaces all occurrences of `Target` with `Replacement`.

### `Remove`
```lua
StringBuilder:Remove(Index: number, Count: number): StringBuilder
```
Chops exactly `Count` amount of letters right out of the string starting from `Index`. 

### `Reverse`
```lua
StringBuilder:Reverse(): StringBuilder
```
Reverses the string safely using `utf8.graphemes`. This is the default because it fully supports emojis and multi-language strings! 
*(Note: It's slower than `ReverseBytes()`)*

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
Clears the buffer! *(More accurately, it just resets the end cursor, so it's basically free to call)*

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
StringBuilder:SetLength(Length: number): boolean
```
Manually sets the length of the string!
- If it's smaller, it instantly truncates your string.  
- If it's larger than your current capacity, it forces a buffer expansion.
Returns `true` if successful, or `false` if your length is negative.

### `GetCapacity`
```lua
StringBuilder:GetCapacity(): number
```
Returns your current capacity in bytes.

### `EnsureCapacity`
```lua
StringBuilder:EnsureCapacity(EnsuredCapacity: number): (boolean, number)
```
Makes sure your buffer is at least as big as `EnsuredCapacity`! Returns `true` if it had to/could resize, alongside your new capacity. 
!!! warning "This is capped by your `StringBuilder`'s max capacity, so be sure to check if the returned capacity is enough!"

### `SetCapacity`
```lua
StringBuilder:SetCapacity(Capacity: number): number
```
Manually set the capacity safely! It resizes the buffer, and any out of bounds data just gets cut off. Returns the new actual capacity (capped by your max capacity!).

### `GetMaxCapacity`
```lua
StringBuilder:GetMaxCapacity(): number
```
Returns the max capacity in bytes.

### `SetMaxCapacity`
```lua
StringBuilder:SetMaxCapacity(MaxCapacity: number)
```
Manually sets your absolute max capacity. If you try to pass something less than your current capacity, it just silently ignores it.

### `GetFreeSpace`
```lua
StringBuilder:GetFreeSpace(): number
```
Returns your available writable space in bytes.

### `GetTotalFreeSpace`
```lua
StringBuilder:GetTotalFreeSpace(): number
```
Returns your max writable space in bytes.

---

## Extraction & Memory

### `ToString`
```lua
StringBuilder:ToString(): string
```
Returns the fully built string!  
*(You can also just use `tostring(stringBuilder)` or `print(stringBuilder)`)*

### `Destroy`
```lua
StringBuilder:Destroy()
```
Destroys the object. Leaves the buffer to be cleaned up by the garbage collector automatically since there's no way to do it manually!

---

## Packing & Compression

These are mostly for internal use and networking, but they're here if you want them!

### `Pack`
```lua
StringBuilder:Pack(): buffer
```
Packs the StringBuilder's data and metadata all together into a buffer! 

### `Compress`
```lua
StringBuilder:Compress(CompressionLevel: number?): buffer
```
Compresses the StringBuilder with Zstd 
`CompressionLevel` is optional and must range from `-7 to 22`: higher means more compression at the cost of more time. Returns a packed and compressed buffer.

### `FromBuffer`
```lua
StringBuilder.FromBuffer(data: buffer): StringBuilder?
```
Returns a `StringBuilder` object right back from a compressed (or packed) StringBuilder buffer. Returns `nil` if something is wrong.