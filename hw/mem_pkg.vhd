library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package mem_pkg is
    type word_array is array (natural range <>) of std_logic_vector(31 downto 0);
    -- byte memories; shared here so a testbench can name memory contents
    -- with a VHDL-2008 external name
    type byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

    -- Reads a bin2hex/rvasm hex file (one 32-bit word per line, 8 hex
    -- digits) into an n-word array, zero-filling the rest. Blank lines are
    -- skipped; a trailing CR (Windows line endings) is ignored.
    impure function load_hex(file_name : string; n : integer) return word_array;

    -- number of address bits needed for n words
    function addr_bits(n : integer) return integer;
end package mem_pkg;

package body mem_pkg is

    impure function load_hex(file_name : string; n : integer) return word_array is
        file f : text open read_mode is file_name;
        variable l : line;
        variable v : std_logic_vector(31 downto 0);
        variable good : boolean;
        variable result : word_array(0 to n - 1) := (others => (others => '0'));
        variable i : integer := 0;
    begin
        -- one hread per line: Vivado caps the total iterations of each
        -- loop during elaboration at 65536, so no per-character loop here
        while not endfile(f) and i < n loop
            readline(f, l);
            hread(l, v, good);
            if good then
                result(i) := v;
                i := i + 1;
            end if;
        end loop;
        return result;
    end function;

    function addr_bits(n : integer) return integer is
        variable b : integer := 0;
    begin
        while 2 ** b < n loop
            b := b + 1;
        end loop;
        return b;
    end function;

end package body mem_pkg;
