library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Loads basic.hex -- the actual output of
-- tools/asm.c assembling demos/basic.s -- directly into the CPU via
-- instr_rom_hex, and checks the same expected register values as
-- tb_cpu_top.vhd's hand-encoded version of the same program. This is the
-- real proof: source assembly -> assembler -> hex file -> simulated CPU
-- -> correct register state, with nothing hand-encoded in between.

entity tb_hex_program is
end entity;

architecture sim of tb_hex_program is

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal dbg_addr : std_logic_vector(4 downto 0) := (others => '0');
    signal dbg_data : std_logic_vector(31 downto 0);
    signal errors : integer := 0;

    procedure check_reg(addr : std_logic_vector(4 downto 0); expected : integer; name : string;
                         signal a : out std_logic_vector(4 downto 0);
                         signal d : in std_logic_vector(31 downto 0);
                         signal errcount : inout integer) is
    begin
        a <= addr;
        wait for 1 ns;
        if to_integer(unsigned(d)) /= expected then
            report "FAIL: " & name & " expected " & integer'image(expected) &
                   " got " & integer'image(to_integer(unsigned(d))) severity error;
            errcount <= errcount + 1;
        else
            report "PASS: " & name & " = " & integer'image(expected);
        end if;
    end procedure;

begin

    dut: entity work.cpu_top
        generic map (HEX_FILE => "basic.hex")
        port map (clk => clk, rst => rst, dbg_addr => dbg_addr, dbg_data => dbg_data);

    clk_gen: process
    begin
        while now < 400 ns loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    stim: process
    begin
        wait for 12 ns;
        rst <= '0';
        wait for 250 ns;

        check_reg("00001", 5,   "x1", dbg_addr, dbg_data, errors);
        check_reg("00010", 10,  "x2", dbg_addr, dbg_data, errors);
        check_reg("00011", 15,  "x3", dbg_addr, dbg_data, errors);
        check_reg("00100", 15,  "x4", dbg_addr, dbg_data, errors);
        check_reg("00101", 30,  "x5", dbg_addr, dbg_data, errors);
        check_reg("00110", 0,   "x6 (skipped by beq)", dbg_addr, dbg_data, errors);
        check_reg("00111", 111, "x7", dbg_addr, dbg_data, errors);
        check_reg("01001", 0,   "x9 (skipped by jal)", dbg_addr, dbg_data, errors);
        check_reg("01010", 222, "x10", dbg_addr, dbg_data, errors);

        if errors = 0 then
            report "ALL TESTS PASSED -- assembler output verified on real CPU";
        else
            report integer'image(errors) & " TEST(S) FAILED" severity error;
        end if;
        wait;
    end process;

end architecture sim;
