# VHS tape for ttyz kitty example
# Demonstrates Kitty graphics protocol for images
# Note: Requires a Kitty-compatible terminal (Kitty, WezTerm, Ghostty)

Output tapes/kitty.gif

Require zig

Hide
Set Shell "bash"
Set FontSize 12
Set Width 1000
Set Height 700
Set Theme "Catppuccin Mocha"

Type "zig build kitty 2>/dev/null"
Enter
Sleep 500ms
Show

# Wait for images to render
Sleep 4s

# Press key to clear and exit
Type "q"

Sleep 500ms
