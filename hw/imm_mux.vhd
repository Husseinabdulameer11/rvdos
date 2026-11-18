library ieee;
use ieee.std_logic_1164.all;

entity imm_mux is
    port (
        imm_sel : in  std_logic_vector(2 downto 0); -- 000=I 001=S 010=B 011=U 100=J
        imm_i   : in  std_logic_vector(31 downto 0);
        imm_s   : in  std_logic_vector(31 downto 0);
        imm_b   : in  std_logic_vector(31 downto 0);
        imm_u   : in  std_logic_vector(31 downto 0);
        imm_j   : in  std_logic_vector(31 downto 0);
        imm_out : out std_logic_vector(31 downto 0)
    );
end entity imm_mux;

architecture rtl of imm_mux is
begin
    process(imm_sel, imm_i, imm_s, imm_b, imm_u, imm_j)
    begin
        case imm_sel is
            when "000"  => imm_out <= imm_i;
            when "001"  => imm_out <= imm_s;
            when "010"  => imm_out <= imm_b;
            when "011"  => imm_out <= imm_u;
            when "100"  => imm_out <= imm_j;
            when others => imm_out <= (others => '0');
        end case;
    end process;
end architecture rtl;
