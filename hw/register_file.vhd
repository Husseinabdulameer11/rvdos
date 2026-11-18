library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- RV32I register file: 32 x 32-bit registers.
-- x0 always reads as zero and writes to it are discarded (per spec).
-- Two combinational read ports (rs1, rs2) since the pipeline's ID stage
-- needs both operands in the same cycle. One synchronous write port,
-- written by WB. Write-then-read in the same cycle (WB writing while ID
-- reads) is handled with a bypass so ID sees the new value immediately,
-- avoiding a stall on back-to-back dependent instructions.

entity register_file is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;

        -- read ports (combinational)
        rs1_addr  : in  std_logic_vector(4 downto 0);
        rs2_addr  : in  std_logic_vector(4 downto 0);
        rs1_data  : out std_logic_vector(31 downto 0);
        rs2_data  : out std_logic_vector(31 downto 0);

        -- write port (synchronous, registered on rising edge of clk)
        we        : in  std_logic;
        rd_addr   : in  std_logic_vector(4 downto 0);
        rd_data   : in  std_logic_vector(31 downto 0);

        -- debug/observation port: raw read, no write-bypass, for testbenches
        -- and (eventually) a real debug/JTAG interface
        dbg_addr  : in  std_logic_vector(4 downto 0) := (others => '0');
        dbg_data  : out std_logic_vector(31 downto 0)
    );
end entity register_file;

architecture rtl of register_file is

    type reg_array is array (0 to 31) of std_logic_vector(31 downto 0);
    signal regs : reg_array := (others => (others => '0'));

begin

    -- synchronous write
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                regs <= (others => (others => '0'));
            elsif we = '1' and rd_addr /= "00000" then
                regs(to_integer(unsigned(rd_addr))) <= rd_data;
            end if;
        end if;
    end process;

    -- combinational reads, with write-port bypass so a same-cycle
    -- write-then-read of the same register sees the new value
    rs1_data <= (others => '0') when rs1_addr = "00000" else
                rd_data when (we = '1' and rd_addr = rs1_addr and rd_addr /= "00000") else
                regs(to_integer(unsigned(rs1_addr)));

    rs2_data <= (others => '0') when rs2_addr = "00000" else
                rd_data when (we = '1' and rd_addr = rs2_addr and rd_addr /= "00000") else
                regs(to_integer(unsigned(rs2_addr)));

    dbg_data <= regs(to_integer(unsigned(dbg_addr)));

end architecture rtl;
