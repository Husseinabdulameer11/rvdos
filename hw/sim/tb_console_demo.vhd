library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Loads console_demo_text.hex / console_demo_rodata.hex -- real GCC
-- output using console.c's persistent cursor_col/cursor_row (.bss,
-- mutable global state), printing 4 lines via console_puts. Checks that
-- line 2 actually rendered at the right row -- if cursor_row's state
-- didn't persist correctly across console_putc calls, every character
-- would land on row 0 instead of advancing.

entity tb_console_demo is
end entity;

architecture sim of tb_console_demo is

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal red, green, blue : std_logic_vector(7 downto 0);
    signal errors : integer := 0;

begin

    dut: entity work.cpu_top
        generic map (
            HEX_FILE => "console_demo_text.hex", ROM_WORDS => 1024,
            RODATA_HEX_FILE => "console_demo_rodata.hex", RODATA_WORDS => 128
        )
        port map (clk => clk, rst => rst, red => red, green => green, blue => blue);

    clk_gen: process
    begin
        while now < 9000000 ns loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    monitor: process(clk)
        alias h_count_p is << signal .tb_console_demo.dut.u_video_scanout.h_count : integer range 0 to 799 >>;
        alias v_count_p is << signal .tb_console_demo.dut.u_video_scanout.v_count : integer range 0 to 524 >>;
        variable line1_r_count : integer := 0;
        variable line1_gap_count : integer := 0;
        variable line2_c_count : integer := 0;
    begin
        if rising_edge(clk) and rst = '0' then
            -- Checking the SECOND pass through each row, not the first --
            -- the first pass through v_count=40 happens only ~320,000ns
            -- in, before the CPU (executing dozens of individual
            -- fill_rect calls per glyph) has necessarily finished
            -- drawing. By the second full frame, drawing is certainly
            -- done; the picture is then stable frame to frame.

            -- line 1 ("RISC-V BOOT"), row 0: 'R' top-left, always lit -> white
            if v_count_p = 40 and h_count_p = 2 then
                line1_r_count := line1_r_count + 1;
                if line1_r_count = 2 then
                    report "line1 R top-left -> " & to_hstring(red) & to_hstring(green) & to_hstring(blue);
                    if red /= x"FF" or green /= x"FF" or blue /= x"FF" then
                        report "FAIL: expected white at line 1's 'R'" severity error;
                        errors <= errors + 1;
                    end if;
                end if;
            end if;

            -- line 1, gap between 'R' (cols 0-4) and 'I' (starts col 6) -> black
            if v_count_p = 40 and h_count_p = 12 then
                line1_gap_count := line1_gap_count + 1;
                if line1_gap_count = 2 then
                    report "line1 gap after R -> " & to_hstring(red) & to_hstring(green) & to_hstring(blue);
                    if red /= x"00" or green /= x"00" or blue /= x"00" then
                        report "FAIL: expected black in the gap after 'R'" severity error;
                        errors <= errors + 1;
                    end if;
                end if;
            end if;

            -- line 2 ("CPU: RV32IM"), row 8: 'C' row 1 of its glyph lit at
            -- col 0 -> screen row 9 -> v_count = 40 + 9*2 = 58
            if v_count_p = 58 and h_count_p = 2 then
                line2_c_count := line2_c_count + 1;
                if line2_c_count = 2 then
                    report "line2 C (row1 of glyph) -> " & to_hstring(red) & to_hstring(green) & to_hstring(blue);
                    if red /= x"FF" or green /= x"FF" or blue /= x"FF" then
                        report "FAIL: expected white -- line 2 may not have advanced correctly" severity error;
                        errors <= errors + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    stim: process
    begin
        wait for 12 ns;
        rst <= '0';
        wait for 8990000 ns; -- comfortably past two full frames (2 x 4,200,000ns)

        if errors = 0 then
            report "PASS: multi-line console output correct -- cursor state (.bss) persisted across calls";
        else
            report integer'image(errors) & " TEST(S) FAILED" severity error;
        end if;
        wait;
    end process;

end architecture sim;
