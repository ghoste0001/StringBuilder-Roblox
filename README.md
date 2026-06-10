<picture>
<img src="./docs/banner_rounded.png" style="height:100px;"></img>
</picture>
<br>
<strong>A blazing-fast string builder library for Luau, performing significantly faster than native string concatenation.</strong>
<br><br>

<a href="https://devforum.roblox.com/t/stringbuilder-high-performance-buffer-based-string-manipulation"><img src="./svgs/roblox_forum-icon.svg"></img></a>
<a href="https://ghoste0001.github.io/StringBuilder-Roblox/"><img src="./svgs/documentation_learn.svg"></img></a>

---

Here's a benchmark comparing Native, Table and StringBuilder concatenation (20k iterations, 3 run averages):

```
23:22:39.158  Native concat: 8.877099566666098  -  Edit
23:22:39.158  Table.concat: 0.023049566666789662  -  Edit
23:22:39.158  StringBuilder: 0.04590246666581758  -  Edit
23:22:39.159  Table.concat vs native: 385x  -  Edit
23:22:39.159  StringBuilder vs native: 193x  -  Edit
23:22:39.159  Table.concat vs StringBuilder: 2x  -  Edit
```


<details>
  <summary>Benchmarking Script</summary><br>
  
  ```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StringBuilder = require(ReplicatedStorage:WaitForChild("StringBuilder"))

task.wait(3) -- wait for the game to load and stabilize if playtesting

local TEST_RUNS = 20000
local gc_wait = 3 -- make it more fair by allowing gc to finish before the next benchmark
local t = {}

-- native concatenation
local function test_native()
	local s = ""

	local start = os.clock()
	for i = 1, TEST_RUNS do
		s = s .. "var " .. i .. " = " .. i
	end
	local dt = os.clock() - start

	s = nil
	return dt
end

-- table.concat
local function test_tableconcat()
	table.clear(t)

	local start = os.clock()
	for i = 1, TEST_RUNS do
		t[i] = "var " .. i .. " = " .. i
	end
	local s = table.concat(t)
	local dt = os.clock() - start

	s = nil
	table.clear(t)

	return dt
end

-- StringBuilder
local function test_stringbuilder()
	local sb = StringBuilder.new() -- non pre-allocated stringbuilder (so including resize costs)

	local start = os.clock()
	for i = 1, TEST_RUNS do
		sb:AppendList("var ", i, " = ", i)
	end
	local s = sb:ToString()
	local dt = os.clock() - start

	return dt
end

-- multiple runs
local RUNS = 3

-- function for getting average results over x runs
local function avg(fn)
	local total = 0
	for _ = 1, RUNS do
		task.wait(gc_wait)
		total += fn()
	end
	return total / RUNS
end

local native = avg(test_native)
local concat = avg(test_tableconcat)
local sb = avg(test_stringbuilder)

-- Print results:
print("Native concat:", native)
print("Table.concat:", concat)
print("StringBuilder:", sb)

print("Table.concat vs native:", math.round(native / concat) .. "x")
print("StringBuilder vs native:", math.round(native / sb) .. "x")
print("Table.concat vs StringBuilder:", math.round(sb / concat) .. "x")
  ```
</details>

<details>
  <summary>Example Code</summary><br>
  
  ```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StringBuilder = require(ReplicatedStorage:WaitForChild("StringBuilder"))

local textBuilder = StringBuilder.new() -- You can specify the builder's starting size in bytes if needed

-- Right now the textBuilder is empty, but we can add some text to it:
textBuilder:Append("Hello, World!")

-- Now the textBuilder contains "Hello, World!", so if we do:
print(textBuilder) -- or print(textBuilder:ToString())
-- The output is going to be: "Hello, World!"

-- Lets replace every occurrence of "World" with my name
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
  ```
</details>

---

> [!NOTE]  
> There may be **bugs**, so be sure to report any you encounter.
