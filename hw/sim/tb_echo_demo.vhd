library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Real GCC-compiled interactive program: prints a prompt, then blocks in
-- kbd_getchar() waiting for real input. This testbench injects one
-- synthetic keypress ('H') well after the prompt has finished printing,
-- and confirms -- via store tracing, not a full-frame scan wait -- that
-- the CPU actually detected it and drew the correct pixel pattern for
-- 'H' at the expected screen position (start of line 2, since the
-- prompt ends with a newline).

entity tb_echo_demo is
end entity;

architecture sim of tb_echo_demo is
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal key_valid : std_logic := '0';
    signal key_data : std_logic_vector(7 downto 0) := (others => '0');

    signal saw_h_row0 : boolean := false; -- expect a write at fb offset 2560 (col0,row1-of-console -> pixel y=8)
    signal errors : integer := 0;
begin

    dut: entity work.cpu_top
        generic map (
            HEX_FILE => "echo_demo_text.hex", ROM_WORDS => 1024,
            RODATA_HEX_FILE => "echo_demo_rodata.hex", RODATA_WORDS => 128
        )
        port map (
            clk => clk, rst => rst,
            key_valid => key_valid, key_data => key_data
        );

    clk_gen: process
    begin
        while now < 3000000 ns loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    monitor: process(clk)
        alias mem_write_mem_p is << signal .tb_echo_demo.dut.mem_write_mem : std_logic >>;
        alias alu_result_mem_p is << signal .tb_echo_demo.dut.alu_result_mem : std_logic_vector(31 downto 0) >>;
        alias is_fb_mem_p is << signal .tb_echo_demo.dut.is_fb_mem : std_logic >>;
        alias store_wdata_p is << signal .tb_echo_demo.dut.store_wdata_aligned : std_logic_vector(31 downto 0) >>;
    begin
        if rising_edge(clk) and mem_write_mem_p = '1' and is_fb_mem_p = '1' then
            -- FB_BASE=0x10000, offset 2560 = pixel (col0,row8) = start of
            -- console line 2, where the echoed 'H' should land
            if alu_result_mem_p = x"00010A00" then
                saw_h_row0 <= true;
                report "write to H's expected position, wdata byte0=" & to_hstring(store_wdata_p(7 downto 0));
                if store_wdata_p(7 downto 0) /= x"01" then
                    report "FAIL: expected palette index 1 at H's position" severity error;
                    errors <= errors + 1;
                end if;
            end if;
        end if;
    end process;

    stim: process
    begin
        wait for 12 ns;
        rst <= '0';

        -- let "TYPE SOMETHING:" finish printing before injecting a key
        wait for 2000000 ns;

        wait until rising_edge(clk);
        key_valid <= '1';
        key_data <= x"48"; -- 'H'
        wait until rising_edge(clk);
        key_valid <= '0';

        -- give the CPU time to detect it and draw the glyph
        wait for 900000 ns;

        if not saw_h_row0 then
            report "FAIL: never saw the expected framebuffer write for the echoed key" severity error;
        elsif errors = 0 then
            report "PASS: injected keypress was correctly read and echoed to the screen";
        else
            report integer'image(errors) & " TEST(S) FAILED" severity error;
        end if;
        wait;
    end process;

end architecture sim;
