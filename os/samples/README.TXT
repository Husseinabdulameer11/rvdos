RVDOS 2.0 - a CP/M-style OS for this RV32IM CPU

  DIR [pat]    list files (DIR *.FLT)
  STAT         sizes and free space
  TYPE file    show a file
  ED file      edit a file (ESC for the menu)
  ERA file     erase       REN new=old  rename
  PIP new=old  copy        HELP         all commands
  NAME         run NAME.COM or NAME.FLT

Flint is the built-in language. Try:
  HELLO        run HELLO.FLT
  ED HELLO.FLT change it
  FLINT        type statements, see them run

Flint in a nutshell (one statement per line):
  var x = 5        var a[10]       a[2] = x * 3
  if x > 3 / elif x < 0 / else / end
  while x > 0 / end
  for i = 1 to 10 step 2 / end
  func add(a, b) / return a + b / end
  print "x=", x    print "stay on this line";
  key() getkey() input() rnd(n) len(a)
  cls() at(col,row) color(fg,bg) putch(c)
  fill(col,row,c) pixel(x,y,c) rect(x,y,w,h,c)
  palette(i,0xRRGGBB) wait(ms)

^C stops a program. Files live in RAM: they
survive the reset button, not a power cycle.
