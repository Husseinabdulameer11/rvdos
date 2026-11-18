library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity cpu_top is
    generic (
        PROGRAM   : word_array := (0 => x"00000013"); -- default: single NOP, used only when HEX_FILE is empty
        HEX_FILE  : string := ""; -- if non-empty, load instructions from this hex file instead of PROGRAM
        ROM_WORDS : integer := 256; -- instruction ROM size; must be large enough to hold HEX_FILE's word count
        RODATA_HEX_FILE : string := ""; -- if non-empty, enables the read-only .rodata memory (see rodata_rom.vhd)
        RODATA_WORDS    : integer := 1024; -- 4KB default
        RAM_WORDS       : integer := 256   -- data_ram size (power of two; addresses wrap mod this).
                                           -- 256 (1KB) suits the small demos; RVDOS needs 8192 (32KB).
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- debug/observation port into the register file
        dbg_addr : in  std_logic_vector(4 downto 0) := (others => '0');
        dbg_data : out std_logic_vector(31 downto 0);

        -- VGA output -- 640x480@60, driven by the memory-mapped 320x200
        -- indexed-color framebuffer + palette (see the MEM stage below)
        hsync        : out std_logic;
        vsync        : out std_logic;
        video_active : out std_logic;
        red          : out std_logic_vector(7 downto 0);
        green        : out std_logic_vector(7 downto 0);
        blue         : out std_logic_vector(7 downto 0);

        -- Keyboard input -- one pending key, pulse key_valid for one
        -- cycle to inject it. Fed by either a synthetic testbench
        -- process or real SDL2 keyboard events (tb_live.vhd); cpu_top
        -- itself doesn't know or care which.
        key_valid : in std_logic := '0';
        key_data  : in std_logic_vector(7 downto 0) := (others => '0')
    );
end entity cpu_top;

architecture rtl of cpu_top is

    -- Memory-mapped I/O address ranges. Anything outside these falls
    -- through to the regular data_ram (existing behavior, unchanged).
    constant FB_BASE  : unsigned(31 downto 0) := x"00010000";
    constant FB_SIZE  : integer := 320 * 200; -- 64000 bytes
    constant PAL_BASE : unsigned(31 downto 0) := x"00020000";
    constant PAL_SIZE : integer := 256 * 4; -- 1024 bytes
    constant RODATA_BASE : unsigned(31 downto 0) := x"00030000";
    constant KBD_BASE : unsigned(31 downto 0) := x"00040000";
    constant KBD_SIZE : integer := 8; -- 2 word-registers

    -- ===== IF =====
    signal pc, pc_next, pc_plus4_if, instr_if : std_logic_vector(31 downto 0);
    -- the address the instruction ROM reads on this edge: whatever pc_reg
    -- will hold after it, so instr_if is always the word at pc
    signal fetch_addr : std_logic_vector(31 downto 0);
    signal stall_pc, stall_if_id, flush_if_id : std_logic;

    -- ===== IF/ID -> ID =====
    signal pc_id, pc_plus4_id, instr_id : std_logic_vector(31 downto 0);

    signal opcode_id  : std_logic_vector(6 downto 0);
    signal rd_id      : std_logic_vector(4 downto 0);
    signal funct3_id  : std_logic_vector(2 downto 0);
    signal rs1_id     : std_logic_vector(4 downto 0);
    signal rs2_id     : std_logic_vector(4 downto 0);
    signal funct7_id  : std_logic_vector(6 downto 0);
    signal imm_i_id, imm_s_id, imm_b_id, imm_u_id, imm_j_id, imm_id : std_logic_vector(31 downto 0);

    signal reg_write_id : std_logic;
    signal alu_src_a_id : std_logic_vector(1 downto 0);
    signal alu_src_b_id : std_logic;
    signal alu_op_id     : std_logic_vector(3 downto 0);
    signal mem_read_id, mem_write_id, branch_id, illegal_id : std_logic;
    signal mem_size_id : std_logic_vector(1 downto 0);
    signal mem_unsigned_id : std_logic;
    signal jump_type_id  : std_logic_vector(1 downto 0);
    signal result_src_id : std_logic_vector(1 downto 0);
    signal imm_sel_id    : std_logic_vector(2 downto 0);

    signal rs1_data_id, rs2_data_id : std_logic_vector(31 downto 0);
    signal flush_id_ex : std_logic;

    -- ===== ID/EX -> EX =====
    signal pc_ex, pc_plus4_ex, rs1_data_ex, rs2_data_ex, imm_ex : std_logic_vector(31 downto 0);
    signal rs1_addr_ex, rs2_addr_ex, rd_addr_ex : std_logic_vector(4 downto 0);
    signal funct3_ex : std_logic_vector(2 downto 0);
    signal reg_write_ex, mem_read_ex, mem_write_ex, branch_ex : std_logic;
    signal mem_size_ex : std_logic_vector(1 downto 0);
    signal mem_unsigned_ex : std_logic;
    signal alu_src_a_ex : std_logic_vector(1 downto 0);
    signal alu_src_b_ex : std_logic;
    signal jump_type_ex : std_logic_vector(1 downto 0);
    signal alu_op_ex : std_logic_vector(3 downto 0);
    signal result_src_ex : std_logic_vector(1 downto 0);

    signal forward_a, forward_b : std_logic_vector(1 downto 0);
    signal fwd_rs1, fwd_rs2 : std_logic_vector(31 downto 0);
    signal alu_operand_a, alu_operand_b : std_logic_vector(31 downto 0);
    signal alu_result_ex : std_logic_vector(31 downto 0);
    signal alu_zero : std_logic;

    signal branch_taken_ex, pc_src_ex : std_logic;
    signal branch_target_ex, jalr_target_ex : std_logic_vector(31 downto 0);

    -- ===== EX/MEM -> MEM =====
    signal pc_plus4_mem, alu_result_mem, store_data_mem : std_logic_vector(31 downto 0);
    signal rd_addr_mem : std_logic_vector(4 downto 0);
    signal reg_write_mem, mem_read_mem, mem_write_mem : std_logic;
    signal mem_size_mem : std_logic_vector(1 downto 0);
    signal mem_unsigned_mem : std_logic;
    signal result_src_mem : std_logic_vector(1 downto 0);
    signal mem_rdata_raw, mem_rdata : std_logic_vector(31 downto 0);
    signal is_fb_mem, is_pal_mem : std_logic;
    signal is_rodata_mem : std_logic;
    signal is_kbd_mem : std_logic;
    signal fb_addr_local, pal_addr_local : std_logic_vector(31 downto 0);
    signal rodata_addr_local : std_logic_vector(31 downto 0);
    signal kbd_addr_local : std_logic_vector(31 downto 0);
    signal data_ram_rdata, fb_ram_rdata, pal_ram_rdata : std_logic_vector(31 downto 0);
    signal rodata_rdata : std_logic_vector(31 downto 0);
    signal kbd_rdata : std_logic_vector(31 downto 0);
    signal store_wdata_aligned : std_logic_vector(31 downto 0);
    signal store_byte_enable : std_logic_vector(3 downto 0);
    -- palette and keyboard reads are small and stay combinational; this is
    -- their read data, registered into WB alongside the block RAM outputs
    signal small_rdata_mem : std_logic_vector(31 downto 0);

    -- video_scanout <-> framebuffer_ram/palette_ram port B loop
    signal vs_pixel_addr : std_logic_vector(17 downto 0);
    signal vs_pixel_data : std_logic_vector(7 downto 0);
    signal vs_pal_index  : std_logic_vector(7 downto 0);
    signal vs_pal_rgb    : std_logic_vector(23 downto 0);

    -- ===== MEM/WB -> WB =====
    signal pc_plus4_wb, alu_result_wb, mem_data_wb, wb_data : std_logic_vector(31 downto 0);
    signal rd_addr_wb : std_logic_vector(4 downto 0);
    signal reg_write_wb : std_logic;
    signal result_src_wb : std_logic_vector(1 downto 0);
    -- block RAM reads land in WB, so the source select and the
    -- load-extension controls travel to WB with them
    signal src_sel_wb : std_logic_vector(1 downto 0) := "00"; -- 00 data_ram, 01 fb, 10 rodata, 11 small
    signal small_rdata_wb : std_logic_vector(31 downto 0) := (others => '0');
    signal addr_lsb_wb : std_logic_vector(1 downto 0) := "00";
    signal mem_size_wb : std_logic_vector(1 downto 0) := "10";
    signal mem_unsigned_wb : std_logic := '0';
    signal mem_rdata_raw_wb, load_data_wb : std_logic_vector(31 downto 0);

begin

    -- ================= IF =================
    u_pc_reg: entity work.pc_reg
        port map (clk => clk, rst => rst, stall => stall_pc, pc_next => pc_next, pc => pc);

    u_pc_adder: entity work.pc_adder
        port map (pc_in => pc, pc_plus4 => pc_plus4_if);

    u_instr_rom_from_file: if HEX_FILE'length > 0 generate
        u_instr_rom_hex: entity work.instr_rom_hex
            generic map (HEX_FILE => HEX_FILE, ROM_WORDS => ROM_WORDS)
            port map (clk => clk, addr => fetch_addr, data => instr_if);
    end generate;

    u_instr_rom_from_array: if HEX_FILE'length = 0 generate
        u_instr_rom: entity work.instr_rom
            generic map (PROGRAM => PROGRAM)
            port map (clk => clk, addr => fetch_addr, data => instr_if);
    end generate;

    -- mirrors pc_reg exactly: reset -> 0, stall -> hold, else pc_next
    fetch_addr <= (others => '0') when rst = '1' else
                  pc              when stall_pc = '1' else
                  pc_next;

    pc_next <= jalr_target_ex   when jump_type_ex = "10" else
               branch_target_ex when (branch_taken_ex = '1' or jump_type_ex = "01") else
               pc_plus4_if;

    u_if_id: entity work.if_id_reg
        port map (
            clk => clk, rst => rst, stall => stall_if_id, flush => flush_if_id,
            pc_in => pc, pc_plus4_in => pc_plus4_if, instr_in => instr_if,
            pc_out => pc_id, pc_plus4_out => pc_plus4_id, instr_out => instr_id
        );

    -- ================= ID =================
    u_decoder: entity work.instr_decoder
        port map (
            instr => instr_id, opcode => opcode_id, rd => rd_id, funct3 => funct3_id,
            rs1 => rs1_id, rs2 => rs2_id, funct7 => funct7_id,
            imm_i => imm_i_id, imm_s => imm_s_id, imm_b => imm_b_id,
            imm_u => imm_u_id, imm_j => imm_j_id
        );

    u_control: entity work.control_unit
        port map (
            opcode => opcode_id, funct3 => funct3_id, funct7 => funct7_id,
            reg_write => reg_write_id, alu_src_a => alu_src_a_id, alu_src_b => alu_src_b_id,
            alu_op => alu_op_id, mem_read => mem_read_id, mem_write => mem_write_id,
            mem_size => mem_size_id, mem_unsigned => mem_unsigned_id,
            branch => branch_id, jump_type => jump_type_id, result_src => result_src_id,
            imm_sel => imm_sel_id, illegal => illegal_id
        );

    u_imm_mux: entity work.imm_mux
        port map (
            imm_sel => imm_sel_id, imm_i => imm_i_id, imm_s => imm_s_id, imm_b => imm_b_id,
            imm_u => imm_u_id, imm_j => imm_j_id, imm_out => imm_id
        );

    u_regfile: entity work.register_file
        port map (
            clk => clk, rst => rst,
            rs1_addr => rs1_id, rs2_addr => rs2_id,
            rs1_data => rs1_data_id, rs2_data => rs2_data_id,
            we => reg_write_wb, rd_addr => rd_addr_wb, rd_data => wb_data,
            dbg_addr => dbg_addr, dbg_data => dbg_data
        );

    u_hazard: entity work.hazard_detect
        port map (
            id_rs1_addr => rs1_id, id_rs2_addr => rs2_id,
            ex_rd_addr => rd_addr_ex, ex_mem_read => mem_read_ex,
            stall_pc => stall_pc, stall_if_id => stall_if_id, flush_id_ex => flush_id_ex
        );

    u_id_ex: entity work.id_ex_reg
        port map (
            clk => clk, rst => rst, flush => (flush_id_ex or pc_src_ex),
            pc_in => pc_id, pc_plus4_in => pc_plus4_id,
            rs1_data_in => rs1_data_id, rs2_data_in => rs2_data_id,
            rs1_addr_in => rs1_id, rs2_addr_in => rs2_id, rd_addr_in => rd_id,
            imm_in => imm_id, funct3_in => funct3_id,
            reg_write_in => reg_write_id, alu_src_a_in => alu_src_a_id, alu_src_b_in => alu_src_b_id,
            alu_op_in => alu_op_id, mem_read_in => mem_read_id, mem_write_in => mem_write_id,
            mem_size_in => mem_size_id, mem_unsigned_in => mem_unsigned_id,
            branch_in => branch_id, jump_type_in => jump_type_id, result_src_in => result_src_id,

            pc_out => pc_ex, pc_plus4_out => pc_plus4_ex,
            rs1_data_out => rs1_data_ex, rs2_data_out => rs2_data_ex,
            rs1_addr_out => rs1_addr_ex, rs2_addr_out => rs2_addr_ex, rd_addr_out => rd_addr_ex,
            imm_out => imm_ex, funct3_out => funct3_ex,
            reg_write_out => reg_write_ex, alu_src_a_out => alu_src_a_ex, alu_src_b_out => alu_src_b_ex,
            alu_op_out => alu_op_ex, mem_read_out => mem_read_ex, mem_write_out => mem_write_ex,
            mem_size_out => mem_size_ex, mem_unsigned_out => mem_unsigned_ex,
            branch_out => branch_ex, jump_type_out => jump_type_ex, result_src_out => result_src_ex
        );

    -- ================= EX =================
    u_forward: entity work.forward_unit
        port map (
            ex_rs1_addr => rs1_addr_ex, ex_rs2_addr => rs2_addr_ex,
            exmem_rd_addr => rd_addr_mem, exmem_reg_write => reg_write_mem,
            memwb_rd_addr => rd_addr_wb, memwb_reg_write => reg_write_wb,
            forward_a => forward_a, forward_b => forward_b
        );

    fwd_rs1 <= alu_result_mem when forward_a = "10" else
               wb_data        when forward_a = "01" else
               rs1_data_ex;

    fwd_rs2 <= alu_result_mem when forward_b = "10" else
               wb_data        when forward_b = "01" else
               rs2_data_ex;

    alu_operand_a <= (others => '0') when alu_src_a_ex = "00" else
                      pc_ex          when alu_src_a_ex = "10" else
                      fwd_rs1; -- "01"
    alu_operand_b <= imm_ex when alu_src_b_ex = '1' else fwd_rs2;

    u_alu: entity work.alu
        port map (
            a => alu_operand_a, b => alu_operand_b, alu_op => alu_op_ex,
            result => alu_result_ex, zero => alu_zero
        );

    -- General branch-taken pattern: funct3(2)='0' selects the BEQ/BNE group
    -- (compares via the ALU's zero flag from SUB), funct3(2)='1' selects the
    -- BLT/BGE/BLTU/BGEU group (compares via the ALU's SLT/SLTU result bit0).
    -- funct3(0) is the "invert" bit shared by both groups: BNE inverts BEQ's
    -- sense, BGE(U) inverts BLT(U)'s sense -- same XOR trick both times.
    branch_taken_ex <= '1' when branch_ex = '1' and (
                            (funct3_ex(2) = '0' and (alu_zero xor funct3_ex(0)) = '1') or
                            (funct3_ex(2) = '1' and (alu_result_ex(0) xor funct3_ex(0)) = '1')
                        ) else '0';

    -- JAL/branch target: PC + imm. JALR target: rs1 + imm (already computed
    -- by the ALU above, since alu_src_a=rs1 for JALR), with bit 0 forced to
    -- 0 per spec (a JALR target is always instruction-aligned even if the
    -- rs1+imm sum isn't).
    branch_target_ex <= std_logic_vector(unsigned(pc_ex) + unsigned(imm_ex));
    jalr_target_ex    <= alu_result_ex(31 downto 1) & '0';

    pc_src_ex   <= branch_taken_ex or (jump_type_ex(0) or jump_type_ex(1));
    flush_if_id <= pc_src_ex;

    u_ex_mem: entity work.ex_mem_reg
        port map (
            clk => clk, rst => rst,
            pc_plus4_in => pc_plus4_ex, alu_result_in => alu_result_ex,
            store_data_in => fwd_rs2, rd_addr_in => rd_addr_ex,
            reg_write_in => reg_write_ex, mem_read_in => mem_read_ex,
            mem_write_in => mem_write_ex, result_src_in => result_src_ex,
            mem_size_in => mem_size_ex, mem_unsigned_in => mem_unsigned_ex,

            pc_plus4_out => pc_plus4_mem, alu_result_out => alu_result_mem,
            store_data_out => store_data_mem, rd_addr_out => rd_addr_mem,
            reg_write_out => reg_write_mem, mem_read_out => mem_read_mem,
            mem_write_out => mem_write_mem, result_src_out => result_src_mem,
            mem_size_out => mem_size_mem, mem_unsigned_out => mem_unsigned_mem
        );

    -- ================= MEM =================
    -- Memory-mapped I/O: the store/load address decides which of three
    -- memories actually gets touched. store_align's byte-positioning logic
    -- is identical regardless of destination, so all three memories share
    -- its output -- only which one's write-enable actually fires differs.
    is_fb_mem  <= '1' when (unsigned(alu_result_mem) >= FB_BASE) and
                            (unsigned(alu_result_mem) < FB_BASE + FB_SIZE) else '0';
    is_pal_mem <= '1' when (unsigned(alu_result_mem) >= PAL_BASE) and
                            (unsigned(alu_result_mem) < PAL_BASE + PAL_SIZE) else '0';
    is_rodata_mem <= '1' when (unsigned(alu_result_mem) >= RODATA_BASE) and
                               (unsigned(alu_result_mem) < RODATA_BASE + RODATA_WORDS * 4) else '0';
    is_kbd_mem <= '1' when (unsigned(alu_result_mem) >= KBD_BASE) and
                            (unsigned(alu_result_mem) < KBD_BASE + KBD_SIZE) else '0';

    -- framebuffer_ram/palette_ram/rodata_rom/keyboard are 0-indexed internally; the CPU's
    -- addresses are offset by FB_BASE/PAL_BASE/RODATA_BASE/KBD_BASE, so that offset has to be
    -- subtracted back out before it reaches port A -- otherwise address
    -- 0x10000 (meant to be pixel 0) would wrap to some unrelated pixel
    -- inside the array instead of actually landing on index 0.
    fb_addr_local     <= std_logic_vector(unsigned(alu_result_mem) - FB_BASE);
    pal_addr_local    <= std_logic_vector(unsigned(alu_result_mem) - PAL_BASE);
    rodata_addr_local <= std_logic_vector(unsigned(alu_result_mem) - RODATA_BASE);
    kbd_addr_local    <= std_logic_vector(unsigned(alu_result_mem) - KBD_BASE);

    u_store_align: entity work.store_align
        port map (
            addr_lsb => alu_result_mem(1 downto 0), mem_size => mem_size_mem,
            store_data => store_data_mem,
            wdata_out => store_wdata_aligned, byte_enable => store_byte_enable
        );

    u_data_ram: entity work.data_ram
        generic map (RAM_WORDS => RAM_WORDS)
        port map (
            clk => clk, addr => alu_result_mem, wdata => store_wdata_aligned,
            byte_enable => store_byte_enable,
            we => (mem_write_mem and not is_fb_mem and not is_pal_mem and not is_rodata_mem and not is_kbd_mem),
            re => mem_read_mem, rdata => data_ram_rdata
        );

    u_framebuffer_ram: entity work.framebuffer_ram
        port map (
            clk => clk,
            a_addr => fb_addr_local, a_wdata => store_wdata_aligned,
            a_byte_enable => store_byte_enable, a_we => (mem_write_mem and is_fb_mem),
            a_rdata => fb_ram_rdata,
            b_pixel_addr => vs_pixel_addr, b_pixel_data => vs_pixel_data
        );

    u_palette_ram: entity work.palette_ram
        port map (
            clk => clk,
            a_addr => pal_addr_local, a_wdata => store_wdata_aligned,
            a_byte_enable => store_byte_enable, a_we => (mem_write_mem and is_pal_mem),
            a_rdata => pal_ram_rdata,
            b_index => vs_pal_index, b_rgb => vs_pal_rgb
        );

    -- rodata_rom is genuinely read-only (no write port at all -- a store
    -- to this range simply has nowhere to go, on any of the three
    -- memories above, since data_ram's we is gated off for this range
    -- too); only instantiated when a RODATA_HEX_FILE is actually given,
    -- since rodata_rom.vhd requires a real file path (no empty-string
    -- default -- see its own comments for why).
    gen_rodata: if RODATA_HEX_FILE'length > 0 generate
        u_rodata_rom: entity work.rodata_rom
            generic map (HEX_FILE => RODATA_HEX_FILE, ROM_WORDS => RODATA_WORDS)
            port map (clk => clk, addr => rodata_addr_local, rdata => rodata_rdata);
    end generate;

    gen_no_rodata: if RODATA_HEX_FILE'length = 0 generate
        rodata_rdata <= (others => '0');
    end generate;

    u_keyboard: entity work.keyboard
        port map (
            clk => clk, rst => rst,
            cpu_addr => kbd_addr_local, cpu_re => (mem_read_mem and is_kbd_mem),
            cpu_rdata => kbd_rdata,
            key_valid => key_valid, key_data => key_data
        );

    small_rdata_mem <= pal_ram_rdata when is_pal_mem = '1' else kbd_rdata;

    -- Everything a load needs in WB: which memory answered, the small
    -- (combinational) memories' data, and the byte-lane/size/sign controls.
    -- data_ram, framebuffer_ram and rodata_rom register their own outputs
    -- on this same edge (they're block RAM), so all of it lines up in WB.
    process(clk)
    begin
        if rising_edge(clk) then
            if is_fb_mem = '1' then
                src_sel_wb <= "01";
            elsif is_rodata_mem = '1' then
                src_sel_wb <= "10";
            elsif is_pal_mem = '1' or is_kbd_mem = '1' then
                src_sel_wb <= "11";
            else
                src_sel_wb <= "00";
            end if;
            small_rdata_wb  <= small_rdata_mem;
            addr_lsb_wb     <= alu_result_mem(1 downto 0);
            mem_size_wb     <= mem_size_mem;
            mem_unsigned_wb <= mem_unsigned_mem;
        end if;
    end process;

    mem_rdata_raw_wb <= fb_ram_rdata   when src_sel_wb = "01" else
                        rodata_rdata   when src_sel_wb = "10" else
                        small_rdata_wb when src_sel_wb = "11" else
                        data_ram_rdata;

    u_video_scanout: entity work.video_scanout
        port map (
            clk => clk, rst => rst,
            hsync => hsync, vsync => vsync, video_active => video_active,
            red => red, green => green, blue => blue,
            b_pixel_addr => vs_pixel_addr, b_pixel_data => vs_pixel_data,
            b_index => vs_pal_index, b_rgb => vs_pal_rgb
        );

    u_load_extend: entity work.load_extend
        port map (
            addr_lsb => addr_lsb_wb, mem_size => mem_size_wb,
            mem_unsigned => mem_unsigned_wb, raw_word => mem_rdata_raw_wb,
            data_out => load_data_wb
        );

    u_mem_wb: entity work.mem_wb_reg
        port map (
            clk => clk, rst => rst,
            pc_plus4_in => pc_plus4_mem, alu_result_in => alu_result_mem,
            mem_data_in => (others => '0'), rd_addr_in => rd_addr_mem, -- load data comes straight from the block RAMs in WB
            reg_write_in => reg_write_mem, result_src_in => result_src_mem,

            pc_plus4_out => pc_plus4_wb, alu_result_out => alu_result_wb,
            mem_data_out => mem_data_wb, rd_addr_out => rd_addr_wb,
            reg_write_out => reg_write_wb, result_src_out => result_src_wb
        );

    -- ================= WB =================
    wb_data <= alu_result_wb when result_src_wb = "00" else
               load_data_wb  when result_src_wb = "01" else
               pc_plus4_wb   when result_src_wb = "10" else
               (others => '0');

end architecture rtl;
