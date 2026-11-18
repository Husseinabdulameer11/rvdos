library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Program:
--   auipc x1, 0x1              ; x1 = PC(=0) + 0x1000 = 0x00001000
--   addi  x2, x0, 20             ; x2 = 20  (offset used as JALR base component)
--   jalr  x3, x2, 12               ; x3 = link addr (this instr's PC+4 = 8+4=12*4? word idx2*4=8, link=12)
--                                    ; target = (x2 + 12) & ~1 = (20+12)=32, word index 32/4=8
--   addi  x4, x0, 999                ; SKIPPED (word idx3, wrong path)
--   addi  x5, x0, 999                 ; SKIPPED (word idx4..7, wrong path, padding)
--   ... (pad to word index 8)
--   addi  x6, x0, 777                  ; word idx8 = JALR target: x6 = 777

entity tb_jalr_auipc is
end entity;

architecture sim of tb_jalr_auipc is

    subtype reg5    is std_logic_vector(4 downto 0);
    subtype f3       is std_logic_vector(2 downto 0);
    subtype f7       is std_logic_vector(6 downto 0);
    subtype opcode7  is std_logic_vector(6 downto 0);
    subtype imm12_t  is std_logic_vector(11 downto 0);
    subtype imm20_t  is std_logic_vector(19 downto 0);

    function i_type(imm12 : imm12_t; rs1 : reg5; funct3v : f3; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin
        return imm12 & rs1 & funct3v & rd & opcode;
    end function;

    function u_type(imm20 : imm20_t; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin
        return imm20 & rd & opcode;
    end function;

    subtype imm21_t is std_logic_vector(20 downto 0);
    function j_type(imm21 : imm21_t; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin
        return imm21(20) & imm21(10 downto 1) & imm21(11) & imm21(19 downto 12) & rd & opcode;
    end function;

    constant OP_I     : std_logic_vector(6 downto 0) := "0010011";
    constant OP_JALR   : std_logic_vector(6 downto 0) := "1100111";
    constant OP_AUIPC  : std_logic_vector(6 downto 0) := "0010111";
    constant OP_JAL    : std_logic_vector(6 downto 0) := "1101111";

    constant x0 : reg5 := "00000";
    constant x1 : reg5 := "00001";
    constant x2 : reg5 := "00010";
    constant x3 : reg5 := "00011";
    constant x4 : reg5 := "00100";
    constant x5 : reg5 := "00101";
    constant x6 : reg5 := "00110";

    constant NOP : std_logic_vector(31 downto 0) := i_type(x"000", x0, "000", x0, OP_I);

    constant PROGRAM : word_array(0 to 9) := (
        0 => u_type(x"00001", x1, OP_AUIPC),          -- auipc x1, 0x1        (word 0, PC=0)
        1 => i_type(x"014", x0, "000", x2, OP_I),      -- addi  x2, x0, 20      (word 1)
        2 => i_type(x"00C", x2, "000", x3, OP_JALR),    -- jalr  x3, x2, 12       (word 2, PC=8)
        3 => i_type(x"3E7", x0, "000", x4, OP_I),        -- addi  x4,x0,999 SKIPPED
        4 => NOP,
        5 => NOP,
        6 => NOP,
        7 => NOP,
        8 => i_type(x"309", x0, "000", x6, OP_I),         -- addi x6,x0,777 (JALR target, word 8)
        9 => j_type("000000000000000000000", x0, OP_JAL)  -- jal x0,0 -- infinite self-loop (halt)
    );

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal dbg_addr : std_logic_vector(4 downto 0) := (others => '0');
    signal dbg_data : std_logic_vector(31 downto 0);
    signal errors : integer := 0;

    procedure check_reg(addr : std_logic_vector(4 downto 0); expected : integer;
                         name : string; signal a : out std_logic_vector(4 downto 0);
                         signal d : in std_logic_vector(31 downto 0);
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
        while now < 500 ns loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    stim: process
    begin
        wait for 12 ns;
        rst <= '0';
        wait for 150 ns;

        check_reg(x1, 4096,  "x1 (AUIPC: PC=0 + 0x1000)", dbg_addr, dbg_data, errors);
        check_reg(x2, 20,    "x2", dbg_addr, dbg_data, errors);
        check_reg(x3, 12,    "x3 (JALR link = PC+4 of jalr instr)", dbg_addr, dbg_data, errors);
        check_reg(x4, 0,     "x4 (skipped by JALR)", dbg_addr, dbg_data, errors);
        check_reg(x6, 777,   "x6 (JALR landed here)", dbg_addr, dbg_data, errors);

        if errors = 0 then
            report "ALL TESTS PASSED";
        else
            report integer'image(errors) & " TEST(S) FAILED" severity error;
        end if;
        wait;
    end process;

end architecture sim;
