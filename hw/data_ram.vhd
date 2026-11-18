library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Direct-connect data memory. Same bus simplification as instr_rom: no
-- Wishbone protocol yet. Byte-addressable via a 4-bit write mask, one bit
-- per byte lane -- store_align.vhd computes that mask and positions the
-- store value into the correct lane(s) before this entity ever sees it,
-- so this stays a plain masked-write word RAM.
--
-- Read is deliberately COMBINATIONAL, not registered. The pipeline model
-- here has each stage's combinational logic act on its pipeline register's
-- *current, stable* output, with results latched at the next clock edge --
-- a registered ("synchronous") memory read would return data one cycle
-- late relative to that model, arriving after mem_wb_reg has already
-- latched (a stale value). Combinational read is a common simplification
-- in a first pipeline; real FPGA block RAM often wants a registered read
-- for timing closure at high clock speeds, which would mean restructuring
-- MEM into its own extra pipeline stage -- a real next step, not done here.

entity data_ram is
    generic (
        RAM_WORDS : integer := 256
    );
    port (
        clk         : in  std_logic;
        addr        : in  std_logic_vector(31 downto 0); -- byte address
        wdata       : in  std_logic_vector(31 downto 0); -- already repositioned by store_align
        byte_enable : in  std_logic_vector(3 downto 0);  -- one bit per byte lane
        we          : in  std_logic;                     -- overall write enable (SW/SH/SB)
        re          : in  std_logic; -- unused internally (read is always valid); kept for interface symmetry
        rdata       : out std_logic_vector(31 downto 0)
    );
end entity data_ram;

architecture rtl of data_ram is
    type ram_array is array (0 to RAM_WORDS - 1) of std_logic_vector(31 downto 0);
    signal ram : ram_array := (others => (others => '0'));
    attribute ram_style : string;
    attribute ram_style of ram : signal is "block";
    signal word_addr : integer range 0 to RAM_WORDS - 1;
begin
    word_addr <= to_integer(unsigned(addr(31 downto 2))) mod RAM_WORDS;

    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                for i in 0 to 3 loop
                    if byte_enable(i) = '1' then
                        ram(word_addr)(8*i+7 downto 8*i) <= wdata(8*i+7 downto 8*i);
                    end if;
                end loop;
            end if;
            -- clocked, read-first: the block RAM template Vivado infers.
            -- rdata arrives in the WB stage, the same timing the MEM/WB
            -- register gave the old combinational read.
            rdata <= ram(word_addr);
        end if;
    end process;
end architecture rtl;
