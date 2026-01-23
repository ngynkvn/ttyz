# VHS tape for ttyz progress example
# Demonstrates animated progress bars and spinners

Output tapes/progress.gif

Require zig

Set Shell "bash"
Set FontSize 14
Set Width 900
Set Height 500
Set Theme "Catppuccin Mocha"

Hide
Type "zig build progress 2>/dev/null"
Enter
Sleep 500ms
Show

# Watch the progress animation complete
Sleep 6s

# The progress completes and shows "Complete!" - exit
Type "q"

Sleep 500ms
