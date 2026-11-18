library ieee;
use ieee.std_logic_1164.all;

entity id_ex_reg is
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        flush : in  std_logic; -- bubble insertion (load-use stall OR branch/jump taken)

        pc_in        : in  std_logic_vector(31 downto 0);
        pc_plus4_in  : in  std_logic_vector(31 downto 0);
        rs1_data_in  : in  std_logic_vector(31 downto 0);
        rs2_data_in  : in  std_logic_vector(31 downto 0);
        rs1_addr_in  : in  std_logic_vector(4 downto 0);
        rs2_addr_in  : in  std_logic_vector(4 downto 0);
        rd_addr_in   : in  std_logic_vector(4 downto 0);
        imm_in       : in  std_logic_vector(31 downto 0);
        funct3_in    : in  std_logic_vector(2 downto 0);

        reg_write_in  : in  std_logic;
        alu_src_a_in  : in  std_logic_vector(1 downto 0);
        alu_src_b_in  : in  std_logic;
        alu_op_in     : in  std_logic_vector(3 downto 0);
        mem_read_in   : in  std_logic;
        mem_write_in  : in  std_logic;
        mem_size_in     : in  std_logic_vector(1 downto 0);
        mem_unsigned_in : in  std_logic;
        branch_in     : in  std_logic;
        jump_type_in  : in  std_logic_vector(1 downto 0);
        result_src_in : in  std_logic_vector(1 downto 0);

        pc_out        : out std_logic_vector(31 downto 0);
        pc_plus4_out  : out std_logic_vector(31 downto 0);
        rs1_data_out  : out std_logic_vector(31 downto 0);
        rs2_data_out  : out std_logic_vector(31 downto 0);
        rs1_addr_out  : out std_logic_vector(4 downto 0);
        rs2_addr_out  : out std_logic_vector(4 downto 0);
        rd_addr_out   : out std_logic_vector(4 downto 0);
        imm_out       : out std_logic_vector(31 downto 0);
        funct3_out    : out std_logic_vector(2 downto 0);

        reg_write_out  : out std_logic;
        alu_src_a_out  : out std_logic_vector(1 downto 0);
        alu_src_b_out  : out std_logic;
        alu_op_out     : out std_logic_vector(3 downto 0);
        mem_read_out   : out std_logic;
        mem_write_out  : out std_logic;
        mem_size_out     : out std_logic_vector(1 downto 0);
        mem_unsigned_out : out std_logic;
        branch_out     : out std_logic;
        jump_type_out  : out std_logic_vector(1 downto 0);
        result_src_out : out std_logic_vector(1 downto 0)
    );
end entity id_ex_reg;

architecture rtl of id_ex_reg is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush = '1' then
                pc_out         <= (others => '0');
                pc_plus4_out   <= (others => '0');
                rs1_data_out   <= (others => '0');
                rs2_data_out   <= (others => '0');
                rs1_addr_out   <= (others => '0');
                rs2_addr_out   <= (others => '0');
                rd_addr_out    <= (others => '0');
                imm_out        <= (others => '0');
                funct3_out     <= (others => '0');
                reg_write_out  <= '0';
                alu_src_a_out  <= "01";
                alu_src_b_out  <= '0';
                alu_op_out     <= (others => '0');
                mem_read_out   <= '0';
                mem_write_out  <= '0';
                mem_size_out     <= (others => '0');
                mem_unsigned_out <= '0';
                branch_out     <= '0';
                jump_type_out  <= "00";
                result_src_out <= (others => '0');
            else
                pc_out         <= pc_in;
                pc_plus4_out   <= pc_plus4_in;
                rs1_data_out   <= rs1_data_in;
                rs2_data_out   <= rs2_data_in;
                rs1_addr_out   <= rs1_addr_in;
                rs2_addr_out   <= rs2_addr_in;
                rd_addr_out    <= rd_addr_in;
                imm_out        <= imm_in;
                funct3_out     <= funct3_in;
                reg_write_out  <= reg_write_in;
                alu_src_a_out  <= alu_src_a_in;
                alu_src_b_out  <= alu_src_b_in;
                alu_op_out     <= alu_op_in;
                mem_read_out   <= mem_read_in;
                mem_write_out  <= mem_write_in;
                mem_size_out     <= mem_size_in;
                mem_unsigned_out <= mem_unsigned_in;
                branch_out     <= branch_in;
                jump_type_out  <= jump_type_in;
                result_src_out <= result_src_in;
            end if;
        end if;
    end process;
end architecture rtl;
