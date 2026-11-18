library ieee;
use ieee.std_logic_1164.all;

-- A physical button's signal has no relationship to any clock on the FPGA
-- -- sampling it directly with a flip-flop risks metastability (the flop
-- catching the input mid-transition and taking an unbounded time to
-- settle to a valid 0 or 1). Two flops in series gives the first one's
-- potential metastability a full clock period to resolve before the
-- second one (and everything downstream) ever sees it. This is standard
-- practice for any asynchronous input crossing into a clock domain --
-- not specific to reset buttons, but that's the only asynchronous input
-- this design has.

entity reset_sync is
    port (
        clk      : in  std_logic;
        async_in : in  std_logic;
        sync_out : out std_logic
    );
end entity reset_sync;

architecture rtl of reset_sync is
    signal ff1, ff2 : std_logic := '0';
begin
    process(clk)
    begin
        if rising_edge(clk) then
            ff1 <= async_in;
            ff2 <= ff1;
        end if;
    end process;
    sync_out <= ff2;
end architecture rtl;
