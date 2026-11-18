library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Combinational ALU for RV32I.
--
-- alu_op is a decoded control code, not the raw funct3/funct7 bits from
-- the instruction. Translating instruction encoding -> alu_op is the
-- control unit's job (comes later) -- keeping that translation out of
-- the ALU is standard practice: it lets the same ALU be reused for R-type,
-- I-type, and branch comparisons without duplicating decode logic, and
-- keeps this block trivially verifiable in isolation.

package alu_pkg is
    constant ALU_ADD  : std_logic_vector(3 downto 0) := "0000";
    constant ALU_SUB  : std_logic_vector(3 downto 0) := "0001";
    constant ALU_SLL  : std_logic_vector(3 downto 0) := "0010";
    constant ALU_SLT  : std_logic_vector(3 downto 0) := "0011";
    constant ALU_SLTU : std_logic_vector(3 downto 0) := "0100";
    constant ALU_XOR  : std_logic_vector(3 downto 0) := "0101";
    constant ALU_SRL  : std_logic_vector(3 downto 0) := "0110";
    constant ALU_SRA  : std_logic_vector(3 downto 0) := "0111";
    constant ALU_OR   : std_logic_vector(3 downto 0) := "1000";
    constant ALU_AND  : std_logic_vector(3 downto 0) := "1001";
    -- RV32M (multiply only -- divide is deliberately not implemented yet,
    -- see README)
    constant ALU_MUL     : std_logic_vector(3 downto 0) := "1010"; -- low 32 bits of rs1*rs2
    constant ALU_MULH    : std_logic_vector(3 downto 0) := "1011"; -- high 32 bits, signed*signed
    constant ALU_MULHSU  : std_logic_vector(3 downto 0) := "1100"; -- high 32 bits, signed*unsigned
    constant ALU_MULHU   : std_logic_vector(3 downto 0) := "1101"; -- high 32 bits, unsigned*unsigned
end package alu_pkg;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity alu is
    port (
        a       : in  std_logic_vector(31 downto 0);
        b       : in  std_logic_vector(31 downto 0);
        alu_op  : in  std_logic_vector(3 downto 0);
        result  : out std_logic_vector(31 downto 0);
        zero    : out std_logic  -- result = 0, used by branch comparisons (BEQ/BNE)
    );
end entity alu;

architecture rtl of alu is

    signal res      : std_logic_vector(31 downto 0);
    signal shamt    : integer range 0 to 31;

    -- signed views for SUB/SLT/SRA
    signal a_signed, b_signed : signed(31 downto 0);

    -- Wide multiply products for MUL/MULH/MULHSU/MULHU. Using full 64-bit
    -- operands for every variant (rather than the tighter 33x33 a real
    -- mixed-sign multiplier would use) is a deliberate simplification --
    -- correctness and clarity over gate count, consistent with this
    -- project's other behavioral-first choices (e.g. the direct-connect
    -- memories). A synthesis-minded version would right-size this.
    signal a_s64, b_s64, b_u64_as_signed : signed(63 downto 0);
    signal a_u64, b_u64 : unsigned(63 downto 0);
    signal product_ss, product_su : signed(127 downto 0);
    signal product_uu : unsigned(127 downto 0);

begin

    a_signed <= signed(a);
    b_signed <= signed(b);
    shamt    <= to_integer(unsigned(b(4 downto 0)));  -- shift amount = low 5 bits of b

    a_s64          <= resize(signed(a), 64);
    b_s64          <= resize(signed(b), 64);
    b_u64_as_signed<= signed(resize(unsigned(b), 64)); -- zero-extended, top bit 0 so safe as signed
    a_u64          <= resize(unsigned(a), 64);
    b_u64          <= resize(unsigned(b), 64);
    product_ss <= a_s64 * b_s64;
    product_su <= a_s64 * b_u64_as_signed;
    product_uu <= a_u64 * b_u64;

    process(a, b, alu_op, a_signed, b_signed, shamt, product_ss, product_su, product_uu)
    begin
        case alu_op is
            when ALU_ADD =>
                res <= std_logic_vector(unsigned(a) + unsigned(b));

            when ALU_SUB =>
                res <= std_logic_vector(unsigned(a) - unsigned(b));

            when ALU_SLL =>
                res <= std_logic_vector(shift_left(unsigned(a), shamt));

            when ALU_SLT =>
                if a_signed < b_signed then
                    res <= (0 => '1', others => '0');
                else
                    res <= (others => '0');
                end if;

            when ALU_SLTU =>
                if unsigned(a) < unsigned(b) then
                    res <= (0 => '1', others => '0');
                else
                    res <= (others => '0');
                end if;

            when ALU_XOR =>
                res <= a xor b;

            when ALU_SRL =>
                res <= std_logic_vector(shift_right(unsigned(a), shamt));

            when ALU_SRA =>
                res <= std_logic_vector(shift_right(a_signed, shamt));

            when ALU_OR =>
                res <= a or b;

            when ALU_AND =>
                res <= a and b;

            when ALU_MUL =>
                res <= std_logic_vector(product_ss(31 downto 0));

            when ALU_MULH =>
                res <= std_logic_vector(product_ss(63 downto 32));

            when ALU_MULHSU =>
                res <= std_logic_vector(product_su(63 downto 32));

            when ALU_MULHU =>
                res <= std_logic_vector(product_uu(63 downto 32));

            when others =>
                res <= (others => '0');
        end case;
    end process;

    result <= res;
    zero   <= '1' when res = x"00000000" else '0';

end architecture rtl;