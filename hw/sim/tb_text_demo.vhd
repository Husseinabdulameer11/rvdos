library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Loads /home/claude/riscv-cpu/text_demo_text.hex and text_demo_rodata.hex
-- -- real GCC output, .text and .rodata extracted and loaded SEPARATELY,
-- proving the new rodata_rom actually closes the Harvard-memory gap:
-- the font table and the "RISC-V" string literal are genuine C const
-- data, unreachable by any load instruction before this fix.
--
-- This checks basic STRUCTURE, not the full glyph shapes -- a lit pixel
-- where 'R' should start, a blank gap between 'R' and 'I'. Confirming
-- the text actually reads "RISC-V" and not some scrambled-but-
-- structurally-plausible garbage is a job for the live SDL2 render
-- (tb_live.vhd), not a pixel-assertion testbench -- font/text rendering
-- correctness is fundamentally a "look at it" check.

entity tb_text_demo is
end entity;

architecture sim of tb_text_demo is

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal red, green, blue : std_logic_vector(7 downto 0);
    signal errors : integer := 0;

begin

    dut: entity work.cpu_top
        generic map (
            HEX_FILE => "text_demo_text.hex", ROM_WORDS => 512,
            RODATA_HEX_FILE => "text_demo_rodata.hex", RODATA_WORDS => 64
        )
        port map (clk => clk, rst => rst, red => red, green => green, blue => blue);

    clk_gen: process
    begin
        while now < 700000 ns loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    monitor: process(clk)
        alias h_count_p is << signal .tb_text_demo.dut.u_video_scanout.h_count : integer range 0 to 799 >>;
        alias v_count_p is << signal .tb_text_demo.dut.u_video_scanout.v_count : integer range 0 to 524 >>;
        variable seen_r_pixel : boolean := false;
        variable seen_gap : boolean := false;
    begin
        if rising_edge(clk) and rst = '0' and v_count_p = 80 then
            -- 'R' starts at logical col 20 -- its top-left pixel is always
            -- lit in this font (column 0, every row of 'R' is lit).
            -- Column formula accounts for the 1-cycle registration delay
            -- established in tb_video.vhd: logical col C reads back at
            -- h_count_p in {2C+1, 2C+2}.
            if (h_count_p = 41 or h_count_p = 42) and not seen_r_pixel then
                seen_r_pixel := true;
                report "R top-left pixel -> " & to_hstring(red) & to_hstring(green) & to_hstring(blue);
                if red /= x"FF" or green /= x"FF" or blue /= x"FF" then
                    report "FAIL: expected white at R's top-left corner" severity error;
                    errors <= errors + 1;
                end if;
            end if;

            -- gap between 'R' (ends at col 34) and 'I' (starts at col 38)
            -- -- col 36 should be blank background
            if (h_count_p = 73 or h_count_p = 74) and not seen_gap then
                seen_gap := true;
                report "gap between R and I -> " & to_hstring(red) & to_hstring(green) & to_hstring(blue);
                if red /= x"00" or green /= x"00" or blue /= x"00" then
                    report "FAIL: expected black in the gap between letters" severity error;
                    errors <= errors + 1;
                end if;
            end if;
        end if;
    end process;

    stim: process
    begin
        wait for 12 ns;
        rst <= '0';
        wait for 690000 ns;

        if errors = 0 then
            report "PASS: basic text structure correct -- watch tb_live.vhd to confirm it actually reads 'RISC-V'";
        else
            report integer'image(errors) & " TEST(S) FAILED" severity error;
        end if;
        wait;
    end process;

end architecture sim;
