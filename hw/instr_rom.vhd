library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Direct-connect instruction memory: combinational read, word-addressed.
-- This is a simplification -- a real design would sit this behind a
-- Wishbone (or similar) bus with proper handshaking so it can later be
-- swapped for something with real access latency (external SRAM, a cache
-- miss, etc.) without touching the CPU. Deferred until the core itself is
-- proven correct.
--
-- Contents come in via a VHDL-2008 unconstrained generic array, set by
-- whoever instantiates this (test program, real firmware image, etc.)
-- rather than hardcoded here.

entity instr_rom is
    generic (
        PROGRAM : word_array
    );
    port (
        clk  : in  std_logic;
        addr : in  std_logic_vector(31 downto 0); -- byte address of the NEXT fetch (read is clocked)
        data : out std_logic_vector(31 downto 0)
    );
end entity instr_rom;

architecture rtl of instr_rom is
    constant ROM_WORDS : integer := PROGRAM'length;
    signal word_addr : integer range 0 to ROM_WORDS - 1;
begin
    word_addr <= to_integer(unsigned(addr(31 downto 2))) mod ROM_WORDS;
    process(clk)
    begin
        if rising_edge(clk) then
            data <= PROGRAM(PROGRAM'low + word_addr);
        end if;
    end process;
end architecture rtl;
