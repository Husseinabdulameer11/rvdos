library ieee;
use ieee.std_logic_1164.all;
use work.mem_pkg.all;

-- Board-specific glue only. All the actual CPU/video logic lives in
-- cpu_top.vhd and is completely unaware this wrapper exists -- this file
-- adds exactly the things a real board needs that a testbench doesn't:
-- a real clock (not a `wait for 5 ns` loop), a debounced/synchronized
-- reset (not a signal a testbench process drives directly), and pin-
-- width matching for the physical VGA DAC.
--
-- Single clock domain: clk_25mhz drives the CPU, the pipeline, and the
-- video scanout, all together. Simplest correct choice for first
-- hardware bring-up -- see clk_wiz_basys3.vhd's comments for why.

entity basys3_top is
    generic (
        -- Defaults build RVDOS. Paths are relative to the directory Vivado
        -- runs in (hw/build.tcl runs from the repo root). Block RAM budget on the
        -- XC7A35T (50 x RAMB36): framebuffer 16 + ROM 12 + rodata 6 + RAM 8 = 42.
        HEX_FILE  : string := "os/rvdos_text.hex";
        ROM_WORDS : integer := 12288;
        RODATA_HEX_FILE : string := "os/rvdos_rodata.hex";
        RODATA_WORDS    : integer := 6144;
        RAM_WORDS       : integer := 8192;
        -- keyboard layout for the USB keyboard: "NO" (Norwegian) or "US"
        KBD_LAYOUT      : string  := "NO"
    );
    port (
        clk_100mhz : in  std_logic; -- W5, the board's only oscillator
        btnC       : in  std_logic; -- center button, used as reset

        Hsync : out std_logic;
        Vsync : out std_logic;
        vgaRed   : out std_logic_vector(3 downto 0);
        vgaGreen : out std_logic_vector(3 downto 0);
        vgaBlue  : out std_logic_vector(3 downto 0);

        -- USB keyboard, via the board's USB-to-PS/2 PIC (USB HOST port J2)
        PS2Clk  : in std_logic;
        PS2Data : in std_logic;

        -- LD0-LD7 show the last raw scan code byte received, LD15 lights
        -- once any byte has arrived: a quick check that the keyboard works
        led : out std_logic_vector(15 downto 0)
    );
end entity basys3_top;

architecture rtl of basys3_top is

    signal clk_25mhz, mmcm_locked : std_logic;
    signal btn_synced, rst_debounced, rst : std_logic;

    signal video_active_i : std_logic;
    signal red_i, green_i, blue_i : std_logic_vector(7 downto 0);

    signal key_valid_i, scan_valid_i : std_logic;
    signal key_data_i, scan_code_i   : std_logic_vector(7 downto 0);
    signal last_scan : std_logic_vector(7 downto 0) := (others => '0');
    signal seen_scan : std_logic := '0';

begin

    u_clk_wiz: entity work.clk_wiz_basys3
        port map (
            clk_100mhz => clk_100mhz,
            clk_25mhz  => clk_25mhz,
            locked     => mmcm_locked
        );

    -- reset conditioning chain: raw async button -> 2-flop synchronizer
    -- -> debounce filter -> gated by MMCM lock (holding the CPU in reset
    -- until the clock is actually stable is standard practice; releasing
    -- reset into an unlocked/still-settling clock risks the pipeline
    -- registers coming up in an inconsistent state)
    u_reset_sync: entity work.reset_sync
        port map (clk => clk_25mhz, async_in => btnC, sync_out => btn_synced);

    u_debounce: entity work.debounce
        port map (clk => clk_25mhz, noisy_in => btn_synced, clean_out => rst_debounced);

    rst <= rst_debounced or not mmcm_locked;

    u_cpu: entity work.cpu_top
        generic map (HEX_FILE => HEX_FILE, ROM_WORDS => ROM_WORDS,
                     RODATA_HEX_FILE => RODATA_HEX_FILE, RODATA_WORDS => RODATA_WORDS,
                     RAM_WORDS => RAM_WORDS)
        port map (
            clk => clk_25mhz, rst => rst,
            hsync => Hsync, vsync => Vsync, video_active => video_active_i,
            red => red_i, green => green_i, blue => blue_i,
            key_valid => key_valid_i, key_data => key_data_i
        );

    u_ps2: entity work.ps2_keyboard
        generic map (LAYOUT => KBD_LAYOUT)
        port map (
            clk => clk_25mhz, rst => rst,
            ps2_clk => PS2Clk, ps2_data => PS2Data,
            key_valid => key_valid_i, key_data => key_data_i,
            scan_valid => scan_valid_i, scan_code => scan_code_i
        );

    process(clk_25mhz)
    begin
        if rising_edge(clk_25mhz) then
            if scan_valid_i = '1' then
                last_scan <= scan_code_i;
                seen_scan <= '1';
            end if;
        end if;
    end process;

    led <= seen_scan & "0000000" & last_scan;

    -- Basys3's VGA connector only wires 4 DAC bits per channel (see
    -- basys3.xdc) -- truncate here at the board boundary, not inside
    -- cpu_top/video_scanout, which stay board-agnostic and keep their
    -- full 8-bit color for simulation/future higher-bit-depth hardware.
    vgaRed   <= red_i(7 downto 4)   when video_active_i = '1' else (others => '0');
    vgaGreen <= green_i(7 downto 4) when video_active_i = '1' else (others => '0');
    vgaBlue  <= blue_i(7 downto 4)  when video_active_i = '1' else (others => '0');

end architecture rtl;
