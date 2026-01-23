# VHS tape for ttyz demo example
# Comprehensive demo showing all features

Output tapes/demo.gif

Require zig

Set Shell "bash"
Set FontSize 14
Set Width 1000
Set Height 600
Set Theme "Catppuccin Mocha"

Hide
Type "zig build demo 2>/dev/null"
Enter
Sleep 500ms
Show

# Overview tab
Sleep 2s

# Switch to Colors tab
Tab
Sleep 2s

# Switch to Events tab
Tab
Sleep 1s

# Type some keys
Type "test"
Sleep 1s

# Switch to Boxes tab
Tab
Sleep 2s

# Switch to Text tab
Tab
Sleep 2s

# Quit
Type "q"

Sleep 500ms
