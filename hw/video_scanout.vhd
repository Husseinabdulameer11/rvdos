library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Standard 640x480@60Hz VGA timing (25.175 MHz-ish pixel clock, same
-- constants as the original vga_top proof-of-concept earlier in this
-- project), driving a 320x200 indexed-color framebuffer scaled 2x in
-- both directions (640x400) and letterboxed with a 40-pixel black bar
-- top and bottom to fill the 480-line frame -- the classic way a
-- lower-resolution mode gets displayed on fixed VGA timing, same idea
-- real VGA "Mode 13h" hardware used.
--
-- This entity owns no memory itself -- it generates the scan address
-- (b_pixel_addr) for framebuffer_ram's port B, receives that pixel's
-- raw index back (b_pixel_data), forwards it to palette_ram's port B
-- (b_index) as a color lookup, and receives the final RGB back
-- (b_rgb). cpu_top wires this loop through the two RAM instances it
-- owns -- keeping this entity pure timing/address logic with no
-- direct dependency on how those RAMs are built.

entity video_scanout is
    port (
        clk : in  std_logic;
        rst : in  std_logic;

        hsync        : out std_logic;
        vsync        : out std_logic;
        video_active : out std_logic;
        red          : out std_logic_vector(7 downto 0);
        green        : out std_logic_vector(7 downto 0);
        blue         : out std_logic_vector(7 downto 0);

        -- to/from framebuffer_ram's port B
        b_pixel_addr : out std_logic_vector(17 downto 0);
        b_pixel_data : in  std_logic_vector(7 downto 0);

        -- to/from palette_ram's port B
        b_index : out std_logic_vector(7 downto 0);
        b_rgb   : in  std_logic_vector(23 downto 0)
    );
end entity video_scanout;

architecture rtl of video_scanout is

    constant H_VISIBLE : integer := 640;
    constant H_FRONT    : integer := 16;
    constant H_SYNC     : integer := 96;
    constant H_BACK     : integer := 48;
    constant H_TOTAL     : integer := H_VISIBLE + H_FRONT + H_SYNC + H_BACK; -- 800

    constant V_VISIBLE : integer := 480;
    constant V_FRONT    : integer := 10;
    constant V_SYNC     : integer := 2;
    constant V_BACK     : integer := 33;
    constant V_TOTAL     : integer := V_VISIBLE + V_FRONT + V_SYNC + V_BACK; -- 525

    -- 320x200 doubled to 640x400, letterboxed within 480 lines
    constant FB_WIDTH   : integer := 320;
    constant FB_HEIGHT  : integer := 200;
    constant V_MARGIN   : integer := (V_VISIBLE - FB_HEIGHT * 2) / 2; -- 40

    signal h_count : integer range 0 to H_TOTAL - 1 := 0;
    signal v_count : integer range 0 to V_TOTAL - 1 := 0;
    signal h_active, v_active : std_logic;
    signal hsync_comb, vsync_comb, video_active_comb : std_logic;

    signal picture_active : std_logic; -- within the letterboxed 320x200 region
    -- the beam position one clock from now: framebuffer_ram's port B is a
    -- clocked block RAM, so the pixel is requested a cycle early and its
    -- data is ready exactly when the beam reaches it
    signal h_next : integer range 0 to H_TOTAL - 1;
    signal v_next : integer range 0 to V_TOTAL - 1;
    signal pixel_col : integer range 0 to FB_WIDTH - 1;
    signal pixel_row : integer range 0 to FB_HEIGHT - 1;

begin

    -- horizontal counter
    process(clk, rst)
    begin
        if rst = '1' then
            h_count <= 0;
        elsif rising_edge(clk) then
            if h_count = H_TOTAL - 1 then
                h_count <= 0;
            else
                h_count <= h_count + 1;
            end if;
        end if;
    end process;

    -- vertical counter
    process(clk, rst)
    begin
        if rst = '1' then
            v_count <= 0;
        elsif rising_edge(clk) then
            if h_count = H_TOTAL - 1 then
                if v_count = V_TOTAL - 1 then
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
                end if;
            end if;
        end if;
    end process;

    -- Every output is registered together in one process, deliberately --
    -- if only red/green/blue were registered (to let the framebuffer/
    -- palette lookup settle) while hsync/vsync/video_active stayed
    -- combinational, the pixel data would land one clock cycle behind
    -- where the sync signals say the beam is, shifting the whole image
    -- by one pixel. Registering everything together keeps them in
    -- lockstep -- the whole frame is a uniform one cycle "behind" the
    -- internal counters, which is normal and imperceptible.
    h_active <= '1' when h_count < H_VISIBLE else '0';
    v_active <= '1' when v_count < V_VISIBLE else '0';

    hsync_comb        <= '0' when (h_count >= H_VISIBLE + H_FRONT) and
                                   (h_count <  H_VISIBLE + H_FRONT + H_SYNC) else '1';
    vsync_comb        <= '0' when (v_count >= V_VISIBLE + V_FRONT) and
                                   (v_count <  V_VISIBLE + V_FRONT + V_SYNC) else '1';
    video_active_comb <= h_active and v_active;

    -- letterboxed picture region: full width used (320*2=640 exactly),
    -- vertically centered with V_MARGIN black lines top and bottom
    picture_active <= '1' when (h_active = '1') and
                                (v_count >= V_MARGIN) and (v_count < V_MARGIN + FB_HEIGHT * 2)
                       else '0';

    h_next <= 0 when h_count = H_TOTAL - 1 else h_count + 1;
    v_next <= v_count when h_count /= H_TOTAL - 1 else
              0 when v_count = V_TOTAL - 1 else v_count + 1;

    pixel_col <= h_next / 2 when h_next < H_VISIBLE else 0;
    pixel_row <= (v_next - V_MARGIN) / 2 when (v_next >= V_MARGIN and v_next < V_MARGIN + FB_HEIGHT * 2) else 0;

    b_pixel_addr <= std_logic_vector(to_unsigned(pixel_row * FB_WIDTH + pixel_col, 18));
    b_index      <= b_pixel_data;

    process(clk)
    begin
        if rising_edge(clk) then
            hsync        <= hsync_comb;
            vsync        <= vsync_comb;
            video_active <= video_active_comb;
            if picture_active = '1' then
                red   <= b_rgb(23 downto 16);
                green <= b_rgb(15 downto 8);
                blue  <= b_rgb(7 downto 0);
            else
                red   <= (others => '0');
                green <= (others => '0');
                blue  <= (others => '0');
            end if;
        end if;
    end process;

end architecture rtl;
