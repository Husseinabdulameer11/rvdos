library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Loads /home/claude/riscv-c/gfx/demo.hex -- real GCC-compiled C using the
-- gfx.c library (set_palette, fill_rect, draw_pixel), nothing hand-
-- assembled. Watches the actual VGA scan cross row 4 (v_count=48) and
-- checks five distinct columns against what the demo should have drawn:
-- inside the red block, background between shapes, the lone green pixel,
-- inside the blue block, background again. Column formula accounts for
-- the same known 1-cycle registration delay established in tb_video.vhd:
-- a pixel at logical column C is read back at h_count_p in {2C+1, 2C+2}.

entity tb_gfx_demo is
end entity;

architecture sim of tb_gfx_demo is

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal red, green, blue : std_logic_vector(7 downto 0);

    type check_t is record
        col      : integer;
        exp_r    : std_logic_vector(7 downto 0);
        exp_g    : std_logic_vector(7 downto 0);
        exp_b    : std_logic_vector(7 downto 0);
        name     : string(1 to 25);
        seen     : boolean;
    end record;

    type check_array_t is array (0 to 4) of check_t;
    signal checks : check_array_t := (
        (5,  x"FF", x"00", x"00", "inside red block         ", false),
        (15, x"00", x"00", x"00", "background between shapes", false),
        (20, x"00", x"FF", x"00", "lone green pixel         ", false),
        (27, x"00", x"00", x"FF", "inside blue block        ", false),
        (32, x"00", x"00", x"00", "background after blue    ", false)
    );

    signal mismatch_errors : integer := 0; -- driven only by monitor
    signal missing_errors  : integer := 0; -- driven only by stim

begin

    dut: entity work.cpu_top
        generic map (HEX_FILE => "demo.hex", ROM_WORDS => 512)
        port map (clk => clk, rst => rst, red => red, green => green, blue => blue);

    clk_gen: process
    begin
        while now < 400000 ns loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    monitor: process(clk)
        alias h_count_p is << signal .tb_gfx_demo.dut.u_video_scanout.h_count : integer range 0 to 799 >>;
        alias v_count_p is << signal .tb_gfx_demo.dut.u_video_scanout.v_count : integer range 0 to 524 >>;
    begin
        if rising_edge(clk) and rst = '0' and v_count_p = 48 then
            for i in checks'range loop
                if (h_count_p = 2*checks(i).col + 1 or h_count_p = 2*checks(i).col + 2)
                   and not checks(i).seen then
                    checks(i).seen <= true;
                    report "col=" & integer'image(checks(i).col) & " (" & checks(i).name & ") -> " &
                           to_hstring(red) & to_hstring(green) & to_hstring(blue);
                    if red /= checks(i).exp_r or green /= checks(i).exp_g or blue /= checks(i).exp_b then
                        report "FAIL: " & checks(i).name & " wrong color" severity error;
                        mismatch_errors <= mismatch_errors + 1;
                    end if;
                end if;
            end loop;
        end if;
    end process;

    stim: process
    begin
        wait for 12 ns;
        rst <= '0';
        wait for 399000 ns;

        for i in checks'range loop
            if not checks(i).seen then
                report "FAIL: never observed check '" & checks(i).name & "'" severity error;
                missing_errors <= missing_errors + 1;
            end if;
        end loop;
        wait for 1 ns; -- let the increments above settle before checking totals

        if mismatch_errors = 0 and missing_errors = 0 then
            report "PASS: all shapes from the real GCC-compiled graphics demo rendered correctly";
        else
            report integer'image(mismatch_errors + missing_errors) & " TEST(S) FAILED" severity error;
        end if;
        wait;
    end process;

end architecture sim;
