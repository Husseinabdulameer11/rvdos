library ieee;
use ieee.std_logic_1164.all;

-- forward_a/forward_b: 00 = use register file value (no hazard)
--                       10 = forward from EX/MEM (most recent producer)
--                       01 = forward from MEM/WB (older producer)
-- EX/MEM takes priority over MEM/WB when both match, since it's the more
-- recent write (e.g. two consecutive instructions both writing the same
-- register the current EX instruction depends on).

entity forward_unit is
    port (
        ex_rs1_addr : in  std_logic_vector(4 downto 0);
        ex_rs2_addr : in  std_logic_vector(4 downto 0);

        exmem_rd_addr   : in  std_logic_vector(4 downto 0);
        exmem_reg_write : in  std_logic;

        memwb_rd_addr   : in  std_logic_vector(4 downto 0);
        memwb_reg_write : in  std_logic;

        forward_a : out std_logic_vector(1 downto 0);
        forward_b : out std_logic_vector(1 downto 0)
    );
end entity forward_unit;

architecture rtl of forward_unit is
begin

    process(ex_rs1_addr, exmem_rd_addr, exmem_reg_write, memwb_rd_addr, memwb_reg_write)
    begin
        if exmem_reg_write = '1' and exmem_rd_addr /= "00000" and exmem_rd_addr = ex_rs1_addr then
            forward_a <= "10";
        elsif memwb_reg_write = '1' and memwb_rd_addr /= "00000" and memwb_rd_addr = ex_rs1_addr then
            forward_a <= "01";
        else
            forward_a <= "00";
        end if;
    end process;

    process(ex_rs2_addr, exmem_rd_addr, exmem_reg_write, memwb_rd_addr, memwb_reg_write)
    begin
        if exmem_reg_write = '1' and exmem_rd_addr /= "00000" and exmem_rd_addr = ex_rs2_addr then
            forward_b <= "10";
        elsif memwb_reg_write = '1' and memwb_rd_addr /= "00000" and memwb_rd_addr = ex_rs2_addr then
            forward_b <= "01";
        else
            forward_b <= "00";
        end if;
    end process;

end architecture rtl;
