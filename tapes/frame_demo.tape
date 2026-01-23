# VHS tape for ttyz frame_demo example
# Demonstrates the Frame abstraction with border styles

Output tapes/frame_demo.gif

Require zig

Set Shell "bash"
Set FontSize 14
Set Width 1000
Set Height 600
Set Theme "Catppuccin Mocha"

Hide
Type "zig build frame_demo 2>/dev/null"
Enter
Sleep 500ms
Show

# Show initial state (Single border selected)
Sleep 2s

# Navigate through border styles
Right
Sleep 1s

Right
Sleep 1s

Right
Sleep 1s

# Go back
Left
Left
Sleep 1s

# Quit
Type "q"

Sleep 500ms
