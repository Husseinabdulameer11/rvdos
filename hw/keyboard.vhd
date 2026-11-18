library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Simplest possible keyboard interface: one pending keypress at a time,
-- no FIFO/buffering (a second keypress before the first is read just
-- overwrites it -- real keyboard controllers buffer several, this one
-- doesn't; a known, deliberate simplification).
--
-- Memory map (word-addressed, matching the rest of this project's
-- peripherals):
--   KBD_BASE+0  status : bit 0 = 1 when a key is waiting to be read
--   KBD_BASE+4  data   : the waiting key's ASCII code (low 8 bits);
--                        reading this register clears the status bit
--
-- The "key_valid" pulse-in side is deliberately generic -- it doesn't
-- know or care whether it's driven by a synthetic testbench process
-- (tb_keyboard.vhd) or real SDL2 keyboard events (tb_live.vhd via
-- sdl_bridge.c's sdl_poll_key). Same pattern as everything else in this
-- project: keep the hardware model of a thing separate from whatever
-- happens to be feeding it in a given simulation.

entity keyboard is
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- CPU-facing read port
        cpu_addr  : in  std_logic_vector(31 downto 0); -- already offset-adjusted (0=status, 4=data)
        cpu_re    : in  std_logic;
        cpu_rdata : out std_logic_vector(31 downto 0);

        -- host-injection side: pulse key_valid for exactly one clock
        -- cycle with key_data set to inject a keypress
        key_valid : in std_logic;
        key_data  : in std_logic_vector(7 downto 0)
    );
end entity keyboard;

architecture rtl of keyboard is
    signal available : std_logic := '0';
    signal data_reg  : std_logic_vector(7 downto 0) := (others => '0');
    signal reading_data : std_logic;
begin

    -- address bit 2 distinguishes offset 0 (status) from offset 4 (data)
    -- for these word-aligned registers
    reading_data <= '1' when cpu_addr(2) = '1' else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                available <= '0';
                data_reg  <= (others => '0');
            elsif key_valid = '1' then
                data_reg  <= key_data;
                available <= '1'; -- overwrites any unread previous key
            elsif cpu_re = '1' and reading_data = '1' then
                available <= '0'; -- reading the data register consumes it
            end if;
        end if;
    end process;

    cpu_rdata <= x"000000" & data_reg when reading_data = '1' else
                 x"0000000" & "000" & available;

end architecture rtl;
