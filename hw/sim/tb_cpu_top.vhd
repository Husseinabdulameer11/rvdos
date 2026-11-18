library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Test program (hand-assembled below, field by field, same approach as the
-- decoder testbench -- avoids hand-computing full hex encodings by hand).
--
--   addi x1, x0, 5        ; x1 = 5
--   addi x2, x0, 10        ; x2 = 10
--   add  x3, x1, x2         ; x3 = 15   <- needs EX/MEM forwarding (x1 just written)
--   sw   x3, 0(x0)           ; mem[0] = 15
--   lw   x4, 0(x0)            ; x4 = 15  <- load
--   add  x5, x4, x4            ; x5 = 30  <- load-use hazard (x4 needed right after lw), forces a stall
--   beq  x3, x4, 8               ; 15 == 15, taken: skip the next instruction
--   addi x6, x0, 999               ; SKIPPED -- should never execute, x6 stays 0
--   addi x7, x0, 111                ; x7 = 111 (branch target lands here)
--   jal  x8, 8                       ; x8 = addr of next instr (link), jump forward by 8 (skip one)
--   addi x9, x0, 888                  ; SKIPPED by the jump
--   addi x10, x0, 222                  ; x10 = 222 (jump target)
--
-- Expected final register state: x1=5 x2=10 x3=15 x4=15 x5=30 x6=0
--                                 x7=111 x8=<addr of "addi x10..."> x9=0 x10=222

entity tb_cpu_top is
end entity;

architecture sim of tb_cpu_top is

    subtype reg5    is std_logic_vector(4 downto 0);
    subtype f3       is std_logic_vector(2 downto 0);
    subtype f7       is std_logic_vector(6 downto 0);
    subtype opcode7  is std_logic_vector(6 downto 0);
    subtype imm12_t  is std_logic_vector(11 downto 0);
    subtype imm13_t  is std_logic_vector(12 downto 0);
    subtype imm21_t  is std_logic_vector(20 downto 0);

    -- field helpers for assembling instructions (explicit descending-index
    -- subtypes below, since an unconstrained parameter picks up whatever
    -- index direction the literal at the call site defaults to -- which
    -- doesn't necessarily match the "downto" slicing used here)
    function r_type(funct7v : f7; rs2, rs1 : reg5; funct3v : f3; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin
        return funct7v & rs2 & rs1 & funct3v & rd & opcode;
    end function;

    function i_type(imm12 : imm12_t; rs1 : reg5; funct3v : f3; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin
        return imm12 & rs1 & funct3v & rd & opcode;
    end function;

    function s_type(imm12 : imm12_t; rs2, rs1 : reg5; funct3v : f3; opcode : opcode7) return std_logic_vector is
    begin
        return imm12(11 downto 5) & rs2 & rs1 & funct3v & imm12(4 downto 0) & opcode;
    end function;

    -- imm13: full signed branch offset (bit0 always 0, not stored separately)
    function b_type(imm13 : imm13_t; rs2, rs1 : reg5; funct3v : f3; opcode : opcode7) return std_logic_vector is
    begin
        return imm13(12) & imm13(10 downto 5) & rs2 & rs1 & funct3v & imm13(4 downto 1) & imm13(11) & opcode;
    end function;

    -- imm21: full signed jump offset (bit0 always 0, not stored separately)
    function j_type(imm21 : imm21_t; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin
        return imm21(20) & imm21(10 downto 1) & imm21(11) & imm21(19 downto 12) & rd & opcode;
    end function;

    constant OP_R  : std_logic_vector(6 downto 0) := "0110011";
    constant OP_I  : std_logic_vector(6 downto 0) := "0010011";
    constant OP_LD : std_logic_vector(6 downto 0) := "0000011";
    constant OP_ST : std_logic_vector(6 downto 0) := "0100011";
    constant OP_BR : std_logic_vector(6 downto 0) := "1100011";
    constant OP_JAL: std_logic_vector(6 downto 0) := "1101111";

    constant F7_0 : std_logic_vector(6 downto 0) := "0000000";

    constant x0 : std_logic_vector(4 downto 0) := "00000";
    constant x1 : std_logic_vector(4 downto 0) := "00001";
    constant x2 : std_logic_vector(4 downto 0) := "00010";
    constant x3 : std_logic_vector(4 downto 0) := "00011";
    constant x4 : std_logic_vector(4 downto 0) := "00100";
    constant x5 : std_logic_vector(4 downto 0) := "00101";
    constant x6 : std_logic_vector(4 downto 0) := "00110";
    constant x7 : std_logic_vector(4 downto 0) := "00111";
    constant x8 : std_logic_vector(4 downto 0) := "01000";
    constant x9 : std_logic_vector(4 downto 0) := "01001";
    constant x10 : std_logic_vector(4 downto 0) := "01010";

    constant PROGRAM : word_array(0 to 11) := (
        0  => i_type(x"005", x0, "000", x1, OP_I),                          -- addi x1,x0,5
        1  => i_type(x"00A", x0, "000", x2, OP_I),                          -- addi x2,x0,10
        2  => r_type(F7_0, x2, x1, "000", x3, OP_R),                        -- add  x3,x1,x2
        3  => s_type(x"000", x3, x0, "010", OP_ST),                        -- sw   x3,0(x0)
        4  => i_type(x"000", x0, "010", x4, OP_LD),                        -- lw   x4,0(x0)
        5  => r_type(F7_0, x4, x4, "000", x5, OP_R),                       -- add  x5,x4,x4
        6  => b_type("0000000001000", x4, x3, "000", OP_BR),               -- beq  x3,x4,8
        7  => i_type(x"3E7", x0, "000", x6, OP_I),                         -- addi x6,x0,999 (skipped)
        8  => i_type(x"06F", x0, "000", x7, OP_I),                         -- addi x7,x0,111
        9  => j_type("000000000000000001000", x8, OP_JAL),                 -- jal  x8,8
        10 => i_type(x"378", x0, "000", x9, OP_I),                         -- addi x9,x0,888 (skipped)
        11 => i_type(x"0DE", x0, "000", x10, OP_I)                         -- addi x10,x0,222
    );

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal dbg_addr : std_logic_vector(4 downto 0) := (others => '0');
    signal dbg_data : std_logic_vector(31 downto 0);

    signal errors : integer := 0;

    procedure check(cond : boolean; msg : string; signal errcount : inout integer) is
    begin
        if not cond then
            report "FAIL: " & msg severity error;
            errcount <= errcount + 1;
        else
            report "PASS: " & msg;
        end if;
    end procedure;

    procedure check_reg(addr : std_logic_vector(4 downto 0); expected : integer;
                         name : string; signal dbg_addr : out std_logic_vector(4 downto 0);
                         signal dbg_data : in std_logic_vector(31 downto 0);
                         signal errcount : inout integer) is
    begin
        dbg_addr <= addr;
        wait for 1 ns;
        check(to_integer(unsigned(dbg_data)) = expected,
              name & " = " & integer'image(expected) &
              " (got " & integer'image(to_integer(unsigned(dbg_data))) & ")",
              errcount);
    end procedure;

begin

    dut: entity work.cpu_top
        generic map (PROGRAM => PROGRAM)
        port map (clk => clk, rst => rst, dbg_addr => dbg_addr, dbg_data => dbg_data);

    clk_gen: process
    begin
        while now < 3000 ns loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    stim: process
    begin
        wait for 12 ns;
        rst <= '0';

        -- let the program run to completion: 12 instructions + pipeline
        -- fill/drain + one stall cycle, generously rounded up
        wait for 250 ns;

        check_reg(x1, 5,   "x1", dbg_addr, dbg_data, errors);
        check_reg(x2, 10,  "x2", dbg_addr, dbg_data, errors);
        check_reg(x3, 15,  "x3", dbg_addr, dbg_data, errors);
        check_reg(x4, 15,  "x4", dbg_addr, dbg_data, errors);
        check_reg(x5, 30,  "x5", dbg_addr, dbg_data, errors);
        check_reg(x6, 0,   "x6 (should be skipped by branch)", dbg_addr, dbg_data, errors);
        check_reg(x7, 111, "x7", dbg_addr, dbg_data, errors);
        check_reg(x9, 0,   "x9 (should be skipped by jump)", dbg_addr, dbg_data, errors);
        check_reg(x10, 222,"x10", dbg_addr, dbg_data, errors);

        if errors = 0 then
            report "ALL TESTS PASSED";
        else
            report integer'image(errors) & " TEST(S) FAILED" severity error;
        end if;
        wait;
    end process;

end architecture sim;
