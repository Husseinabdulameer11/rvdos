#!/usr/bin/env bash
# smoke.sh -- quick end-to-end checks of RVDOS in the headless emulator:
# commands, ED, every sample program and every game. Run after build_os.sh.
cd "$(dirname "$0")/.."
EMU=tools/rvemu_headless
[ -x $EMU ] || gcc -O2 -DRVEMU_HEADLESS -Ios -o $EMU tools/rvemu.c os/font.c || exit 1
pass=0; fail=0
check() {   # check NAME STEPS KEYS EXPECTED-REGEX...
    local name=$1 steps=$2 keys=$3; shift 3
    local out; out=$($EMU os/rvdos_text.hex os/rvdos_rodata.hex --steps=$steps --screen --keys="$keys" 2>&1)
    for want in "$@"; do
        if ! grep -qE -- "$want" <<< "$out"; then
            echo "FAIL  $name: no match for /$want/"; echo "$out" | sed 's/^/      /'; fail=$((fail+1)); return
        fi
    done
    if grep -qE "unimplemented|illegal" <<< "$out"; then echo "FAIL  $name: CPU halted"; fail=$((fail+1)); return; fi
    echo "ok    $name"; pass=$((pass+1))
}
check boot      20000000 ''                       'RVDOS 2.0' 'Cold start' '^\|A>'
check dir       40000000 'dir\n'                  'ED +COM : FLINT +COM : PONG +COM' 'README +TXT'
check dir-wild  40000000 'dir *.flt\n'            'DODGE +FLT' '^\|A>$'
check stat      40000000 'stat\n'                 'ROM  PONG.COM' 'bytes free' 'TPA: [0-9]+ bytes'
check type      40000000 'type readme.txt\n\w '    'Flint in a nutshell' 'survive the reset button'
check unknown   40000000 'frob\n'                 '^\|FROB\?'
check ren-pip   80000000 'ren x.flt=hello.flt\npip y.flt=x.flt\ndir hel*\ny\n' '^\|NO FILE' 'Hello from Flint'
check era-all   80000000 'era *.*\ny\ndir\n'      'ALL FILES' 'TETRIS +COM$'
check format    80000000 'era *.*\ny\nformat\ny\ndir\n' 'A: FORMATTED' 'HELLO +FLT'
check history   40000000 'ver\n\x05\n'            'Flint 1.0' '^\|A>ver$'
check hello     40000000 'hello\n'                '5 squared is 25'
check primes   100000000 'primes\n'               '168 primes up to 1000'
check guess     60000000 'guess\n50\n'            'number 1-100' '(Higher|Lower|Got it)'
check mandel   120000000 'mandel\n'               ''
check dodge    160000000 'dodge\n\W\Wq'             'SCORE' 'GAME OVER'
check ed-new   100000000 'ed n.flt\nprint 6*7\n\eX\nn\n' '^\|42$'
check ed-quit  100000000 'ed hello.flt\nxx\eQy\nhello\n' 'Hello from Flint'
check repl     80000000  'flint\n2+2\nbye\n'      '^\|4$'
check pong     80000000  'pong\n \W\Wq'           '^\|A>'
check snake    80000000  'snake\n \W\Wq'          '^\|A>'
check tetris   80000000  'tetris\n \W\Wq'         '^\|A>'
check halt     20000000  'halt\n'                 'SYSTEM HALTED'
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
