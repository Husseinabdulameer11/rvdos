library ieee;
use ieee.std_logic_1164.all;
use work.alu_pkg.all;

-- imm_sel encoding: 000=I  001=S  010=B  011=U  100=J
-- result_src:       00=ALU 01=mem 10=PC+4(link)
-- alu_src_a:        00=zero (LUI)  01=rs1  10=PC (AUIPC)
-- alu_src_b:        0=rs2             1=immediate
-- jump_type:        00=none 01=JAL (target=PC+imm) 10=JALR (target=rs1+imm, bit0 cleared)
-- mem_size:         00=byte 01=halfword 10=word (shared by loads and stores)
-- mem_unsigned:     1=zero-extend on load (LBU/LHU), 0=sign-extend (LB/LH) or n/a (LW)

entity control_unit is
    port (
        opcode     : in  std_logic_vector(6 downto 0);
        funct3     : in  std_logic_vector(2 downto 0);
        funct7     : in  std_logic_vector(6 downto 0);  -- instr(31:25)

        reg_write    : out std_logic;
        alu_src_a    : out std_logic_vector(1 downto 0);
        alu_src_b    : out std_logic;
        alu_op       : out std_logic_vector(3 downto 0);
        mem_read     : out std_logic;
        mem_write    : out std_logic;
        mem_size     : out std_logic_vector(1 downto 0);
        mem_unsigned : out std_logic;
        branch       : out std_logic;
        jump_type    : out std_logic_vector(1 downto 0);
        result_src   : out std_logic_vector(1 downto 0);
        imm_sel      : out std_logic_vector(2 downto 0);
        illegal      : out std_logic  -- opcode not recognized
    );
end entity control_unit;

architecture rtl of control_unit is

    constant OP_R_TYPE : std_logic_vector(6 downto 0) := "0110011";
    constant OP_I_ALU   : std_logic_vector(6 downto 0) := "0010011";
    constant OP_LOAD    : std_logic_vector(6 downto 0) := "0000011";
    constant OP_STORE   : std_logic_vector(6 downto 0) := "0100011";
    constant OP_BRANCH  : std_logic_vector(6 downto 0) := "1100011";
    constant OP_JAL     : std_logic_vector(6 downto 0) := "1101111";
    constant OP_JALR    : std_logic_vector(6 downto 0) := "1100111";
    constant OP_LUI     : std_logic_vector(6 downto 0) := "0110111";
    constant OP_AUIPC   : std_logic_vector(6 downto 0) := "0010111";

    constant FUNCT7_M_EXT : std_logic_vector(6 downto 0) := "0000001"; -- RV32M select

    -- alu_op decode shared by R-type and I-type ALU ops.
    -- is_sub only applies for R-type (I-type ADDI has no SUB variant --
    -- funct7_b5 there is just part of the sign-extended immediate).
    function decode_alu_op(funct3 : std_logic_vector(2 downto 0);
                            funct7_b5 : std_logic;
                            is_r_type : std_logic) return std_logic_vector is
    begin
        case funct3 is
            when "000" =>
                if is_r_type = '1' and funct7_b5 = '1' then
                    return ALU_SUB;
                else
                    return ALU_ADD;
                end if;
            when "001" => return ALU_SLL;
            when "010" => return ALU_SLT;
            when "011" => return ALU_SLTU;
            when "100" => return ALU_XOR;
            when "101" =>
                if funct7_b5 = '1' then
                    return ALU_SRA;
                else
                    return ALU_SRL;
                end if;
            when "110" => return ALU_OR;
            when "111" => return ALU_AND;
            when others => return ALU_ADD;
        end case;
    end function;

begin

    process(opcode, funct3, funct7)
    begin
        -- safe defaults: a bubble / unrecognized instruction does nothing
        reg_write    <= '0';
        alu_src_a    <= "01"; -- rs1
        alu_src_b    <= '0';
        alu_op       <= ALU_ADD;
        mem_read     <= '0';
        mem_write    <= '0';
        mem_size     <= "10"; -- word (irrelevant unless mem_read/mem_write set)
        mem_unsigned <= '0';
        branch       <= '0';
        jump_type    <= "00";
        result_src   <= "00";
        imm_sel      <= "000";
        illegal      <= '0';

        case opcode is
            when OP_R_TYPE =>
                reg_write <= '1';
                alu_src_b <= '0';
                if funct7 = FUNCT7_M_EXT then
                    -- RV32M multiply/divide select. Only the multiply
                    -- variants are implemented; divide/remainder are a
                    -- deliberately deferred follow-up (see README) --
                    -- flagged illegal rather than silently doing ADD.
                    case funct3 is
                        when "000" => alu_op <= ALU_MUL;
                        when "001" => alu_op <= ALU_MULH;
                        when "010" => alu_op <= ALU_MULHSU;
                        when "011" => alu_op <= ALU_MULHU;
                        when others => illegal <= '1'; -- DIV/DIVU/REM/REMU
                    end case;
                else
                    alu_op <= decode_alu_op(funct3, funct7(5), '1');
                end if;

            when OP_I_ALU =>
                reg_write <= '1';
                alu_src_b <= '1';
                imm_sel   <= "000"; -- I
                alu_op    <= decode_alu_op(funct3, funct7(5), '0');

            when OP_LOAD =>
                reg_write    <= '1';
                alu_src_b    <= '1';
                imm_sel      <= "000"; -- I
                alu_op       <= ALU_ADD;
                mem_read     <= '1';
                mem_size     <= funct3(1 downto 0); -- 00=LB/LBU 01=LH/LHU 10=LW
                mem_unsigned <= funct3(2);           -- 1=LBU/LHU (zero-extend)
                result_src   <= "01";

            when OP_STORE =>
                alu_src_b <= '1';
                imm_sel   <= "001"; -- S
                alu_op    <= ALU_ADD;
                mem_write <= '1';
                mem_size  <= funct3(1 downto 0); -- 00=SB 01=SH 10=SW

            when OP_BRANCH =>
                alu_src_b <= '0';
                imm_sel   <= "010"; -- B
                branch    <= '1';
                -- funct3(2)='0': BEQ/BNE, compare via SUB + zero flag.
                -- funct3(2)='1': BLT/BGE/BLTU/BGEU, compare via SLT/SLTU;
                -- funct3(1) picks signed (SLT) vs unsigned (SLTU) comparison.
                if funct3(2) = '0' then
                    alu_op <= ALU_SUB;
                elsif funct3(1) = '0' then
                    alu_op <= ALU_SLT;
                else
                    alu_op <= ALU_SLTU;
                end if;

            when OP_JAL =>
                reg_write  <= '1';
                imm_sel    <= "100"; -- J
                jump_type  <= "01";
                result_src <= "10"; -- PC+4 link value

            when OP_JALR =>
                reg_write  <= '1';
                alu_src_a  <= "01"; -- rs1
                alu_src_b  <= '1';  -- imm
                alu_op     <= ALU_ADD; -- target = rs1 + imm (bit0 cleared in cpu_top)
                imm_sel    <= "000"; -- I
                jump_type  <= "10";
                result_src <= "10"; -- PC+4 link value

            when OP_LUI =>
                reg_write <= '1';
                alu_src_a <= "00"; -- force ALU operand A = 0
                alu_src_b <= '1';
                imm_sel   <= "011"; -- U
                alu_op    <= ALU_ADD; -- 0 + imm_u = imm_u

            when OP_AUIPC =>
                reg_write <= '1';
                alu_src_a <= "10"; -- PC
                alu_src_b <= '1';
                imm_sel   <= "011"; -- U
                alu_op    <= ALU_ADD; -- PC + imm_u

            when others =>
                illegal <= '1';
        end case;
    end process;

end architecture rtl;