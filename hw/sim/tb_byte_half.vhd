library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Program:
--   addi x1, x0, -1        ; x1 = 0xFFFFFFFF
--   sb   x1, 0(x0)          ; mem[0] byte0 = 0xFF, rest of word untouched (still 0)
--   lb   x2, 0(x0)           ; x2 = sign-extend(0xFF) = 0xFFFFFFFF (-1)
--   lbu  x3, 0(x0)             ; x3 = zero-extend(0xFF) = 0x000000FF (255)
--   addi x4, x0, 0x3CD          ; x4 = 0x3CD (arbitrary halfword-sized value)
--   sh   x4, 4(x0)                ; mem[4..5] = 0x03CD
--   lh   x5, 4(x0)                 ; x5 = sign-extend(0x03CD) = 0x000003CD (positive, top bit clear)
--   lhu  x6, 4(x0)                  ; x6 = zero-extend(0x03CD) = 0x000003CD (same, since top bit clear)
--   addi x7, x0, -100                ; x7 = 0xFFFFFF9C
--   sh   x7, 8(x0)                    ; mem[8..9] = 0xFF9C (negative halfword)
--   lh   x8, 8(x0)                     ; x8 = sign-extend(0xFF9C) = 0xFFFFFF9C (-100)
--   lhu  x9, 8(x0)                      ; x9 = zero-extend(0xFF9C) = 0x0000FF9C (65436)
--   sb   x1, 6(x0)                       ; store into byte lane 2 of word at addr4 (tests non-zero byte lane)
--   lbu  x10, 6(x0)                       ; x10 = 0xFF (255) -- confirms byte-lane addressing works
--   jal  x0, 0                             ; halt

entity tb_byte_half is
end entity;

architecture sim of tb_byte_half is

    subtype reg5   is std_logic_vector(4 downto 0);
    subtype f3     is std_logic_vector(2 downto 0);
    subtype opcode7 is std_logic_vector(6 downto 0);
    subtype imm12_t is std_logic_vector(11 downto 0);
    subtype imm21_t is std_logic_vector(20 downto 0);

    function i_type(imm12 : imm12_t; rs1 : reg5; funct3v : f3; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin return imm12 & rs1 & funct3v & rd & opcode; end function;

    function s_type(imm12 : imm12_t; rs2, rs1 : reg5; funct3v : f3; opcode : opcode7) return std_logic_vector is
    begin return imm12(11 downto 5) & rs2 & rs1 & funct3v & imm12(4 downto 0) & opcode; end function;

    function j_type(imm21 : imm21_t; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin return imm21(20) & imm21(10 downto 1) & imm21(11) & imm21(19 downto 12) & rd & opcode; end function;

    constant OP_I  : std_logic_vector(6 downto 0) := "0010011";
    constant OP_LD : std_logic_vector(6 downto 0) := "0000011";
    constant OP_ST : std_logic_vector(6 downto 0) := "0100011";
    constant OP_JAL: std_logic_vector(6 downto 0) := "1101111";

    constant x0 : reg5 := "00000"; constant x1 : reg5 := "00001";
    constant x2 : reg5 := "00010"; constant x3 : reg5 := "00011";
    constant x4 : reg5 := "00100"; constant x5 : reg5 := "00101";
    constant x6 : reg5 := "00110"; constant x7 : reg5 := "00111";
    constant x8 : reg5 := "01000"; constant x9 : reg5 := "01001";
    constant x10 : reg5 := "01010";

    constant PROGRAM : word_array(0 to 13) := (
        0  => i_type(x"FFF", x0, "000", x1, OP_I),          -- addi x1,x0,-1
        1  => s_type(x"000", x1, x0, "000", OP_ST),          -- sb x1,0(x0)
        2  => i_type(x"000", x0, "000", x2, OP_LD),           -- lb x2,0(x0)
        3  => i_type(x"000", x0, "100", x3, OP_LD),            -- lbu x3,0(x0)
        4  => i_type(x"3CD", x0, "000", x4, OP_I),              -- addi x4,x0,0x3CD
        5  => s_type(x"004", x4, x0, "001", OP_ST),              -- sh x4,4(x0)
        6  => i_type(x"004", x0, "001", x5, OP_LD),               -- lh x5,4(x0)
        7  => i_type(x"004", x0, "101", x6, OP_LD),                -- lhu x6,4(x0)
        8  => i_type(x"F9C", x0, "000", x7, OP_I),                  -- addi x7,x0,-100
        9  => s_type(x"008", x7, x0, "001", OP_ST),                  -- sh x7,8(x0)
        10 => i_type(x"008", x0, "001", x8, OP_LD),                   -- lh x8,8(x0)
        11 => i_type(x"008", x0, "101", x9, OP_LD),                    -- lhu x9,8(x0)
        12 => s_type(x"006", x1, x0, "000", OP_ST),                     -- sb x1,6(x0)
        13 => i_type(x"006", x0, "100", x10, OP_LD)                     -- lbu x10,6(x0)
    );

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal dbg_addr : std_logic_vector(4 downto 0) := (others => '0');
    signal dbg_data : std_logic_vector(31 downto 0);
    signal errors : integer := 0;

    procedure check_reg(addr : reg5; expected : integer; name : string;
                         signal a : out reg5; signal d : in std_logic_vector(31 downto 0);
                         signal errcount : inout integer) is
        variable got : integer;
    begin
        a <= addr;
        wait for 1 ns;
        got := to_integer(signed(d)); -- read as signed so negative expected values compare correctly
        if got /= expected then
            report "FAIL: " & name & " expected " & integer'image(expected) &
                   " got " & integer'image(got) severity error;
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

        check_reg(x2, -1,     "x2 (LB sign-extend 0xFF)", dbg_addr, dbg_data, errors);
        check_reg(x3, 255,    "x3 (LBU zero-extend 0xFF)", dbg_addr, dbg_data, errors);
        check_reg(x5, 973,    "x5 (LH sign-extend 0x03CD, positive)", dbg_addr, dbg_data, errors);
        check_reg(x6, 973,    "x6 (LHU zero-extend 0x03CD)", dbg_addr, dbg_data, errors);
        check_reg(x8, -100,   "x8 (LH sign-extend 0xFF9C, negative)", dbg_addr, dbg_data, errors);
        check_reg(x9, 65436,  "x9 (LHU zero-extend 0xFF9C)", dbg_addr, dbg_data, errors);
        check_reg(x10, 255,   "x10 (LBU from byte lane 2, addr=6)", dbg_addr, dbg_data, errors);

        if errors = 0 then
            report "ALL TESTS PASSED";
        else
            report integer'image(errors) & " TEST(S) FAILED" severity error;
        end if;
        wait;
    end process;

end architecture sim;
