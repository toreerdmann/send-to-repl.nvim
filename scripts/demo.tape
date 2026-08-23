Output demo.gif

Set FontSize 14
Set Width 1200
Set Height 650
Set Padding 16
Set Theme "TokyoNight"
Set TypingSpeed 50ms

# Launch isolated test drive
Hide
Type "./scripts/test_drive.sh"
Enter
Sleep 2s
Show

# Navigate to Cell 1
Type "17G"
Sleep 1s

# Demo 1: Send single line
Type " "
Type "l"
Sleep 2.5s

# Demo 2: Send second line
Type "j"
Sleep 500ms
Type " "
Type "l"
Sleep 1.5s

# Demo 3: Jump into Cell 2 and send entire cell (# %%)
Type "23G"
Sleep 800ms
Type " "
Type "c"
Sleep 2.5s

# Demo 4: Visual selection on loop in Cell 3
Type "29G"
Sleep 600ms
Type "Vj"
Sleep 800ms
Type " "
Enter
Sleep 2.5s

# Demo 5: Focus REPL window and evaluate expression
Type " "
Type "rt"
Sleep 800ms
Type "result * 2"
Enter
Sleep 3s
