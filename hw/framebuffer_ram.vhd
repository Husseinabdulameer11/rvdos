library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- 320x200 framebuffer, one byte (palette index) per pixel, 64000 bytes.
--
-- Stored as 16384 x 32-bit words so it maps onto Artix-7 block RAM (16 of
-- the XC7A35T's 50 RAMB36). Both ports are synchronous, as block RAM
-- requires:
--   port A (CPU, MEM stage): word read/write with byte enables;
--          a_rdata is the word addressed on the previous edge (WB stage)
--   port B (video): b_pixel_data is the pixel addressed on the previous
--          edge -- video_scanout asks one pixel ahead to make up for it.

entity framebuffer_ram is
    generic (
        WIDTH  : integer := 320;
        HEIGHT : integer := 200
    );
    port (
        clk : in std_logic;

        a_addr        : in  std_logic_vector(31 downto 0); -- byte address, word-aligned base
        a_wdata       : in  std_logic_vector(31 downto 0); -- pre-positioned by store_align
        a_byte_enable : in  std_logic_vector(3 downto 0);
        a_we          : in  std_logic;
        a_rdata       : out std_logic_vector(31 downto 0);

        b_pixel_addr : in  std_logic_vector(17 downto 0); -- 0 .. WIDTH*HEIGHT-1
        b_pixel_data : out std_logic_vector(7 downto 0)
    );
end entity framebuffer_ram;

architecture rtl of framebuffer_ram is
    constant NUM_BYTES : integer := WIDTH * HEIGHT;
    constant AW        : integer := addr_bits((NUM_BYTES + 3) / 4);   -- 14 for 320x200
    constant NUM_WORDS : integer := 2 ** AW;

    -- named "mem" so testbenches can read the picture with an external name
    signal mem : word_array(0 to NUM_WORDS - 1) := (others => (others => '0'));
    attribute ram_style : string;
    attribute ram_style of mem : signal is "block";

    signal a_index, b_index : integer range 0 to NUM_WORDS - 1;
    signal b_word : std_logic_vector(31 downto 0);
    signal b_lane : std_logic_vector(1 downto 0) := "00";
begin

    a_index <= to_integer(unsigned(a_addr(AW + 1 downto 2)));
    b_index <= to_integer(unsigned(b_pixel_addr(AW + 1 downto 2)));

    process(clk)
    begin
        if rising_edge(clk) then
            if a_we = '1' then
                for i in 0 to 3 loop
                    if a_byte_enable(i) = '1' then
                        mem(a_index)(8*i+7 downto 8*i) <= a_wdata(8*i+7 downto 8*i);
                    end if;
                end loop;
            end if;
            a_rdata <= mem(a_index);
            b_word  <= mem(b_index);
            b_lane  <= b_pixel_addr(1 downto 0);
        end if;
    end process;

    with b_lane select b_pixel_data <=
        b_word(7 downto 0)   when "00",
        b_word(15 downto 8)  when "01",
        b_word(23 downto 16) when "10",
        b_word(31 downto 24) when others;

end architecture rtl;
