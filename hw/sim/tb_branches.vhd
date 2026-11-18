library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Program: x1 = -1 (0xFFFFFFFF), x2 = 1.
-- Signed:   -1 < 1   -> BLT should take.
-- Unsigned: 0xFFFFFFFF > 1 -> BLTU should NOT take (this is the classic
-- gotcha that makes signed vs unsigned comparison worth testing explicitly:
-- the same two bit patterns compare oppositely depending on interpretation).
--
--   addi x1, x0, -1         ; x1 = 0xFFFFFFFF
--   addi x2, x0, 1            ; x2 = 1
--   blt  x1, x2, 8              ; -1 < 1 (signed) -> TAKEN, skip next
--   addi x3, x0, 111              ; SKIPPED
--   addi x4, x0, 222               ; x4 = 222 (BLT landed here)
--   bltu x1, x2, 8                   ; 0xFFFFFFFF < 1 (unsigned) -> NOT taken
--   addi x5, x0, 333                   ; x5 = 333 (falls through, not skipped)
--   bge  x2, x1, 8                       ; 1 >= -1 (signed) -> TAKEN, skip next
--   addi x6, x0, 444                       ; SKIPPED
--   addi x7, x0, 555                         ; x7 = 555
--   bgeu x2, x1, 8                             ; 1 >= 0xFFFFFFFF (unsigned) -> NOT taken
--   addi x8, x0, 666                             ; x8 = 666 (falls through)
--   jal  x0, 0                                     ; halt (infinite self-loop)

entity tb_branches is
end entity;

architecture sim of tb_branches is

    subtype reg5   is std_logic_vector(4 downto 0);
    subtype f3     is std_logic_vector(2 downto 0);
    subtype opcode7 is std_logic_vector(6 downto 0);
    subtype imm12_t is std_logic_vector(11 downto 0);
    subtype imm13_t is std_logic_vector(12 downto 0);
    subtype imm21_t is std_logic_vector(20 downto 0);

    function i_type(imm12 : imm12_t; rs1 : reg5; funct3v : f3; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin return imm12 & rs1 & funct3v & rd & opcode; end function;

    function b_type(imm13 : imm13_t; rs2, rs1 : reg5; funct3v : f3; opcode : opcode7) return std_logic_vector is
    begin return imm13(12) & imm13(10 downto 5) & rs2 & rs1 & funct3v & imm13(4 downto 1) & imm13(11) & opcode; end function;

    function j_type(imm21 : imm21_t; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin return imm21(20) & imm21(10 downto 1) & imm21(11) & imm21(19 downto 12) & rd & opcode; end function;

    constant OP_I  : std_logic_vector(6 downto 0) := "0010011";
    constant OP_BR : std_logic_vector(6 downto 0) := "1100011";
    constant OP_JAL: std_logic_vector(6 downto 0) := "1101111";

    constant x0 : reg5 := "00000"; constant x1 : reg5 := "00001";
    constant x2 : reg5 := "00010"; constant x3 : reg5 := "00011";
    constant x4 : reg5 := "00100"; constant x5 : reg5 := "00101";
    constant x6 : reg5 := "00110"; constant x7 : reg5 := "00111";
    constant x8 : reg5 := "01000";

    constant OFFSET8 : imm13_t := "0000000001000"; -- +8, skip exactly one instr

    constant PROGRAM : word_array(0 to 12) := (
        0  => i_type(x"FFF", x0, "000", x1, OP_I),           -- addi x1,x0,-1
        1  => i_type(x"001", x0, "000", x2, OP_I),           -- addi x2,x0,1
        2  => b_type(OFFSET8, x2, x1, "100", OP_BR),         -- blt  x1,x2,8
        3  => i_type(x"06F", x0, "000", x3, OP_I),           -- addi x3,x0,111 SKIPPED
        4  => i_type(x"0DE", x0, "000", x4, OP_I),           -- addi x4,x0,222
        5  => b_type(OFFSET8, x2, x1, "110", OP_BR),         -- bltu x1,x2,8 (NOT taken)
        6  => i_type(x"14D", x0, "000", x5, OP_I),           -- addi x5,x0,333
        7  => b_type(OFFSET8, x1, x2, "101", OP_BR),         -- bge  x2,x1,8
        8  => i_type(x"1BC", x0, "000", x6, OP_I),           -- addi x6,x0,444 SKIPPED
        9  => i_type(x"22B", x0, "000", x7, OP_I),           -- addi x7,x0,555
        10 => b_type(OFFSET8, x1, x2, "111", OP_BR),         -- bgeu x2,x1,8 (NOT taken)
        11 => i_type(x"29A", x0, "000", x8, OP_I),           -- addi x8,x0,666
        12 => j_type("000000000000000000000", x0, OP_JAL)   -- halt
    );

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal dbg_addr : std_logic_vector(4 downto 0) := (others => '0');
    signal dbg_data : std_logic_vector(31 downto 0);
    signal errors : integer := 0;

    procedure check_reg(addr : reg5; expected : integer; name : string;
                         signal a : out reg5; signal d : in std_logic_vector(31 downto 0);
                         signal errcount : inout integer) is
    begin
        a <= addr;
        wait for 1 ns;
        if to_integer(unsigned(d)) /= expected then
            report "FAIL: " & name & " expected " & integer'image(expected) &
                   " got " & integer'image(to_integer(unsigned(d))) severity error;
            errcount <= errcount + 1;
        else
            report "PASS: " & name & " = " & integer'image(expected);
        end if;
    end procedure;

begin

    dut: entity work.cpu_top
        generic map (PROGRAM => PROGRAM)
        port map (clk => clk, rst => rst, dbg_addr => dbg_addr, dbg_data => dbg_data);

    clk_gen: process
    begin
        while now < 400 ns loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    stim: process
    begin
        wait for 12 ns;
        rst <= '0';
        wait for 200 ns;

        check_reg(x3, 0,   "x3 (skipped by BLT: -1 < 1 signed)", dbg_addr, dbg_data, errors);
        check_reg(x4, 222, "x4 (BLT landed here)", dbg_addr, dbg_data, errors);
        check_reg(x5, 333, "x5 (BLTU not taken: 0xFFFFFFFF > 1 unsigned)", dbg_addr, dbg_data, errors);
        check_reg(x6, 0,   "x6 (skipped by BGE: 1 >= -1 signed)", dbg_addr, dbg_data, errors);
        check_reg(x7, 555, "x7 (BGE landed here)", dbg_addr, dbg_data, errors);
        check_reg(x8, 666, "x8 (BGEU not taken: 1 < 0xFFFFFFFF unsigned)", dbg_addr, dbg_data, errors);

        if errors = 0 then
            report "ALL TESTS PASSED";
        else
            report integer'image(errors) & " TEST(S) FAILED" severity error;
        end if;
        wait;
    end process;

end architecture sim;
