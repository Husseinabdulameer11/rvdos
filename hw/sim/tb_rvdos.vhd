library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

-- Boots the real RVDOS image (build_os.sh output) on the VHDL CPU, types
-- "DIR" and "HELLO" on the keyboard port, and writes the framebuffer to
-- tb_rvdos_fb.txt (one byte per line, palette indices). Comparing that
-- with rvemu's framebuffer for the same keys cross-checks the hardware
-- against the emulator the OS was developed on (see tests/ghdl_rvdos.sh).
--
-- Each key is pressed only after the previous one was read, like
-- rvemu's scripted keys.

entity tb_rvdos is
    generic (CYCLES : integer := 3000000);
end entity;

architecture sim of tb_rvdos is
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal key_valid : std_logic := '0';
    signal key_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal red, green, blue : std_logic_vector(7 downto 0);
    signal done : boolean := false;

    constant KEYS : string := "DIR" & LF & "HELLO" & LF;
begin

    dut: entity work.cpu_top
        generic map (
            HEX_FILE => "rvdos_text.hex", ROM_WORDS => 12288,
            RODATA_HEX_FILE => "rvdos_rodata.hex", RODATA_WORDS => 6144,
            RAM_WORDS => 8192
        )
        port map (clk => clk, rst => rst, red => red, green => green, blue => blue,
                  key_valid => key_valid, key_data => key_data);

    clk_gen: process
    begin
        while not done loop
            clk <= '0'; wait for 20 ns;
            clk <= '1'; wait for 20 ns;    -- 25 MHz
        end loop;
        wait;
    end process;

    stim: process
        alias kbd_avail is << signal .tb_rvdos.dut.u_keyboard.available : std_logic >>;
        alias fb is << signal .tb_rvdos.dut.u_framebuffer_ram.mem : work.mem_pkg.word_array(0 to 16383) >>;
        file f : text;
        variable l : line;
        variable n : integer := 0;
    begin
        rst <= '1';
        for i in 1 to 5 loop wait until rising_edge(clk); end loop;
        rst <= '0';
        -- let it boot (clear screen, format the RAM disk, print the banner)
        for i in 1 to 600000 loop wait until rising_edge(clk); end loop;
        n := 600000;
        for k in KEYS'range loop
            key_data  <= std_logic_vector(to_unsigned(character'pos(KEYS(k)), 8));
            key_valid <= '1';
            wait until rising_edge(clk);
            key_valid <= '0';
            wait for 1 ns;     -- let the keyboard's 'available' flag update first
            -- wait until the CPU has read it, then a little more
            while kbd_avail = '1' loop wait until rising_edge(clk); n := n + 1; end loop;
            for i in 1 to 20000 loop wait until rising_edge(clk); end loop;
            n := n + 20000;
        end loop;
        while n < CYCLES loop wait until rising_edge(clk); n := n + 1; end loop;

        file_open(f, "tb_rvdos_fb.txt", write_mode);
        for i in 0 to 320 * 200 - 1 loop
            write(l, to_integer(unsigned(fb(i / 4)(8 * (i mod 4) + 7 downto 8 * (i mod 4)))));
            writeline(f, l);
        end loop;
        file_close(f);
        report "tb_rvdos: framebuffer written after " & integer'image(n) & " cycles";
        done <= true;
        wait;
    end process;
end architecture;
