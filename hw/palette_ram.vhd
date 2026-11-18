library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Same dual-port structure as framebuffer_ram.vhd, sized for a 256-entry
-- color lookup table (the "CLUT" a real indexed video mode uses to turn
-- an 8-bit pixel index into an actual RGB color). Each entry is one
-- 32-bit word; only the low 24 bits (R:G:B, 8 bits each) are meaningful,
-- matching vga_top's existing 8-bit-per-channel RGB output ports.

entity palette_ram is
    port (
        clk : in std_logic;

        -- Port A: CPU write (one SW per palette entry)
        a_addr        : in  std_logic_vector(31 downto 0); -- byte address
        a_wdata       : in  std_logic_vector(31 downto 0);
        a_byte_enable : in  std_logic_vector(3 downto 0);
        a_we          : in  std_logic;
        a_rdata       : out std_logic_vector(31 downto 0);

        -- Port B: VGA scanout, read-only
        b_index : in  std_logic_vector(7 downto 0); -- pixel value from the framebuffer
        b_rgb   : out std_logic_vector(23 downto 0) -- R(23:16) G(15:8) B(7:0)
    );
end entity palette_ram;

architecture rtl of palette_ram is
    constant NUM_ENTRIES : integer := 256;
    type entry_array is array (0 to NUM_ENTRIES - 1) of std_logic_vector(31 downto 0);
    signal mem : entry_array := (others => (others => '0'));

    signal a_word_index : integer range 0 to NUM_ENTRIES - 1;
begin

    a_word_index <= to_integer(unsigned(a_addr(31 downto 2))) mod NUM_ENTRIES;

    process(clk)
    begin
        if rising_edge(clk) then
            if a_we = '1' then
                for i in 0 to 3 loop
                    if a_byte_enable(i) = '1' then
                        mem(a_word_index)(8*i+7 downto 8*i) <= a_wdata(8*i+7 downto 8*i);
                    end if;
                end loop;
            end if;
        end if;
    end process;

    a_rdata <= mem(a_word_index);
    b_rgb   <= mem(to_integer(unsigned(b_index)))(23 downto 0);

end architecture rtl;
