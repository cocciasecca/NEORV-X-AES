-- =============== --
--   AES package   --
-- =============== --
-- The package contains all useful components and functions

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package aes_package is
  -- Constants definitions
  constant BLOCK_LENGTH : integer := 128;
  constant KEY_MAX_LENGTH : integer := 256;
  constant KEY_LENGTH_128 : integer := 128;

  -- Types and subtypes definitions
  subtype byte is std_ulogic_vector(7 downto 0);
  subtype word is std_ulogic_vector(31 downto 0);
  type key_size_type is (invalid, is128bit, is192bit, is256bit);
  type key_type is array (7 downto 0) of word;
  type round_key_type is array (3 downto 0) of word;
  type text_type is array (3 downto 0) of word;
  type operation_type is (encrypt, decrypt);

  -- Functions declarations
  function mul2(a : byte) return byte;
  function mul3(a : byte) return byte;
  function mul9(a : byte) return byte;
  function mul11(a : byte) return byte;
  function mul13(a : byte) return byte;
  function mul14(a : byte) return byte;
  function RotWord(a : word) return word;
  function Rcon(i : integer) return word;
end package aes_package;

package body aes_package is
  
  -- Functions definitions

  function mul2(a : byte) return byte is -- normal multiplication by 2 in Galois Field(2^8), equivalent to a simple xor, or to a left shift and xor with x"1B" if overflow occurs
  begin
    if a(7) = '1' then
      return (a(6 downto 0) & '0') xor x"1B";
    else
      return (a(6 downto 0) & '0');
    end if;
  end function;

  function mul3(a : byte) return byte is -- multiplication by 3 in GF(2^8), equivalent to mul2(a) xor a
  begin
    return mul2(a) xor a;
  end function;
  
  function mul4(a : byte) return byte is -- multiplication by 4 in GF(2^8), equivalent to mul2(mul2(a))
  begin
    return mul2(mul2(a));
  end function;

  function mul8(a : byte) return byte is -- multiplication by 8 in GF(2^8), equivalent to mul2(mul4(a))
  begin
    return mul2(mul4(a));
  end function;

  function mul9(a : byte) return byte is -- multiplication by 9 in GF(2^8), equivalent to 8*a xor a
  begin
    return mul8(a) xor a;
  end function;

  function mul11(a : byte) return byte is -- multiplication by 11 in GF(2^8), equivalent to 8*a xor 2*a xor a
  begin
    return mul8(a) xor mul2(a) xor a;
  end function;

  function mul13(a : byte) return byte is -- multiplication by 13 in GF(2^8), equivalent to 8*a xor 4*a xor a
  begin
    return mul8(a) xor mul4(a) xor a;
  end function;

  function mul14(a : byte) return byte is -- multiplication by 14 in GF(2^8), equivalent to 8*a xor 4*a xor 2*a
  begin
    return mul8(a) xor mul4(a) xor mul2(a);
  end function;

  function RotWord(a : word) return word is -- rotates a 4 byte (32 bit) word by one byte to the left
  begin
    return a(23 downto 0) & a(31 downto 24);
  end function;

function Rcon(i : integer) return word is -- returns the round constant used to generate the next round key
begin
  case i is
    when 1  => return b"00000001000000000000000000000000"; -- [01,00,00,00]
    when 2  => return b"00000010000000000000000000000000"; -- [02,00,00,00]
    when 3  => return b"00000100000000000000000000000000"; -- [04,00,00,00]
    when 4  => return b"00001000000000000000000000000000"; -- [08,00,00,00]
    when 5  => return b"00010000000000000000000000000000"; -- [10,00,00,00]
    when 6  => return b"00100000000000000000000000000000"; -- [20,00,00,00]
    when 7  => return b"01000000000000000000000000000000"; -- [40,00,00,00]
    when 8  => return b"10000000000000000000000000000000"; -- [80,00,00,00]
    when 9  => return b"00011011000000000000000000000000"; -- [1b,00,00,00]
    when 10 => return b"00110110000000000000000000000000"; -- [36,00,00,00]
    when Others => return b"00000000000000000000000000000000";
  end case;
end function;
  
end package body aes_package;