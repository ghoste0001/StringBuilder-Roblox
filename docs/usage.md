# Usage Guide

Using `StringBuilder` is super straightforward. Here's a quick walkthrough of how to use it!

## Initialization
First things first, require the module and make a new builder.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StringBuilder = require(ReplicatedStorage:WaitForChild("StringBuilder"))

-- Initialize with default settings
local textBuilder = StringBuilder.new() 

-- Alternatively, specify the builder's starting capacity in bytes
-- local textBuilder = StringBuilder.new(128) 
```

## Appending Text
Appending data writes it directly into the builder's buffer.

```lua
-- Add some text to it:
textBuilder:Append("Hello, World!")

print(textBuilder) -- You can also use textBuilder:ToString()
-- Output: "Hello, World!"
```

!!! info "Formatting"
    The `Append` function does **not** add spaces automatically. You can include spaces manually, or use the `:Space()` method!

    ```lua
    textBuilder:Append(" <- Like this")

    textBuilder:Space()
    textBuilder:Append("<- Or like this!")
    ```

## Replacing Content
You can easily swap occurrences of a substring dynamically.

```lua
textBuilder:Append("Hello, World!")
-- Replace every occurrence of the word "World" with "Ghost"
textBuilder:Replace("World", "Ghost")

print(textBuilder)
-- Output: "Hello, Ghost!"
```

## Method Chaining
StringBuilder also supports method chaining, so you can just string your calls together!

```lua
local builder = StringBuilder.new()

builder:Append("Hello"):Space():Append("Again!")

print(builder) 
-- Output: "Hello Again!"
```

!!! tip "Direct Calls vs Method Calls"
    Instead of calling methods with the colon operator (`:`), you can call them directly to avoid Roblox method call overhead.

    ```lua
    -- Standard (Method)
    textBuilder:Append(" Let's continue!")

    -- Direct
    StringBuilder.Append(textBuilder, " Let's continue!")
    ```
    *Pick your poison: doing this offers minor performance gains, but is slightly less intuitive.*
