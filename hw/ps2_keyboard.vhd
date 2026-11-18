library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PS/2 keyboard front end for the Basys3.
--
-- The Basys3 has no PS/2 socket. Its USB-A port (J2, "USB HOST") is run by
-- a PIC24 microcontroller that talks USB HID to the keyboard and re-sends
-- every key to the FPGA as ordinary PS/2 scan code set 2 on two pins
-- (PS2Clk C17, PS2Data B17). So a USB keyboard looks exactly like a PS/2
-- keyboard to the FPGA, and this module is a plain PS/2 receiver.
--
-- Output side matches keyboard.vhd's injection port: key_valid pulses for
-- one clock with key_data holding the character. Codes follow syscall.h:
-- Enter = '\n', Backspace = 8, Tab = 9, Esc = 27, Delete = 127, and the
-- WordStar control codes for navigation (Up ^E, Down ^X, Left ^S,
-- Right ^D, Home ^A, End ^F, PgUp ^R, PgDn 30). Ctrl+letter gives the
-- usual control code (Ctrl+C = 3).
--
-- LAYOUT selects which symbol each key position produces: "NO" for a
-- Norwegian keyboard, "US" for US. Letters and digits are the same in
-- both. Keys that produce non-ASCII characters (æ ø å § ¤ £) are ignored,
-- since the font is ASCII. Dead keys (¨ ^ ~ ` ´) produce their character
-- directly instead of waiting for a following letter.

entity ps2_keyboard is
    generic (
        LAYOUT : string := "NO"
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        ps2_clk  : in std_logic;
        ps2_data : in std_logic;

        key_valid : out std_logic;
        key_data  : out std_logic_vector(7 downto 0);

        -- raw scan code bytes, for debugging on the LEDs
        scan_valid : out std_logic;
        scan_code  : out std_logic_vector(7 downto 0)
    );
end entity ps2_keyboard;

architecture rtl of ps2_keyboard is

    subtype byte is std_logic_vector(7 downto 0);

    function ch(c : character) return byte is
    begin
        return std_logic_vector(to_unsigned(character'pos(c), 8));
    end function;

    function num(n : integer) return byte is
    begin
        return std_logic_vector(to_unsigned(n, 8));
    end function;

    constant NONE : byte := x"00";
    constant NORWEGIAN : boolean := LAYOUT = "NO";

    -- Letters: same position in every layout we support.
    function letter(code : byte) return byte is
    begin
        case code is
            when x"1C" => return ch('a'); when x"32" => return ch('b');
            when x"21" => return ch('c'); when x"23" => return ch('d');
            when x"24" => return ch('e'); when x"2B" => return ch('f');
            when x"34" => return ch('g'); when x"33" => return ch('h');
            when x"43" => return ch('i'); when x"3B" => return ch('j');
            when x"42" => return ch('k'); when x"4B" => return ch('l');
            when x"3A" => return ch('m'); when x"31" => return ch('n');
            when x"44" => return ch('o'); when x"4D" => return ch('p');
            when x"15" => return ch('q'); when x"2D" => return ch('r');
            when x"1B" => return ch('s'); when x"2C" => return ch('t');
            when x"3C" => return ch('u'); when x"2A" => return ch('v');
            when x"1D" => return ch('w'); when x"22" => return ch('x');
            when x"35" => return ch('y'); when x"1A" => return ch('z');
            when others => return NONE;
        end case;
    end function;

    -- Keys that don't depend on layout or shift.
    function fixed(code : byte) return byte is
    begin
        case code is
            when x"29" => return ch(' ');
            when x"5A" => return num(10);   -- Enter -> '\n'
            when x"66" => return num(8);    -- Backspace
            when x"0D" => return num(9);    -- Tab
            when x"76" => return num(27);   -- Esc
            -- numeric keypad, treated as if Num Lock is always on
            when x"70" => return ch('0'); when x"69" => return ch('1');
            when x"72" => return ch('2'); when x"7A" => return ch('3');
            when x"6B" => return ch('4'); when x"73" => return ch('5');
            when x"74" => return ch('6'); when x"6C" => return ch('7');
            when x"75" => return ch('8'); when x"7D" => return ch('9');
            when x"7C" => return ch('*'); when x"7B" => return ch('-');
            when x"79" => return ch('+'); when x"71" => return ch('.');
            when others => return NONE;
        end case;
    end function;

    -- Digit row and punctuation, US layout.
    function us_sym(code : byte; shift : boolean) return byte is
    begin
        if not shift then
            case code is
                when x"0E" => return ch('`');
                when x"16" => return ch('1'); when x"1E" => return ch('2');
                when x"26" => return ch('3'); when x"25" => return ch('4');
                when x"2E" => return ch('5'); when x"36" => return ch('6');
                when x"3D" => return ch('7'); when x"3E" => return ch('8');
                when x"46" => return ch('9'); when x"45" => return ch('0');
                when x"4E" => return ch('-'); when x"55" => return ch('=');
                when x"54" => return ch('['); when x"5B" => return ch(']');
                when x"5D" => return ch('\'); when x"61" => return ch('\');
                when x"4C" => return ch(';'); when x"52" => return ch(''');
                when x"41" => return ch(','); when x"49" => return ch('.');
                when x"4A" => return ch('/');
                when others => return NONE;
            end case;
        else
            case code is
                when x"0E" => return ch('~');
                when x"16" => return ch('!'); when x"1E" => return ch('@');
                when x"26" => return ch('#'); when x"25" => return ch('$');
                when x"2E" => return ch('%'); when x"36" => return ch('^');
                when x"3D" => return ch('&'); when x"3E" => return ch('*');
                when x"46" => return ch('('); when x"45" => return ch(')');
                when x"4E" => return ch('_'); when x"55" => return ch('+');
                when x"54" => return ch('{'); when x"5B" => return ch('}');
                when x"5D" => return ch('|'); when x"61" => return ch('|');
                when x"4C" => return ch(':'); when x"52" => return ch('"');
                when x"41" => return ch('<'); when x"49" => return ch('>');
                when x"4A" => return ch('?');
                when others => return NONE;
            end case;
        end if;
    end function;

    -- Digit row and punctuation, Norwegian layout.
    function no_sym(code : byte; shift, altgr : boolean) return byte is
    begin
        if altgr then
            case code is
                when x"1E" => return ch('@'); when x"25" => return ch('$');
                when x"3D" => return ch('{'); when x"3E" => return ch('[');
                when x"46" => return ch(']'); when x"45" => return ch('}');
                when x"5B" => return ch('~'); when x"55" => return ch(''');
                when others => return NONE;
            end case;
        elsif not shift then
            case code is
                when x"0E" => return ch('|');
                when x"16" => return ch('1'); when x"1E" => return ch('2');
                when x"26" => return ch('3'); when x"25" => return ch('4');
                when x"2E" => return ch('5'); when x"36" => return ch('6');
                when x"3D" => return ch('7'); when x"3E" => return ch('8');
                when x"46" => return ch('9'); when x"45" => return ch('0');
                when x"4E" => return ch('+'); when x"55" => return ch('\');
                when x"5B" => return ch('"');  -- the ¨ key; nearest ASCII
                when x"5D" => return ch(''');
                when x"61" => return ch('<');
                when x"41" => return ch(','); when x"49" => return ch('.');
                when x"4A" => return ch('-');
                when others => return NONE;   -- å ø æ: not ASCII
            end case;
        else
            case code is
                when x"16" => return ch('!'); when x"1E" => return ch('"');
                when x"26" => return ch('#');
                when x"2E" => return ch('%'); when x"36" => return ch('&');
                when x"3D" => return ch('/'); when x"3E" => return ch('(');
                when x"46" => return ch(')'); when x"45" => return ch('=');
                when x"4E" => return ch('?'); when x"55" => return ch('`');
                when x"5B" => return ch('^'); when x"5D" => return ch('*');
                when x"61" => return ch('>');
                when x"41" => return ch(';'); when x"49" => return ch(':');
                when x"4A" => return ch('_');
                when others => return NONE;   -- § ¤ Å Ø Æ: not ASCII
            end case;
        end if;
    end function;

    -- E0-prefixed keys: navigation block, keypad Enter and '/'.
    function extended(code : byte) return byte is
    begin
        case code is
            when x"75" => return num(5);    -- Up     ^E
            when x"72" => return num(24);   -- Down   ^X
            when x"6B" => return num(19);   -- Left   ^S
            when x"74" => return num(4);    -- Right  ^D
            when x"6C" => return num(1);    -- Home   ^A
            when x"69" => return num(6);    -- End    ^F
            when x"7D" => return num(18);   -- PgUp   ^R
            when x"7A" => return num(30);   -- PgDn
            when x"71" => return num(127);  -- Delete
            when x"5A" => return num(10);   -- keypad Enter
            when x"4A" => return ch('/');   -- keypad /
            when others => return NONE;
        end case;
    end function;

    -- ---- receiver ----
    signal clk_sync, data_sync : std_logic_vector(1 downto 0) := "11";
    signal clk_hist  : std_logic_vector(7 downto 0) := (others => '1');
    signal clk_clean : std_logic := '1';
    signal shift_reg : std_logic_vector(10 downto 0) := (others => '0');
    signal bit_count : integer range 0 to 11 := 0;
    signal idle_cnt  : unsigned(15 downto 0) := (others => '0');
    signal code_valid : std_logic := '0';
    signal code       : byte := (others => '0');

    -- ---- decoder ----
    signal got_e0, got_f0 : std_logic := '0';
    signal lshift, rshift, lctrl, rctrl, altgr, caps, caps_held : std_logic := '0';

begin

    -- Stage 1: synchronize, filter glitches on the PS/2 clock, and shift
    -- in a frame on each falling edge: start(0), 8 data bits LSB first,
    -- odd parity, stop(1).
    process(clk)
        variable frame : std_logic_vector(10 downto 0);
    begin
        if rising_edge(clk) then
            code_valid <= '0';
            clk_sync  <= clk_sync(0) & ps2_clk;
            data_sync <= data_sync(0) & ps2_data;
            clk_hist  <= clk_hist(6 downto 0) & clk_sync(1);

            if rst = '1' then
                clk_clean <= '1';
                bit_count <= 0;
                idle_cnt  <= (others => '0');
            else
                -- a half-received frame is dropped if the line goes quiet
                -- for ~2.6 ms at 25 MHz (a real frame takes about 1 ms)
                if idle_cnt /= x"FFFF" then
                    idle_cnt <= idle_cnt + 1;
                else
                    bit_count <= 0;
                end if;

                if clk_hist = x"FF" then
                    clk_clean <= '1';
                elsif clk_hist = x"00" then
                    clk_clean <= '0';
                    if clk_clean = '1' then          -- falling edge
                        idle_cnt <= (others => '0');
                        frame := data_sync(1) & shift_reg(10 downto 1);
                        shift_reg <= frame;
                        if bit_count = 10 then
                            bit_count <= 0;
                            -- frame(0) start, frame(8:1) data, frame(9) parity, frame(10) stop
                            if frame(0) = '0' and frame(10) = '1' and
                               (frame(1) xor frame(2) xor frame(3) xor frame(4) xor
                                frame(5) xor frame(6) xor frame(7) xor frame(8) xor
                                frame(9)) = '1' then
                                code       <= frame(8 downto 1);
                                code_valid <= '1';
                            end if;
                        else
                            bit_count <= bit_count + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    scan_valid <= code_valid;
    scan_code  <= code;

    -- Stage 2: turn scan codes into characters.
    process(clk)
        variable shift_on, ctrl_on, altgr_on, is_break, ext : boolean;
        variable c, l : byte;
        variable held : std_logic;
    begin
        if rising_edge(clk) then
            key_valid <= '0';
            if rst = '1' then
                got_e0 <= '0'; got_f0 <= '0';
                lshift <= '0'; rshift <= '0'; lctrl <= '0'; rctrl <= '0';
                altgr <= '0'; caps <= '0'; caps_held <= '0';
            elsif code_valid = '1' then
                if code = x"E0" then
                    got_e0 <= '1';
                elsif code = x"F0" then
                    got_f0 <= '1';
                elsif code = x"E1" then
                    null;   -- Pause key prefix; its bytes all decode to nothing
                else
                    got_e0 <= '0';
                    got_f0 <= '0';
                    is_break := got_f0 = '1';
                    ext     := got_e0 = '1';
                    if is_break then held := '0'; else held := '1'; end if;

                    -- modifier keys: track held state, produce no character
                    if not ext and code = x"12" then
                        lshift <= held;
                    elsif not ext and code = x"59" then
                        rshift <= held;
                    elsif code = x"14" and not ext then
                        lctrl <= held;
                    elsif code = x"14" and ext then
                        rctrl <= held;
                    elsif code = x"11" and ext then
                        altgr <= held;
                    elsif code = x"58" and not ext then
                        -- Caps Lock toggles once per press, ignoring auto-repeat
                        if is_break then
                            caps_held <= '0';
                        elsif caps_held = '0' then
                            caps_held <= '1';
                            caps <= not caps;
                        end if;
                    elsif not is_break then
                        shift_on := lshift = '1' or rshift = '1';
                        ctrl_on  := lctrl = '1' or rctrl = '1';
                        altgr_on := altgr = '1' and NORWEGIAN;

                        if ext then
                            c := extended(code);
                        else
                            l := letter(code);
                            if l /= NONE then
                                if ctrl_on then
                                    c := l and x"1F";                 -- Ctrl+A = 1 ...
                                elsif shift_on xor (caps = '1') then
                                    c := l and x"DF";                 -- upper case
                                else
                                    c := l;
                                end if;
                                if altgr_on then
                                    c := NONE;                        -- € µ etc.
                                end if;
                            else
                                c := fixed(code);
                                if c = NONE then
                                    if NORWEGIAN then
                                        c := no_sym(code, shift_on, altgr_on);
                                    else
                                        c := us_sym(code, shift_on);
                                    end if;
                                end if;
                            end if;
                        end if;

                        if c /= NONE then
                            key_data  <= c;
                            key_valid <= '1';
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
