library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- This is the actual fix for the gap flagged throughout this project's
-- README: instr_rom holds .text, fetched only via PC -- the CPU's
-- lw/lb/sw/sb instructions can never reach it, because it isn't wired to
-- the data-side address decode in cpu_top at all. Real constant data
-- (C's `static const` arrays, string literals -- .rodata) needs to live
-- somewhere the LOAD path can actually see. This is that memory: same
-- textio-file-loading mechanism as instr_rom_hex.vhd, but sitting on the
-- data bus instead of the instruction bus, so ordinary loads reach it.
--
-- Read-only from the CPU's perspective (matches its purpose -- constant
-- data shouldn't be written at runtime); stores to this address range
-- are simply ignored by whoever wires this up (see cpu_top.vhd).
--
-- Word-addressed, same convention as data_ram -- byte/halfword access
-- within a word is handled by the shared load_extend.vhd, not duplicated
-- here.

-- Synchronous read (block RAM): rdata is the word at the address given on
-- the previous rising edge, i.e. it arrives in the WB stage.

entity rodata_rom is
    generic (
        HEX_FILE  : string; -- required: path to a rodata hex file (same format rvasm/bin2hex produce)
        ROM_WORDS : integer := 1024 -- 4KB default
    );
    port (
        clk   : in  std_logic;
        addr  : in  std_logic_vector(31 downto 0); -- byte address, already offset-adjusted by the caller
        rdata : out std_logic_vector(31 downto 0)
    );
end entity rodata_rom;

architecture rtl of rodata_rom is
    constant AW : integer := addr_bits(ROM_WORDS);
    signal rom : word_array(0 to ROM_WORDS - 1) := load_hex(HEX_FILE, ROM_WORDS);
    attribute rom_style : string;
    attribute rom_style of rom : signal is "block";
begin
    process(clk)
        variable idx : integer range 0 to 2 ** AW - 1;
    begin
        if rising_edge(clk) then
            idx := to_integer(unsigned(addr(AW + 1 downto 2)));
            if idx < ROM_WORDS then
                rdata <= rom(idx);
            else
                rdata <= (others => '0');
            end if;
        end if;
    end process;
end architecture rtl;
