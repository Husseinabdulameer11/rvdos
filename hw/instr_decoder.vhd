library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Combinational instruction decoder for RV32I.
--
-- Splits a raw 32-bit instruction into its fields. Register fields
-- (rd/rs1/rs2) sit at fixed bit positions across every format that uses
-- them, so those are trivial. The immediate is the hard part: RISC-V
-- deliberately scrambles its bit order differently per instruction
-- format (I/S/B/U/J) so that rs1/rs2/opcode/funct3 always land at the
-- same bit positions regardless of format -- that's what lets the same
-- wires feed the register file and ALU without a format-dependent mux
-- upstream of them. The cost of that decision is paid here, once, in
-- reassembling the immediate correctly per format.
--
-- decoder does NOT interpret opcode/funct3/funct7 into control signals
-- (alu_op, mem_read, reg_write, etc.) -- that's the control unit's job,
-- kept separate so this block stays a pure, easily-verified field split.

entity instr_decoder is
    port (
        instr    : in  std_logic_vector(31 downto 0);

        opcode   : out std_logic_vector(6 downto 0);
        rd       : out std_logic_vector(4 downto 0);
        funct3   : out std_logic_vector(2 downto 0);
        rs1      : out std_logic_vector(4 downto 0);
        rs2      : out std_logic_vector(4 downto 0);
        funct7   : out std_logic_vector(6 downto 0);

        -- sign-extended to 32 bits, format selected by imm_sel from the
        -- control unit since the raw opcode alone doesn't always disambiguate
        -- which layout applies until control has looked at it
        imm_i    : out std_logic_vector(31 downto 0);
        imm_s    : out std_logic_vector(31 downto 0);
        imm_b    : out std_logic_vector(31 downto 0);
        imm_u    : out std_logic_vector(31 downto 0);
        imm_j    : out std_logic_vector(31 downto 0)
    );
end entity instr_decoder;

architecture rtl of instr_decoder is
begin

    opcode <= instr(6 downto 0);
    rd     <= instr(11 downto 7);
    funct3 <= instr(14 downto 12);
    rs1    <= instr(19 downto 15);
    rs2    <= instr(24 downto 20);
    funct7 <= instr(31 downto 25);

    -- I-type: used by loads, arithmetic-immediate, JALR.
    -- imm[11:0] = instr[31:20], sign-extended.
    imm_i <= std_logic_vector(resize(signed(instr(31 downto 20)), 32));

    -- S-type: used by stores. Split because rs2 (the value being stored)
    -- occupies the bits the immediate would otherwise use in I-type.
    -- imm[11:5] = instr[31:25], imm[4:0] = instr[11:7]
    imm_s <= std_logic_vector(resize(signed(instr(31 downto 25) & instr(11 downto 7)), 32));

    -- B-type: used by branches. imm[0] is always 0 (branch targets are
    -- 2-byte aligned), and bit 11 is stored out of order relative to S-type
    -- specifically so B-type and S-type share the same imm[10:5]/imm[4:1]
    -- wiring from instr[30:25]/[11:8] -- another deliberate wiring-reuse choice.
    -- imm[12|10:5|4:1|11] = instr[31|30:25|11:8|7], imm[0] = 0
    imm_b <= std_logic_vector(resize(signed(
                instr(31) & instr(7) & instr(30 downto 25) & instr(11 downto 8) & '0'
             ), 32));

    -- U-type: used by LUI/AUIPC. imm[31:12] = instr[31:12], low 12 bits zero.
    imm_u <= instr(31 downto 12) & x"000";

    -- J-type: used by JAL. Same bit-scrambling idea as B-type, one level up
    -- (21-bit signed offset, 2-byte aligned, imm[0] = 0).
    -- imm[20|10:1|11|19:12] = instr[31|30:21|20|19:12]
    imm_j <= std_logic_vector(resize(signed(
                instr(31) & instr(19 downto 12) & instr(20) & instr(30 downto 21) & '0'
             ), 32));

end architecture rtl;
