# build.tcl -- build RVDOS for the Basys3 and program the board.
#
#   vivado -mode batch -source hw/build.tcl                 (build + program)
#   vivado -mode batch -source hw/build.tcl -tclargs nopgm  (build only)
#   or, in the Vivado Tcl shell:  source hw/build.tcl
#
# Non-project mode. It works from the repo root, so the ROM images
# os/rvdos_text.hex and os/rvdos_rodata.hex are found by the relative
# names that are basys3_top's generic defaults.
# Output: build/rvdos.bit plus utilization and timing reports.

set here [file dirname [file normalize [info script]]]
cd [file dirname $here]
file mkdir build

set sources {
    mem_pkg.vhd alu.vhd control_unit.vhd data_ram.vhd debounce.vhd
    ex_mem_reg.vhd forward_unit.vhd framebuffer_ram.vhd hazard_detect.vhd
    id_ex_reg.vhd if_id_reg.vhd imm_mux.vhd instr_decoder.vhd instr_rom.vhd
    instr_rom_hex.vhd keyboard.vhd load_extend.vhd mem_wb_reg.vhd
    palette_ram.vhd pc_reg.vhd register_file.vhd reset_sync.vhd
    rodata_rom.vhd store_align.vhd video_scanout.vhd ps2_keyboard.vhd
    cpu_top.vhd clk_wiz_basys3.vhd basys3_top.vhd
}
read_vhdl -vhdl2008 [lmap f $sources {file join hw $f}]
read_xdc hw/basys3.xdc

synth_design -top basys3_top -part xc7a35tcpg236-1
report_utilization -file build/utilization_synth.txt
opt_design
place_design
route_design
report_utilization -file build/utilization.txt
report_timing_summary -file build/timing.txt
write_bitstream -force build/rvdos.bit

# timing check: a negative slack means the design may misbehave at 25 MHz
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "Worst setup slack: $wns ns (must be >= 0)"

if {[lindex $argv 0] ne "nopgm"} {
    open_hw_manager
    connect_hw_server
    open_hw_target
    set dev [lindex [get_hw_devices xc7a35t*] 0]
    current_hw_device $dev
    set_property PROGRAM.FILE build/rvdos.bit $dev
    program_hw_devices $dev
    close_hw_manager
    puts "Board programmed. RVDOS should be on the VGA screen."
}
