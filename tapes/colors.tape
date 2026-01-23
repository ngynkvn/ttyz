# VHS tape for ttyz colors example
# Demonstrates 16, 256, and true color support

Output tapes/colors.gif

Require zig

Set Shell "bash"
Set FontSize 14
Set Width 900
Set Height 500
Set Theme "Catppuccin Mocha"

Hide
Type "zig build colors 2>/dev/null"
Enter
Sleep 500ms
Show

# Let the color animation run for a few seconds
Sleep 4s

# Quit
Type "q"

Sleep 500ms
