# VHS tape for ttyz hello example
# Demonstrates basic Frame rendering with Layout

Output tapes/hello.gif

Require zig

Set Shell "bash"
Set FontSize 16
Set Width 800
Set Height 400
Set Theme "Catppuccin Mocha"

Hide
Type "zig build hello 2>/dev/null"
Enter
Sleep 500ms
Show

Sleep 2s

# Press any key to exit
Type "q"

Sleep 500ms
