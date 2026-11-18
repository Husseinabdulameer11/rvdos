library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Loads /home/claude/riscv-c/test.hex -- real GCC -march=rv32im output,
-- compiled from a C program with a function call, a loop, and a hardware
-- multiply, run through objcopy and bin2hex, nothing hand-assembled.
-- Expects a0 (x10) = 55 (sum of squares 1..5) once execution reaches the
-- crt0 halt loop.

entity tb_gcc_program is
end entity;

architecture sim of tb_gcc_program is

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal dbg_addr : std_logic_vector(4 downto 0) := (others => '0');
    signal dbg_data : std_logic_vector(31 downto 0);

begin

    dut: entity work.cpu_top
        generic map (HEX_FILE => "test.hex")
        port map (clk => clk, rst => rst, dbg_addr => dbg_addr, dbg_data => dbg_data);

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
        wait for 1800 ns; -- generous settle time: 5 loop iterations, function
                           -- calls, and load-use stalls need real cycles

        dbg_addr <= "01010"; -- x10 = a0, holds main()'s return value
        wait for 1 ns;

        if to_integer(unsigned(dbg_data)) = 55 then
            report "PASS: a0 (x10) = 55 -- real GCC-compiled C ran correctly on the CPU";
        else
            report "FAIL: a0 (x10) expected 55, got " &
                   integer'image(to_integer(unsigned(dbg_data))) severity error;
        end if;

        wait;
    end process;

end architecture sim;
