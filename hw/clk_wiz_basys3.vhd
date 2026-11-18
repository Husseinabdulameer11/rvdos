library ieee;
use ieee.std_logic_1164.all;

library UNISIM;
use UNISIM.VComponents.all;

-- Generates 25 MHz from the Basys3's 100 MHz input oscillator (pin W5),
-- using the Artix-7's dedicated MMCM hard block rather than any kind of
-- simple counter-based clock division -- a counter divides an existing
-- clock's edges, which works but produces a clock with much worse jitter
-- and no phase control; the MMCM is purpose-built silicon for exactly
-- this job and is what real designs use.
--
-- VCO = 100MHz * 10.0 / 1 = 1000MHz (within the Artix-7's legal VCO
-- range), then divided by 40 to get exactly 25MHz with zero frequency
-- error -- not an approximation.
--
-- Single-clock-domain design: this 25MHz clock drives the ENTIRE CPU,
-- not just the video timing. Simplest correct choice for first hardware
-- bring-up (see cpu_top.vhd / README for why this is a stretch-goal
-- item, not a bug, to eventually split into separate CPU/pixel clock
-- domains with proper crossing).
--
-- UNISIM primitives (MMCME2_BASE, BUFG) are Xilinx-specific and only
-- resolve inside Vivado -- this file cannot be simulated in GHDL, and
-- isn't meant to be. cpu_top.vhd itself is unaffected and still
-- simulates exactly as before; this is purely an FPGA-synthesis-only
-- wrapper layer on top.

entity clk_wiz_basys3 is
    port (
        clk_100mhz : in  std_logic;
        clk_25mhz  : out std_logic;
        locked     : out std_logic
    );
end entity clk_wiz_basys3;

architecture rtl of clk_wiz_basys3 is
    signal clkfb, clk_25_unbuf : std_logic;
begin

    mmcm_inst: MMCME2_BASE
        generic map (
            CLKIN1_PERIOD     => 10.0,  -- 100 MHz input = 10 ns period
            CLKFBOUT_MULT_F   => 10.0,  -- VCO = 100MHz * 10 / 1 = 1000MHz
            DIVCLK_DIVIDE     => 1,
            CLKOUT0_DIVIDE_F  => 40.0,  -- 1000MHz / 40 = 25MHz exactly
            CLKOUT0_DUTY_CYCLE => 0.5,
            CLKOUT0_PHASE      => 0.0,
            BANDWIDTH          => "OPTIMIZED"
        )
        port map (
            CLKIN1   => clk_100mhz,
            CLKFBIN  => clkfb,
            CLKFBOUT => clkfb,
            CLKOUT0  => clk_25_unbuf,
            LOCKED   => locked,
            PWRDWN   => '0',
            RST      => '0'
        );

    bufg_out: BUFG
        port map (
            I => clk_25_unbuf,
            O => clk_25mhz
        );

end architecture rtl;
