library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Same role as instr_rom.vhd, but populated from an external hex file
-- (one 32-bit word per line, 8 hex digits, no "0x" prefix -- exactly what
-- rvasm.c emits) instead of a VHDL constant array.
--
-- Synchronous read: data is the word at the address presented on the
-- previous rising edge. That is what lets Vivado put this ROM in block
-- RAM (block RAM has no combinational read); cpu_top presents the *next*
-- PC so the instruction for the current PC is ready when it's needed.

entity instr_rom_hex is
    generic (
        HEX_FILE  : string;
        ROM_WORDS : integer := 256
    );
    port (
        clk  : in  std_logic;
        addr : in  std_logic_vector(31 downto 0); -- byte address of the NEXT fetch
        data : out std_logic_vector(31 downto 0)
    );
end entity instr_rom_hex;

architecture rtl of instr_rom_hex is
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
                data <= rom(idx);
            else
                data <= (others => '0');
            end if;
        end if;
    end process;
end architecture rtl;
