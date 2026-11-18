library ieee;
use ieee.std_logic_1164.all;

entity ex_mem_reg is
    port (
        clk : in  std_logic;
        rst : in  std_logic;

        pc_plus4_in    : in  std_logic_vector(31 downto 0);
        alu_result_in  : in  std_logic_vector(31 downto 0);
        store_data_in  : in  std_logic_vector(31 downto 0); -- forwarded rs2, for SW
        rd_addr_in     : in  std_logic_vector(4 downto 0);

        reg_write_in  : in  std_logic;
        mem_read_in   : in  std_logic;
        mem_write_in  : in  std_logic;
        mem_size_in     : in  std_logic_vector(1 downto 0);
        mem_unsigned_in : in  std_logic;
        result_src_in : in  std_logic_vector(1 downto 0);

        pc_plus4_out    : out std_logic_vector(31 downto 0);
        alu_result_out  : out std_logic_vector(31 downto 0);
        store_data_out  : out std_logic_vector(31 downto 0);
        rd_addr_out     : out std_logic_vector(4 downto 0);

        reg_write_out  : out std_logic;
        mem_read_out   : out std_logic;
        mem_write_out  : out std_logic;
        mem_size_out     : out std_logic_vector(1 downto 0);
        mem_unsigned_out : out std_logic;
        result_src_out : out std_logic_vector(1 downto 0)
    );
end entity ex_mem_reg;

architecture rtl of ex_mem_reg is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pc_plus4_out   <= (others => '0');
                alu_result_out <= (others => '0');
                store_data_out <= (others => '0');
                rd_addr_out    <= (others => '0');
                reg_write_out  <= '0';
                mem_read_out   <= '0';
                mem_write_out  <= '0';
                mem_size_out     <= (others => '0');
                mem_unsigned_out <= '0';
                result_src_out <= (others => '0');
            else
                pc_plus4_out   <= pc_plus4_in;
                alu_result_out <= alu_result_in;
                store_data_out <= store_data_in;
                rd_addr_out    <= rd_addr_in;
                reg_write_out  <= reg_write_in;
                mem_read_out   <= mem_read_in;
                mem_write_out  <= mem_write_in;
                mem_size_out     <= mem_size_in;
                mem_unsigned_out <= mem_unsigned_in;
                result_src_out <= result_src_in;
            end if;
        end if;
    end process;
end architecture rtl;
