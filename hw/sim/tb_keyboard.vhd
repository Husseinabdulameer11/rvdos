library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Synthetic keyboard test -- no SDL2, no real window, just a VHDL
-- process directly pulsing key_valid/key_data on cpu_top's ports. This
-- verifies the peripheral and its memory-mapped decode in isolation
-- from anything SDL2-related, which can only be reviewed (not run) in
-- this sandbox.

entity tb_keyboard is
end entity;

architecture sim of tb_keyboard is
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal dbg_addr : std_logic_vector(4 downto 0) := (others => '0');
    signal dbg_data : std_logic_vector(31 downto 0);
    signal key_valid : std_logic := '0';
    signal key_data : std_logic_vector(7 downto 0) := (others => '0');
begin

    dut: entity work.cpu_top
        generic map (HEX_FILE => "kbd_test.hex", ROM_WORDS => 64)
        port map (
            clk => clk, rst => rst, dbg_addr => dbg_addr, dbg_data => dbg_data,
            key_valid => key_valid, key_data => key_data
        );

    clk_gen: process
    begin
        while now < 2000 ns loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    stim: process
    begin
        wait for 12 ns;
        rst <= '0';

        -- give the CPU a few cycles to reach the polling loop, then
        -- inject 'H' (0x48) as a one-cycle pulse
        wait for 100 ns;
        wait until rising_edge(clk);
        key_valid <= '1';
        key_data <= x"48"; -- 'H'
        wait until rising_edge(clk);
        key_valid <= '0';

        -- give the CPU time to detect it, read the data register, and
        -- reach the halt loop
        wait for 200 ns;

        dbg_addr <= "00011"; -- x3
        wait for 1 ns;
        if to_integer(unsigned(dbg_data)) = 16#48# then
            report "PASS: x3 = 0x48 ('H') -- keyboard peripheral correctly delivered the injected key";
        else
            report "FAIL: x3 expected 0x48, got 0x" & to_hstring(dbg_data) severity error;
        end if;

        wait;
    end process;

end architecture sim;
