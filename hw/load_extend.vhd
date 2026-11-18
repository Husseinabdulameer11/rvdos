library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity load_extend is
    port (
        addr_lsb     : in  std_logic_vector(1 downto 0); -- address(1:0)
        mem_size     : in  std_logic_vector(1 downto 0);  -- 00=byte 01=half 10=word
        mem_unsigned : in  std_logic;                     -- 1=zero-extend (LBU/LHU)
        raw_word     : in  std_logic_vector(31 downto 0); -- full word read from RAM
        data_out     : out std_logic_vector(31 downto 0)
    );
end entity load_extend;

architecture rtl of load_extend is
    signal sel_byte : std_logic_vector(7 downto 0);
    signal sel_half : std_logic_vector(15 downto 0);
begin

    -- pick out the addressed byte/halfword from the word the RAM returned
    process(addr_lsb, raw_word)
    begin
        case addr_lsb is
            when "00"   => sel_byte <= raw_word(7 downto 0);
            when "01"   => sel_byte <= raw_word(15 downto 8);
            when "10"   => sel_byte <= raw_word(23 downto 16);
            when others => sel_byte <= raw_word(31 downto 24);
        end case;
    end process;

    sel_half <= raw_word(15 downto 0) when addr_lsb(1) = '0' else raw_word(31 downto 16);

    process(mem_size, mem_unsigned, sel_byte, sel_half, raw_word)
    begin
        case mem_size is
            when "00" => -- byte
                if mem_unsigned = '1' then
                    data_out <= x"000000" & sel_byte;
                else
                    data_out <= std_logic_vector(resize(signed(sel_byte), 32));
                end if;

            when "01" => -- halfword
                if mem_unsigned = '1' then
                    data_out <= x"0000" & sel_half;
                else
                    data_out <= std_logic_vector(resize(signed(sel_half), 32));
                end if;

            when others => -- word
                data_out <= raw_word;
        end case;
    end process;

end architecture rtl;
