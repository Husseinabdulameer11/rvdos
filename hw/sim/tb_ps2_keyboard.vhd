library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Drives real PS/2 frames (about 12.5 kHz, like the Basys3's USB-to-PS/2
-- PIC) into ps2_keyboard and checks the characters that come out.
entity tb_ps2_keyboard is
end entity;

architecture sim of tb_ps2_keyboard is
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal ps2_clk, ps2_data : std_logic := '1';
    signal key_valid_no, key_valid_us : std_logic;
    signal key_data_no, key_data_us : std_logic_vector(7 downto 0);
    signal done : boolean := false;

    type byte_list is array (natural range <>) of std_logic_vector(7 downto 0);
    signal got_no, got_us : byte_list(0 to 63) := (others => x"00");
    signal n_no, n_us : integer := 0;

    function s(t : string) return byte_list is
        variable r : byte_list(0 to t'length - 1);
    begin
        for i in t'range loop
            r(i - t'low) := std_logic_vector(to_unsigned(character'pos(t(i)), 8));
        end loop;
        return r;
    end function;
begin
    clk <= not clk after 20 ns when not done;   -- 25 MHz

    u_no: entity work.ps2_keyboard
        generic map (LAYOUT => "NO")
        port map (clk => clk, rst => rst, ps2_clk => ps2_clk, ps2_data => ps2_data,
                  key_valid => key_valid_no, key_data => key_data_no,
                  scan_valid => open, scan_code => open);

    u_us: entity work.ps2_keyboard
        generic map (LAYOUT => "US")
        port map (clk => clk, rst => rst, ps2_clk => ps2_clk, ps2_data => ps2_data,
                  key_valid => key_valid_us, key_data => key_data_us,
                  scan_valid => open, scan_code => open);

    collect: process(clk)
    begin
        if rising_edge(clk) then
            if key_valid_no = '1' then got_no(n_no) <= key_data_no; n_no <= n_no + 1; end if;
            if key_valid_us = '1' then got_us(n_us) <= key_data_us; n_us <= n_us + 1; end if;
        end if;
    end process;

    stim: process
        procedure send(b : std_logic_vector(7 downto 0)) is
            variable frame : std_logic_vector(10 downto 0);
            variable p : std_logic := '1';
        begin
            for i in 0 to 7 loop p := p xor b(i); end loop;
            frame := '1' & p & b & '0';
            for i in 0 to 10 loop
                ps2_data <= frame(i);
                wait for 20 us;
                ps2_clk <= '0';
                wait for 40 us;
                ps2_clk <= '1';
                wait for 20 us;
            end loop;
            wait for 100 us;
        end procedure;
        procedure tap(b : std_logic_vector(7 downto 0)) is
        begin
            send(b); send(x"F0"); send(b);
        end procedure;
        procedure tap_ext(b : std_logic_vector(7 downto 0)) is
        begin
            send(x"E0"); send(b); send(x"E0"); send(x"F0"); send(b);
        end procedure;
        procedure check(name : string; got : byte_list; n : integer; want : byte_list) is
        begin
            assert n = want'length
                report name & ": got " & integer'image(n) & " keys, expected " &
                       integer'image(want'length) severity error;
            for i in 0 to want'length - 1 loop
                assert got(i) = want(i)
                    report name & ": key " & integer'image(i) & " = " &
                           integer'image(to_integer(unsigned(got(i)))) & ", expected " &
                           integer'image(to_integer(unsigned(want(i)))) severity error;
            end loop;
        end procedure;
    begin
        wait for 200 ns;
        rst <= '0';
        wait for 1 us;

        tap(x"33"); tap(x"24"); tap(x"4B");                  -- h e l
        send(x"12"); tap(x"4B"); send(x"F0"); send(x"12");   -- Shift+l
        tap(x"44");                                           -- o
        send(x"59"); tap(x"1E"); send(x"F0"); send(x"59");   -- RShift+2
        tap(x"5A");                                           -- Enter
        tap(x"66");                                           -- Backspace
        send(x"14"); tap(x"21"); send(x"F0"); send(x"14");   -- Ctrl+C
        tap_ext(x"75"); tap_ext(x"6B"); tap_ext(x"71");       -- Up Left Delete
        tap(x"58"); tap(x"1C"); tap(x"58");                   -- Caps on, a, Caps off
        tap(x"1C");                                           -- a
        send(x"E0"); send(x"11"); tap(x"3E");                 -- AltGr+8
        send(x"E0"); send(x"F0"); send(x"11");
        tap(x"4E"); tap(x"4A"); tap(x"52");                   -- + - '  (US: - / ')
        send(x"12"); tap(x"3D"); send(x"F0"); send(x"12");   -- Shift+7
        tap(x"29");                                           -- space
        tap(x"54");                                           -- å / [

        -- a corrupted frame (bad parity) must be dropped, not decoded
        ps2_data <= '0';
        for i in 0 to 4 loop
            wait for 20 us; ps2_clk <= '0'; wait for 40 us; ps2_clk <= '1'; wait for 20 us;
        end loop;
        wait for 4 ms;                                        -- receiver times out
        tap(x"35");                                           -- y

        wait for 1 ms;
        check("NO", got_no, n_no,
              s("helLo""") & x"0A" & x"08" & x"03" & x"05" & x"13" & x"7F" &
              s("Aa") & s("[+-") & s("/ ") & s("y"));
        check("US", got_us, n_us,
              s("helLo@") & x"0A" & x"08" & x"03" & x"05" & x"13" & x"7F" &
              s("Aa") & s("8-/'") & s("& [") & s("y"));
        report "tb_ps2_keyboard done: " & integer'image(n_no) & " NO keys, " &
               integer'image(n_us) & " US keys checked";
        done <= true;
        wait;
    end process;
end architecture;
