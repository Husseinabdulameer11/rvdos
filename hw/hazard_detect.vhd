library ieee;
use ieee.std_logic_1164.all;

-- A load's data isn't available until MEM completes -- if the very next
-- instruction needs that value in EX, no amount of forwarding can supply
-- it in time (it doesn't exist yet). The only fix is one stall cycle:
-- freeze PC and IF/ID, and insert a bubble into ID/EX so EX executes a
-- no-op for one cycle, giving the load time to reach MEM.

entity hazard_detect is
    port (
        id_rs1_addr   : in  std_logic_vector(4 downto 0); -- rs1 of instr currently in ID
        id_rs2_addr   : in  std_logic_vector(4 downto 0); -- rs2 of instr currently in ID
        ex_rd_addr    : in  std_logic_vector(4 downto 0); -- rd of instr currently in EX
        ex_mem_read   : in  std_logic;                    -- EX-stage instr is a load

        stall_pc      : out std_logic;
        stall_if_id   : out std_logic;
        flush_id_ex   : out std_logic
    );
end entity hazard_detect;

architecture rtl of hazard_detect is
    signal hazard : std_logic;
begin
    hazard <= '1' when (ex_mem_read = '1') and (ex_rd_addr /= "00000") and
                        ((ex_rd_addr = id_rs1_addr) or (ex_rd_addr = id_rs2_addr))
              else '0';

    stall_pc    <= hazard;
    stall_if_id <= hazard;
    flush_id_ex <= hazard;
end architecture rtl;
