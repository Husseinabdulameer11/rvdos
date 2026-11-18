library ieee;
use ieee.std_logic_1164.all;

-- Computes the byte-lane write mask and repositions the value being
-- stored, since RV32I allows SB/SH at any address (not just word-aligned)
-- but the underlying RAM is a 32-bit-wide word array. Misaligned SH (odd
-- address) is not checked/trapped here -- a real core would raise a
-- misaligned-address exception; this one just does the wrong thing
-- silently, a known gap.

entity store_align is
    port (
        addr_lsb    : in  std_logic_vector(1 downto 0); -- address(1:0)
        mem_size    : in  std_logic_vector(1 downto 0);  -- 00=byte 01=half 10=word
        store_data  : in  std_logic_vector(31 downto 0); -- raw register value
        wdata_out   : out std_logic_vector(31 downto 0); -- repositioned into the right lane(s)
        byte_enable : out std_logic_vector(3 downto 0)
    );
end entity store_align;

architecture rtl of store_align is
begin
    process(addr_lsb, mem_size, store_data)
    begin
        case mem_size is
            when "00" => -- byte
                case addr_lsb is
                    when "00" =>
                        byte_enable <= "0001";
                        wdata_out   <= x"000000" & store_data(7 downto 0);
                    when "01" =>
                        byte_enable <= "0010";
                        wdata_out   <= x"0000" & store_data(7 downto 0) & x"00";
                    when "10" =>
                        byte_enable <= "0100";
                        wdata_out   <= x"00" & store_data(7 downto 0) & x"0000";
                    when others =>
                        byte_enable <= "1000";
                        wdata_out   <= store_data(7 downto 0) & x"000000";
                end case;

            when "01" => -- halfword
                if addr_lsb(1) = '0' then
                    byte_enable <= "0011";
                    wdata_out   <= x"0000" & store_data(15 downto 0);
                else
                    byte_enable <= "1100";
                    wdata_out   <= store_data(15 downto 0) & x"0000";
                end if;

            when others => -- word
                byte_enable <= "1111";
                wdata_out   <= store_data;
        end case;
    end process;
end architecture rtl;
