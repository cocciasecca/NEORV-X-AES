-- ========================================================= --
-- AES key expansion submodule - Equivalent Inverse Cipher   --
-- ========================================================= --
-- This submodule calculates the previous round key by receiving in input...

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.aes_package.all;

entity aes_keyexpansioneic_invmixcolumns is
  Port(
    round_key     : in round_key_type;
    key_size      : in key_size_type;
    round_counter : in integer;
    round_key_new : out round_key_type
  );
end entity;

architecture keyexpansioneic_invmixcolumns_rtl of aes_keyexpansioneic_invmixcolumns is
  signal result : round_key_type;

begin
  
  InvMixColRoundKey_gen : for i in round_key'RANGE generate
    result(i) <=
      (mul14(round_key(i)(31 downto 24)) xor mul11(round_key(i)(23 downto 16)) xor mul13(round_key(i)(15 downto 8)) xor mul9(round_key(i)(7 downto 0))) &
      (mul9(round_key(i)(31 downto 24)) xor mul14(round_key(i)(23 downto 16)) xor mul11(round_key(i)(15 downto 8)) xor mul13(round_key(i)(7 downto 0))) &
      (mul13(round_key(i)(31 downto 24)) xor mul9(round_key(i)(23 downto 16)) xor mul14(round_key(i)(15 downto 8)) xor mul11(round_key(i)(7 downto 0))) &
      (mul11(round_key(i)(31 downto 24)) xor mul13(round_key(i)(23 downto 16)) xor mul9(round_key(i)(15 downto 8)) xor mul14(round_key(i)(7 downto 0)));
  end generate;

  round_key_new <= round_key when (key_size = is128bit and round_counter = 9) or (key_size = is192bit and round_counter = 11) or (key_size = is256bit and round_counter = 13) or (key_size = invalid)
    else result;
    
end keyexpansioneic_invmixcolumns_rtl;