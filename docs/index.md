---
hide:
- navigation
- toc
---

# StringBuilder

> A blazing-fast string builder library for Luau, performing significantly faster than native string concatenation.

---

## Overview

StringBuilder provides nearly full coverage of the robust C# `StringBuilder` API. It is memory efficient, incredibly powerful, and **hundreds of times faster** than native Roblox string concatenation (`"a" .. "b"`). 

Inspired by depthso's original concept, but remade completely from the ground up using **buffers** for absolute maximum performance.

### Key Features

- 🚀 **Blazing Fast**: Uses raw buffers for manipulation to sidestep standard string memory allocation bottlenecks.
- 🗜️ **Pack & Compress**: Built-in methods to pack and efficiently compress your `StringBuilder` objects into smaller footprints (perfect for DataStores or networking).
- 🛠️ **Familiar API**: Syntax mapping closely to the C# StringBuilder API.