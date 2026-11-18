library ieee;
use ieee.std_logic_1164.all;

entity if_id_reg is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        stall     : in  std_logic; -- hold (load-use hazard)
        flush     : in  std_logic; -- squash to bubble (branch/jump taken)

        pc_in       : in  std_logic_vector(31 downto 0);
        pc_plus4_in : in  std_logic_vector(31 downto 0);
        instr_in    : in  std_logic_vector(31 downto 0);

        pc_out       : out std_logic_vector(31 downto 0);
        pc_plus4_out : out std_logic_vector(31 downto 0);
        instr_out    : out std_logic_vector(31 downto 0)
    );
end entity if_id_reg;

architecture rtl of if_id_reg is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush = '1' then
                pc_out       <= (others => '0');
                pc_plus4_out <= (others => '0');
                instr_out    <= (others => '0'); -- all-zero decodes as a safe no-op
            elsif stall = '0' then
                pc_out       <= pc_in;
                pc_plus4_out <= pc_plus4_in;
                instr_out    <= instr_in;
            end if;
            -- stall = '1' and not flushed: hold current output (do nothing)
        end if;
    end process;
end architecture rtl;
