# Luacsv

Luacsv is a small utility (about 200 lines of Lua) that lets you **run CSV files as programs**, using Lua as a lightweight DSL (domain-specific language) for interpreting and manipulating CSV content.

## What It Does

- Accepts one or more CSV file paths as command-line arguments.
- Opens and parses each CSV file.
- Identifies **"corners"**, which are defined as:
  > A non-empty cell that has both the cell above it and the cell to its left empty.  
  > (The top row and leftmost column are treated as empty by default.)

This structure makes it easy to treat certain cells as the start of meaningful blocks or logic regions.

## Customization

The function `load_standard_lib(state)` is a good place to define custom behavior and utilities for your specific use case.

For example, you can define helper functions, shorthand syntax, or reusable patterns to make your CSV logic cleaner.

## Getting Started

1. Read the ~200 lines of code. It's short and understandable.
2. Run the provided test CSV file.
3. Modify and experiment to suit your use case.
4. Reach out with questions if anything is unclear — good questions may be added to this README.

## License

This project is released into the **public domain**.  
You may use, modify, distribute, and sublicense it freely and without restriction.

---

Feel free to reach out if you have suggestions or want to share how you're using it!

