#!/usr/bin/env bash
# run_flint_tests.sh -- run every tests/flint/*.FLT on RVDOS in the
# headless emulator and compare the screen with the matching .OUT file.
#   tests/run_flint_tests.sh            (from the project folder, after build_os.sh)
cd "$(dirname "$0")/.."
EMU=tools/rvemu_headless
[ -x $EMU ] || gcc -O2 -DRVEMU_HEADLESS -Ios -o $EMU tools/rvemu.c os/font.c || exit 1
pass=0; fail=0
for src in tests/flint/*.FLT; do
    name=$(basename "$src" .FLT)
    disk=$(mktemp)
    rm -f "$disk"
    python3 tools/rvdisk.py "$disk" put "$src" > /dev/null
    # boot, clear the banner, run the program; the program's output is
    # everything between the command line and the next A> prompt
    $EMU os/rvdos_text.hex os/rvdos_rodata.hex --disk="$disk" --steps=${STEPS:-80000000} \
         --screen --keys="cls\n$name\n" 2>/dev/null \
      | sed 's/^|//' | awk -v cmd="A>$name" '
            $0 == cmd { on = 1; next }
            on && /^A>/ { exit }
            on { print }' > /tmp/flint_got.txt
    rm -f "$disk"
    if diff -u "tests/flint/$name.OUT" /tmp/flint_got.txt > /tmp/flint_diff.txt; then
        pass=$((pass + 1)); echo "ok    $name"
    else
        fail=$((fail + 1)); echo "FAIL  $name"; sed 's/^/      /' /tmp/flint_diff.txt
    fi
done
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
