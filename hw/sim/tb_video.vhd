library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Program: write palette[5] = red, then draw pixel (col=10,row=3) with
-- color index 5. Then let the VGA scanout free-run and watch for it to
-- actually reach that pixel's doubled screen position and output red --
-- the real end-to-end proof, not just a memory-content check.

entity tb_video is
end entity;

architecture sim of tb_video is

    subtype reg5    is std_logic_vector(4 downto 0);
    subtype f3      is std_logic_vector(2 downto 0);
    subtype f7      is std_logic_vector(6 downto 0);
    subtype opcode7 is std_logic_vector(6 downto 0);
    subtype imm12_t is std_logic_vector(11 downto 0);
    subtype imm20_t is std_logic_vector(19 downto 0);
    subtype imm21_t is std_logic_vector(20 downto 0);

    function r_type(funct7v : f7; rs2, rs1 : reg5; funct3v : f3; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin return funct7v & rs2 & rs1 & funct3v & rd & opcode; end function;

    function i_type(imm12 : imm12_t; rs1 : reg5; funct3v : f3; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin return imm12 & rs1 & funct3v & rd & opcode; end function;

    function s_type(imm12 : imm12_t; rs2, rs1 : reg5; funct3v : f3; opcode : opcode7) return std_logic_vector is
    begin return imm12(11 downto 5) & rs2 & rs1 & funct3v & imm12(4 downto 0) & opcode; end function;

    function u_type(imm20 : imm20_t; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin return imm20 & rd & opcode; end function;

    function j_type(imm21 : imm21_t; rd : reg5; opcode : opcode7) return std_logic_vector is
    begin return imm21(20) & imm21(10 downto 1) & imm21(11) & imm21(19 downto 12) & rd & opcode; end function;

    constant OP_R  : std_logic_vector(6 downto 0) := "0110011";
    constant OP_I  : std_logic_vector(6 downto 0) := "0010011";
    constant OP_ST : std_logic_vector(6 downto 0) := "0100011";
    constant OP_LUI: std_logic_vector(6 downto 0) := "0110111";
    constant OP_JAL: std_logic_vector(6 downto 0) := "1101111";
    constant F7_0  : std_logic_vector(6 downto 0) := "0000000";

    constant x0 : reg5 := "00000"; constant x1 : reg5 := "00001";
    constant x2 : reg5 := "00010"; constant x3 : reg5 := "00011";
    constant x4 : reg5 := "00100"; constant x5 : reg5 := "00101";
    constant x6 : reg5 := "00110";

    -- PAL_BASE = 0x00020000, entry 5 -> byte address 0x00020014
    -- FB_BASE  = 0x00010000, pixel (row=3,col=10) -> offset 3*320+10=970 (0x3CA)

    constant PROGRAM : word_array(0 to 8) := (
        0 => u_type(x"00FF0", x1, OP_LUI),                    -- lui x1,0xFF0 -> x1=0x00FF0000 (pure red in the low 24 bits)
        1 => u_type(x"00020", x2, OP_LUI),                    -- lui x2,0x20  -> x2=0x00020000 (PAL_BASE)
        2 => s_type(x"014", x1, x2, "010", OP_ST),            -- sw x1,20(x2)  -> palette[5] = red
        3 => i_type(x"005", x0, "000", x3, OP_I),             -- addi x3,x0,5   (color index to draw)
        4 => u_type(x"00010", x4, OP_LUI),                    -- lui x4,0x10   -> x4=0x00010000 (FB_BASE)
        5 => i_type(x"3CA", x0, "000", x5, OP_I),              -- addi x5,x0,970 (pixel offset)
        6 => r_type(F7_0, x5, x4, "000", x6, OP_R),             -- add x6,x4,x5   -> x6 = pixel's byte address
        7 => s_type(x"000", x3, x6, "000", OP_ST),               -- sb x3,0(x6)     -> framebuffer[970] = 5
        8 => j_type("000000000000000000000", x0, OP_JAL)          -- halt
    );

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal red, green, blue : std_logic_vector(7 downto 0);

    signal found_red : boolean := false;
    signal errors : integer := 0;

begin

    dut: entity work.cpu_top
        generic map (PROGRAM => PROGRAM)
        port map (clk => clk, rst => rst, red => red, green => green, blue => blue);

    clk_gen: process
    begin
        while now < 400000 ns loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    monitor: process(clk)
        alias h_count_p is << signal .tb_video.dut.u_video_scanout.h_count : integer range 0 to 799 >>;
        alias v_count_p is << signal .tb_video.dut.u_video_scanout.v_count : integer range 0 to 524 >>;
    begin
        if rising_edge(clk) and rst = '0' and red /= x"00" then
            found_red <= true;
            report "RED at h_count=" & integer'image(h_count_p) &
                   " v_count=" & integer'image(v_count_p) &
                   " rgb=" & to_hstring(red) & to_hstring(green) & to_hstring(blue);

            -- Expected: pixel (col=10,row=3) doubled -> the color was
            -- COMPUTED from h_count in {20,21}, v_count in {46,47}, but
            -- red/green/blue are registered one cycle behind h_count/
            -- v_count deliberately (see video_scanout.vhd) -- so by the
            -- time this process reads h_count_p/v_count_p, h_count has
            -- already advanced by one relative to what produced this
            -- red value. Checking {21,22} here, not {20,21}, accounts
            -- for that known, intentional delay.
            if not (h_count_p >= 21 and h_count_p <= 22 and v_count_p >= 46 and v_count_p <= 47) then
                report "FAIL: red appeared at an unexpected screen position" severity error;
                errors <= errors + 1;
            end if;
            if not (red = x"FF" and green = x"00" and blue = x"00") then
                report "FAIL: wrong color -- expected pure red" severity error;
                errors <= errors + 1;
            end if;
        end if;
    end process;

    stim: process
    begin
        wait for 12 ns;
        rst <= '0';
        wait for 399000 ns;

        if not found_red then
            report "FAIL: scan never reached the drawn pixel / never showed red" severity error;
        elsif errors = 0 then
            report "PASS: CPU-drawn pixel appeared at the correct screen position with the correct color -- full video path verified";
        else
            report integer'image(errors) & " TEST(S) FAILED" severity error;
        end if;
        wait;
    end process;

end architecture sim;
