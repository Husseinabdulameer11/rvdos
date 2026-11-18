library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pc_reg is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        stall   : in  std_logic; -- hold current value (load-use hazard)
        pc_next : in  std_logic_vector(31 downto 0);
        pc      : out std_logic_vector(31 downto 0)
    );
end entity pc_reg;

architecture rtl of pc_reg is
    signal pc_i : std_logic_vector(31 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pc_i <= (others => '0');
            elsif stall = '0' then
                pc_i <= pc_next;
            end if;
        end if;
    end process;
    pc <= pc_i;
end architecture rtl;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pc_adder is
    port (
        pc_in    : in  std_logic_vector(31 downto 0);
        pc_plus4 : out std_logic_vector(31 downto 0)
    );
end entity pc_adder;

architecture rtl of pc_adder is
begin
    pc_plus4 <= std_logic_vector(unsigned(pc_in) + 4);
end architecture rtl;
