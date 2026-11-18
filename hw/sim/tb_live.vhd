library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

-- Streams cpu_top's live hsync/vsync/red/green/blue output to a real SDL2
-- window via GHDL's VHPIDIRECT foreign-function interface -- the same
-- mechanism proven out early in this project against the standalone VGA
-- timing generator. Nothing about the bridge needed to change: cpu_top's
-- video output is already standard 640x480 timing regardless of what's
-- actually driving it underneath (a hardcoded test pattern then, a real
-- memory-mapped framebuffer now).
--
-- Runs indefinitely -- close the SDL window to end the simulation
-- (sdl_new_frame returns 1 on SDL_QUIT, which this testbench treats as
-- "stop clocking").

entity tb_live is
end entity;

architecture sim of tb_live is

    procedure sdl_init;
    attribute foreign of sdl_init : procedure is "VHPIDIRECT libsdlbridge.dll sdl_init";

    procedure sdl_push_pixel_logical(log_x, log_y, r, g, b : integer);
    attribute foreign of sdl_push_pixel_logical : procedure is "VHPIDIRECT libsdlbridge.dll sdl_push_pixel_logical";

    procedure sdl_new_line;
    attribute foreign of sdl_new_line : procedure is "VHPIDIRECT libsdlbridge.dll sdl_new_line";

    impure function sdl_new_frame return integer;
    attribute foreign of sdl_new_frame : function is "VHPIDIRECT libsdlbridge.dll sdl_new_frame";

    procedure sdl_quit;
    attribute foreign of sdl_quit : procedure is "VHPIDIRECT libsdlbridge.dll sdl_quit";

    impure function sdl_poll_key return integer;
    attribute foreign of sdl_poll_key : function is "VHPIDIRECT libsdlbridge.dll sdl_poll_key";

    procedure sdl_init is begin assert false severity failure; end;
    procedure sdl_push_pixel_logical(log_x, log_y, r, g, b : integer) is begin assert false severity failure; end;
    procedure sdl_new_line is begin assert false severity failure; end;
    impure function sdl_new_frame return integer is begin assert false severity failure; return 0; end;
    procedure sdl_quit is begin assert false severity failure; end;
    impure function sdl_poll_key return integer is begin assert false severity failure; return -1; end;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal hsync, vsync, video_active : std_logic;
    signal red, green, blue : std_logic_vector(7 downto 0);
    signal quit_flag : integer := 0;
    signal key_valid : std_logic := '0';
    signal key_data : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Swap these to whatever program you want to watch run. Currently
    -- pointed at the text-rendering demo -- needs BOTH hex files, since
    -- Points at the echo demo -- the first genuinely interactive program
    -- in this project. Needs THREE hex files/generics now (text, rodata,
    -- and keyboard input wired through key_valid/key_data) rather than
    -- the usual two.
    dut: entity work.cpu_top
        generic map (
            HEX_FILE => "echo_demo_text.hex", ROM_WORDS => 1024,
            RODATA_HEX_FILE => "echo_demo_rodata.hex", RODATA_WORDS => 128
        )
        port map (
            clk => clk, rst => rst,
            hsync => hsync, vsync => vsync, video_active => video_active,
            red => red, green => green, blue => blue,
            key_valid => key_valid, key_data => key_data
        );

    clk_gen: process
    begin
        clk <= '0'; wait for 5 ns;
        clk <= '1'; wait for 5 ns;
        if quit_flag = 1 then
            wait;
        end if;
    end process;

    lifecycle: process
    begin
        sdl_init;
        wait until quit_flag = 1;
        sdl_quit;
        wait;
    end process;

    pump: process(clk)
        alias h_count_p is << signal .tb_live.dut.u_video_scanout.h_count : integer range 0 to 799 >>;
        alias v_count_p is << signal .tb_live.dut.u_video_scanout.v_count : integer range 0 to 524 >>;

        variable prev_hsync, prev_vsync : std_logic := '1';
        variable key_code : integer;
        variable log_x, log_y : integer;
        variable prev_log_x, prev_log_y : integer := -1;
    begin
        if rising_edge(clk) then
            -- Only push when the LOGICAL pixel coordinate actually
            -- changes since last cycle, not on every cycle -- this
            -- naturally fires exactly once per logical (320x200) pixel
            -- rather than once per physical (640x400) pixel, without
            -- needing to reason precisely about the 1-cycle output
            -- delay: a transition-detection approach stays correct even
            -- if the exact timing is off by a cycle, unlike trying to
            -- compute an exact h_count offset up front.
            log_x := h_count_p / 2;
            log_y := (v_count_p - 40) / 2; -- 40 = V_MARGIN

            if video_active = '1' and (log_x /= prev_log_x or log_y /= prev_log_y) then
                sdl_push_pixel_logical(log_x, log_y,
                                        to_integer(unsigned(red)),
                                        to_integer(unsigned(green)),
                                        to_integer(unsigned(blue)));
                prev_log_x := log_x;
                prev_log_y := log_y;
            end if;

            -- key_valid defaults low every cycle; only the one cycle
            -- right after a new scanline (see below) can pulse it high.
            key_valid <= '0';

            if hsync = '0' and prev_hsync = '1' then
                sdl_new_line;
                -- Polling once per scanline, not once per clock cycle --
                -- calling across the VHDL/C boundary every single cycle
                -- (up to ~420,000 times/frame) added enough overhead to
                -- visibly slow the whole simulation down; once per line
                -- (480 times/frame) is still far more than fast enough
                -- for anything at human typing speed, and matches the
                -- polling rate already used for keeping the window
                -- responsive.
                key_code := sdl_poll_key;
                if key_code >= 0 then
                    key_valid <= '1';
                    key_data <= std_logic_vector(to_unsigned(key_code, 8));
                end if;
            end if;
            prev_hsync := hsync;

            if vsync = '0' and prev_vsync = '1' then
                quit_flag <= sdl_new_frame;
            end if;
            prev_vsync := vsync;
        end if;
    end process;

    stim: process
    begin
        wait for 12 ns;
        rst <= '0';
        wait;
    end process;

end architecture sim;