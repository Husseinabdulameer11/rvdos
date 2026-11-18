#!/usr/bin/env bash
# run_vhdl_tests.sh -- run every self-checking VHDL testbench in hw/sim with
# GHDL. A testbench passes if GHDL exits cleanly and nothing it printed is an
# error or failure. (tb_live needs the SDL bridge and tb_rvdos is checked by
# tests/ghdl_rvdos.sh, so both are left out here.)
#   tests/run_vhdl_tests.sh            (from anywhere; needs ghdl)
cd "$(dirname "$0")/../hw/sim" || exit 1
W=$(mktemp -d)
ghdl -i --std=08 -fsynopsys --workdir="$W" \
    $(ls ../*.vhd | grep -v "clk_wiz_basys3\|basys3_top") \
    $(ls tb_*.vhd | grep -v "tb_live\|tb_rvdos") > /dev/null
pass=0; fail=0
for src in tb_*.vhd; do
    tb=$(basename "$src" .vhd)
    case $tb in tb_live|tb_rvdos) continue;; esac
    if ! ghdl -m --std=08 -fsynopsys --workdir="$W" "$tb" > "$W/$tb.out" 2>&1; then
        fail=$((fail + 1)); echo "FAIL  $tb (build)"; sed 's/^/      /' "$W/$tb.out" | head -5; continue
    fi
    ghdl -r --std=08 -fsynopsys --workdir="$W" "$tb" --ieee-asserts=disable > "$W/$tb.out" 2>&1
    rc=$?
    if [ $rc -ne 0 ] || grep -qiE "\(assertion (error|failure)\)|error:|FAIL" "$W/$tb.out"; then
        fail=$((fail + 1)); echo "FAIL  $tb"; grep -iE "error|fail" "$W/$tb.out" | head -5 | sed 's/^/      /'
    else
        pass=$((pass + 1)); echo "ok    $tb"
    fi
done
rm -rf "$W"
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
