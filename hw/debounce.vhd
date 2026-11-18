library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- A mechanical button doesn't transition cleanly -- the physical contacts
-- bounce for a few milliseconds, during which the raw signal can toggle
-- rapidly before settling. Feeding that straight into every register's
-- reset input (as cpu_top's rst currently does) would cause spurious
-- repeated resets during that bounce window. This only updates its
-- output once the input has been stable for DEBOUNCE_CYCLES consecutive
-- clock cycles, filtering the bounce out entirely.
--
-- Takes reset_sync.vhd's output as its input -- debouncing doesn't fix
-- metastability (that's reset_sync's job), and metastability isn't a
-- bounce (that's this module's job); a real button input needs both,
-- in that order.

entity debounce is
    generic (
        DEBOUNCE_CYCLES : integer := 250_000 -- ~10ms at 25MHz
    );
    port (
        clk       : in  std_logic;
        noisy_in  : in  std_logic;
        clean_out : out std_logic
    );
end entity debounce;

architecture rtl of debounce is
    signal counter    : integer range 0 to DEBOUNCE_CYCLES := 0;
    signal last_input : std_logic := '0';
    signal stable_out : std_logic := '0';
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if noisy_in /= last_input then
                -- input changed: restart the stability count
                last_input <= noisy_in;
                counter    <= 0;
            elsif counter < DEBOUNCE_CYCLES then
                counter <= counter + 1;
            else
                -- held stable for the full window: accept it
                stable_out <= last_input;
            end if;
        end if;
    end process;
    clean_out <= stable_out;
end architecture rtl;
