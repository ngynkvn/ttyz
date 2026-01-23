# VHS tape for ttyz input example
# Demonstrates keyboard and mouse event handling

Output tapes/input.gif

Require zig

Hide
Set Shell "bash"
Set FontSize 14
Set Width 900
Set Height 500
Set Theme "Catppuccin Mocha"

Type "zig build input 2>/dev/null"
Enter
Sleep 500ms
Show

Sleep 1s

# Type some keys to demonstrate key handling
Type "hello"
Sleep 500ms

Type "world"
Sleep 500ms

# Demonstrate special keys
Space
Sleep 300ms
Tab
Sleep 300ms

# Wait a moment
Sleep 1s

# Quit
Type "q"

Sleep 500ms
