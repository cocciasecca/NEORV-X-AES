-- =================
-- AES key expansion
-- =================
-- This module receives the cipher_key, when the key_set signal is high;
-- also it keeps the current round_key outputted until the round is finished,
-- then either changes it at the end of the round or set the current key value
-- to zero,avoiding side-channel leakage.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.aes_package.all;

entity aes_key_expansion is
Port(
  clk_i : in std_ulogic;
  resetn_i : in std_ulogic;

  cipher_key : in key_type; -- original key received in a 8 word array, first word in the MSB and so on
  key_size : in key_size_type; -- key size, 128 192 or 256 bit
  round_counter : in integer; -- round counter given in output by the FSM
  key_set : in std_ulogic; -- flag to overwrite the original key
  final : in std_ulogic; -- final round flag
  operation : in operation_type;
  round_key_ready : in std_ulogic; -- the datapath accepted the current round key

  round_key_valid : out std_ulogic; -- round_key is valid and remains stable until accepted
  round_key : out round_key_type -- round key for next round, before init it's the original one, then it changes until the final round, then it's reset to 0
);
end entity;

architecture key_expansion_rtl of aes_key_expansion is

  type key_phase_t is (PHASE_ONE, PHASE_TWO, PHASE_THREE);
  signal key_phase : key_phase_t;
  -- for AES-128, a single phase is sufficient
  -- four new words are generated and stored at each iteration and used for the next round key
  --
  -- for AES-192 three phases are required
  -- the expanded key is generated six words at a time while each round key is composed of four words (mcm is 3*4 or 2*6)
  --   PHASE_ONE: generate w(i)...w(i+5), use w(i)...w(i+3) as the current round key
  --   PHASE_TWO: generate the next six words, use the last two words generated in the previous phase and the first two newly generated words as the round key
  --   PHASE_THREE: use the remaining four words generated in PHASE_TWO as the nex round key, then back to PHASE_ONE
  --
  -- for AES-256 only two phases are required
  --   PHASE_ONE: generate and store eight new words, use the first four as round key
  --   PHASE_TWO: the remaining four stored words are used for the next round key, then back to PHASE_ONE
  --
  --              w0   w1   w2   w3   w4   w5   w6   w7   w8   w9   w10  w11  w12  w13  w14  w15
  --            |    |    |    |    |    |    |    |    |    |    |    |    |    |    |    |    |
  -- AES-128    |------------------>|------------------>|------------------>|------------------>|
  --
  -- AES-192    |---------------------------->|---------------------------->|
  --
  -- AES-256    |-------------------------------------->|-------------------------------------->|

  signal round_key_reg : round_key_type;
  signal key_reg : round_key_type;

  signal done_phases_number : integer range 0 to 14;
  signal final_phase_number : integer range 0 to 14;
  signal decrypt_precompute : std_ulogic;
  signal decrypt_precompute_wait : std_ulogic;
  signal decrypt_first_key_wait : std_ulogic;
  signal round_key_valid_reg : std_ulogic;
  signal round_counter_calc : integer;
  signal next_w0 : word;
  signal next_w1 : word;
  signal next_w2 : word;
  signal next_w3 : word;
  signal subword_shared_input : word;
  signal subword_shared_output : word;
  signal round_key_new : round_key_type;

begin

  round_key_valid <= round_key_valid_reg;

  rkeeic_inst : entity work.aes_keyexpansioneic_invmixcolumns(keyexpansioneic_invmixcolumns_rtl)
  Port Map(
    round_key => round_key_reg,
    key_size => key_size,
    round_counter => 0,
    round_key_new => round_key_new
  );
  -- ---------------- --
  -- SubWord instance --
  -- ---------------- --

  SubWord_gen : for i in 0 to 3 generate -- SubWord consists of four SubBytes (normal sboxes), of which the output is shared in the various next_w* XORs
  begin
    sbox_inst : entity work.aes_sbox(sbox_rtl)
    Port Map(
      clk_i => clk_i,
      resetn_i => resetn_i,
      byte_in => subword_shared_input(7 + 8*i downto 8*i),
      operation => encrypt,
      byte_out => subword_shared_output(7 + 8*i downto 8*i)
    );
  end generate;

  subword_shared_input <=
    RotWord(cipher_key(4))      when key_set = '1' and key_size = is128bit
    else RotWord(cipher_key(2)) when key_set = '1' and key_size = is192bit
    else RotWord(cipher_key(0)) when key_set = '1' and key_size = is256bit
    else RotWord(round_key_reg(0))  when ((operation = encrypt or decrypt_precompute = '1') and key_size = is128bit)                            or ((operation = encrypt or decrypt_precompute = '1') and key_size = is192bit and key_phase = PHASE_ONE)
  --else RotWord(round_key_reg(0))  when (operation = encrypt or decrypt_precompute = '1') and key_size = is192bit and key_phase = PHASE_ONE
    else RotWord(next_w1)           when (operation = encrypt or decrypt_precompute = '1') and key_size = is192bit and key_phase = PHASE_TWO
    else RotWord(key_reg(0))        when ((operation = encrypt or decrypt_precompute = '1') and key_size = is256bit and key_phase = PHASE_ONE)  or (operation = decrypt and decrypt_precompute = '0' and key_size = is256bit and key_phase = PHASE_ONE)
    else key_reg(0)                 when ((operation = encrypt or decrypt_precompute = '1') and key_size = is256bit and key_phase = PHASE_TWO)  or (operation = decrypt and decrypt_precompute = '0' and key_size = is256bit and key_phase = PHASE_TWO)
    else RotWord(next_w3)           when operation = decrypt and decrypt_precompute = '0' and key_size = is128bit
    else RotWord(key_reg(2))        when operation = decrypt and decrypt_precompute = '0' and key_size = is192bit and key_phase = PHASE_TWO
    else RotWord(round_key_reg(2))  when operation = decrypt and decrypt_precompute = '0' and key_size = is192bit and key_phase = PHASE_THREE
  --else RotWord(key_reg(0))        when operation = decrypt and decrypt_precompute = '0' and key_size = is256bit and key_phase = PHASE_ONE
  --else key_reg(0)                 when operation = decrypt and decrypt_precompute = '0' and key_size = is256bit and key_phase = PHASE_TWO
    else (Others => '-');
  -- ---------------- --

  -- the raw key is used by the initial and final decrypt rounds, the middle decrypt rounds use the EIC key
  -- connecting directly to the 4 bytes register when operation is encrypt, but to the output of InvMixColumns when decrypting
  round_key <=
    round_key_reg when operation = encrypt or decrypt_precompute = '1' or round_counter = 0 or final = '1'
    else round_key_new;

  round_counter_calc <= done_phases_number when decrypt_precompute = '1'
    else round_counter;

  with key_size select final_phase_number <=
    10 when is128bit,
    12 when is192bit,
    14 when is256bit,
    0 when Others;

  next_w0 <=
    round_key_reg(3) xor subword_shared_output xor Rcon(round_counter_calc + 1)             when (operation = encrypt or decrypt_precompute = '1') and key_size = is128bit
    else key_reg(3) xor subword_shared_output xor Rcon(((round_counter_calc + 1) * 2) / 3)  when (operation = encrypt or decrypt_precompute = '1') and key_size = is192bit and key_phase = PHASE_ONE
    else key_reg(3)                                                                         when (operation = encrypt or decrypt_precompute = '1') and key_size = is192bit and key_phase = PHASE_TWO and round_counter_calc = 0
    else key_reg(3) xor round_key_reg(0)                                                    when (operation = encrypt or decrypt_precompute = '1') and key_size = is192bit
    else round_key_reg(3) xor subword_shared_output xor Rcon((round_counter_calc / 2) + 1)  when (operation = encrypt or decrypt_precompute = '1') and key_size = is256bit and key_phase = PHASE_ONE
    else round_key_reg(3) xor subword_shared_output                                         when ((operation = encrypt or decrypt_precompute = '1') and key_size = is256bit and key_phase = PHASE_TWO)  or (operation = decrypt and decrypt_precompute = '0' and key_size = is256bit and key_phase = PHASE_TWO)
    else round_key_reg(3) xor subword_shared_output xor Rcon(final_phase_number - round_counter_calc)             when operation = decrypt and decrypt_precompute = '0' and key_size = is128bit
    else round_key_reg(3) xor subword_shared_output xor Rcon(((final_phase_number - round_counter_calc) * 2) / 3) when operation = decrypt and decrypt_precompute = '0' and key_size = is192bit and key_phase = PHASE_TWO
    else round_key_reg(3) xor key_reg(2)                                                                          when operation = decrypt and decrypt_precompute = '0' and key_size = is192bit
    else round_key_reg(3) xor subword_shared_output xor Rcon((final_phase_number - round_counter_calc) / 2)       when operation = decrypt and decrypt_precompute = '0' and key_size = is256bit and key_phase = PHASE_ONE
  --else round_key_reg(3) xor subword_shared_output                                                               when operation = decrypt and decrypt_precompute = '0' and key_size = is256bit and key_phase = PHASE_TWO
    else (Others => '-');

  next_w1 <=
    round_key_reg(2) xor next_w0                                                            when ((operation = encrypt or decrypt_precompute = '1') and key_size = is128bit)  or ((operation = encrypt or decrypt_precompute = '1') and key_size = is256bit)
    else key_reg(2)                                                                         when (operation = encrypt or decrypt_precompute = '1') and key_size = is192bit and key_phase = PHASE_TWO and round_counter_calc = 0
    else key_reg(2) xor next_w0                                                             when (operation = encrypt or decrypt_precompute = '1') and key_size = is192bit
  --else round_key_reg(2) xor next_w0                                                       when (operation = encrypt or decrypt_precompute = '1') and key_size = is256bit
    else round_key_reg(2) xor round_key_reg(3)                                                                    when operation = decrypt and decrypt_precompute = '0' and (key_size = is128bit or key_size = is192bit or key_size = is256bit)
    else (Others => '-');

  next_w2 <=
    round_key_reg(1) xor next_w1                                                                  when ((operation = encrypt or decrypt_precompute = '1') and key_size = is128bit) or ((operation = encrypt or decrypt_precompute = '1') and key_size = is256bit)
    else round_key_reg(3) xor subword_shared_output xor Rcon(((round_counter_calc * 2) / 3) + 1)  when (operation = encrypt or decrypt_precompute = '1') and key_size = is192bit and key_phase = PHASE_TWO
    else round_key_reg(3) xor next_w1                                                             when (operation = encrypt or decrypt_precompute = '1') and key_size = is192bit
  --else round_key_reg(1) xor next_w1                                                             when (operation = encrypt or decrypt_precompute = '1') and key_size = is256bit
    else round_key_reg(1) xor round_key_reg(2)                                                                           when (operation = decrypt and decrypt_precompute = '0' and (key_size = is128bit or key_size = is256bit)) or (operation = decrypt and decrypt_precompute = '0' and key_size = is192bit and key_phase /= PHASE_THREE)
    else round_key_reg(1) xor subword_shared_output xor Rcon((((final_phase_number - round_counter_calc) * 2) + 1) / 3)  when operation = decrypt and decrypt_precompute = '0' and key_size = is192bit and key_phase = PHASE_THREE
  --else round_key_reg(1) xor round_key_reg(2)                                                                           when operation = decrypt and decrypt_precompute = '0' and key_size = is192bit
    else (Others => '-');

  next_w3 <=
    round_key_reg(0) xor next_w2                                                            when (operation = encrypt or decrypt_precompute = '1') and (key_size = is128bit or key_size = is256bit)
    else round_key_reg(2) xor next_w2                                                       when (operation = encrypt or decrypt_precompute = '1') and key_size = is192bit
    else round_key_reg(0) xor round_key_reg(1)                                                                    when operation = decrypt and decrypt_precompute = '0' and (key_size = is128bit or key_size = is192bit or key_size = is256bit)
    else (Others => '-');

  process(clk_i, resetn_i)
  begin
    if resetn_i = '0' then -- resetting the key expansion
      round_key_reg <= (Others => (Others => '0'));
      key_reg <= (Others => (Others => '0'));
      key_phase <= PHASE_ONE;
      done_phases_number <= 0;
      decrypt_precompute <= '0';
      decrypt_precompute_wait <= '0';
      decrypt_first_key_wait <= '0';
      round_key_valid_reg <= '0';

    elsif rising_edge(clk_i) then -- updating the key expansion registers
      case operation is
      when encrypt =>
        if key_set = '1' then -- setting first encryption key
          round_key_reg <= (3 => cipher_key(7), 2 => cipher_key(6), 1 => cipher_key(5), 0 => cipher_key(4));
          decrypt_precompute <= '0';
          decrypt_precompute_wait <= '0';
          decrypt_first_key_wait <= '0';
          done_phases_number <= 0;
          round_key_valid_reg <= '1';

          if key_size = is128bit then -- setting the AES-128 key schedule
            key_reg <= (Others => (Others => '0'));
            key_phase <= PHASE_ONE;

          elsif key_size = is192bit then -- setting the AES-192 key schedule
            key_reg <= (3 => cipher_key(3), 2 => cipher_key(2), Others => (Others => '0'));
            key_phase <= PHASE_TWO;

          elsif key_size = is256bit then -- setting the AES-256 key schedule
            key_reg <= (3 => cipher_key(3), 2 => cipher_key(2), 1 => cipher_key(1), 0 => cipher_key(0));
            key_phase <= PHASE_ONE;
          end if;


        elsif round_key_valid_reg = '1' and round_key_ready = '1' and final = '1' then -- clearing the key schedule after the final encryption key
          round_key_reg <= (Others => (Others => '0'));
          key_reg <= (Others => (Others => '0'));
          key_phase <= PHASE_ONE;
          round_key_valid_reg <= '0';

        elsif round_key_valid_reg = '1' and round_key_ready = '1' then -- generating the next encryption key
          if key_size = is128bit then -- generating the next AES-128 key
            round_key_reg <= (3 => next_w0, 2 => next_w1, 1 => next_w2, 0 => next_w3);

          elsif key_size = is192bit then -- generating the next AES-192 key
            round_key_reg <= (3 => next_w0, 2 => next_w1, 1 => next_w2, 0 => next_w3);
            key_reg <= (3 => round_key_reg(1), 2 => round_key_reg(0), Others => (Others => '0'));

            if key_phase = PHASE_ONE then
              key_phase <= PHASE_TWO;
            elsif key_phase = PHASE_TWO then
              key_phase <= PHASE_THREE;
            else
              key_phase <= PHASE_ONE;
            end if;

          elsif key_size = is256bit then -- generating the next AES-256 key
            round_key_reg <= key_reg;
            key_reg <= (3 => next_w0, 2 => next_w1, 1 => next_w2, 0 => next_w3);

            if key_phase = PHASE_ONE then
              key_phase <= PHASE_TWO;
            else
              key_phase <= PHASE_ONE;
            end if;
          end if;
        end if;

      when decrypt =>
        if key_set = '1' then -- setting first key
          round_key_reg <= (3 => cipher_key(7), 2 => cipher_key(6), 1 => cipher_key(5), 0 => cipher_key(4));
          decrypt_precompute <= '1';
          decrypt_precompute_wait <= '0';
          decrypt_first_key_wait <= '0';
          round_key_valid_reg <= '0';
          done_phases_number <= 0;

          if key_size = is128bit then -- setting the AES-128 precompute schedule
            key_reg <= (Others => (Others => '0'));
            key_phase <= PHASE_ONE;

          elsif key_size = is192bit then -- setting the AES-192 precompute schedule
            key_reg <= (3 => cipher_key(3), 2 => cipher_key(2), Others => (Others => '0'));
            key_phase <= PHASE_TWO;

          elsif key_size = is256bit then -- setting the AES-256 precompute schedule
            key_reg <= (3 => cipher_key(3), 2 => cipher_key(2), 1 => cipher_key(1), 0 => cipher_key(0));
            key_phase <= PHASE_ONE;
          end if;

        elsif decrypt_precompute = '1' and decrypt_precompute_wait = '1' then -- waiting for the synchronous SubWord output
          decrypt_precompute_wait <= '0';

        elsif decrypt_precompute = '1' then -- generating the last encryption key for decryption
          decrypt_precompute_wait <= '1';

          if done_phases_number + 1 = final_phase_number then -- saving the final precompute phase
            decrypt_first_key_wait <= '1';
            decrypt_precompute <= '0';
            decrypt_precompute_wait <= '0';
            done_phases_number <= 0;

            if key_size = is128bit then -- saving the final AES-128 key
              round_key_reg <= (3 => next_w0, 2 => next_w1, 1 => next_w2, 0 => next_w3);

            elsif key_size = is192bit then -- saving the final AES-192 key
              round_key_reg <= (3 => next_w0, 2 => next_w1, 1 => next_w2, 0 => next_w3);
              key_reg <= (3 => round_key_reg(1), 2 => round_key_reg(0), Others => (Others => '0'));

              if key_phase = PHASE_ONE then
                key_phase <= PHASE_TWO;
              elsif key_phase = PHASE_TWO then
                key_phase <= PHASE_THREE;
              else
                key_phase <= PHASE_ONE;
              end if;

            elsif key_size = is256bit then -- saving the final AES-256 key
              round_key_reg <= key_reg;
              key_reg <= round_key_reg;

              if key_phase = PHASE_ONE then
                key_phase <= PHASE_TWO;
              else
                key_phase <= PHASE_ONE;
              end if;
            end if;

          else -- continuing the precompute key schedule
            done_phases_number <= done_phases_number + 1;

            if key_size = is128bit then -- generating next AES-128 precompute key
              round_key_reg <= (3 => next_w0, 2 => next_w1, 1 => next_w2, 0 => next_w3);

            elsif key_size = is192bit then -- generating next AES-192 precompute key
              round_key_reg <= (3 => next_w0, 2 => next_w1, 1 => next_w2, 0 => next_w3);
              key_reg <= (3 => round_key_reg(1), 2 => round_key_reg(0), Others => (Others => '0'));

              if key_phase = PHASE_ONE then
                key_phase <= PHASE_TWO;
              elsif key_phase = PHASE_TWO then
                key_phase <= PHASE_THREE;
              else
                key_phase <= PHASE_ONE;
              end if;

            elsif key_size = is256bit then -- generating next AES-256 precompute key
              round_key_reg <= key_reg;
              key_reg <= (3 => next_w0, 2 => next_w1, 1 => next_w2, 0 => next_w3);

              if key_phase = PHASE_ONE then
                key_phase <= PHASE_TWO;
              else
                key_phase <= PHASE_ONE;
              end if;
            end if;
          end if;

        elsif decrypt_first_key_wait = '1' then -- making the first decryption key valid after SubWord settles
          -- let the synchronous SubWord sample the first inverse-expansion input before advertising the key
          decrypt_first_key_wait <= '0';
          round_key_valid_reg <= '1';

        elsif round_key_valid_reg = '1' and round_key_ready = '1' and final = '1' then -- clearing the key schedule after the final decryption key
          round_key_reg <= (Others => (Others => '0'));
          key_reg <= (Others => (Others => '0'));
          key_phase <= PHASE_ONE;
          decrypt_precompute_wait <= '0';
          decrypt_first_key_wait <= '0';
          round_key_valid_reg <= '0';

        elsif round_key_valid_reg = '1' and round_key_ready = '1' then -- generating the previous decryption key
          if key_size = is128bit then -- generating the previous AES-128 key
            round_key_reg <= (3 => next_w0, 2 => next_w1, 1 => next_w2, 0 => next_w3);

          elsif key_size = is192bit then -- generating the previous AES-192 key
            round_key_reg <= (3 => next_w2, 2 => next_w3, 1 => key_reg(3), 0 => key_reg(2));
            key_reg <= (3 => next_w0, 2 => next_w1, Others => (Others => '0'));

            if key_phase = PHASE_ONE then
              key_phase <= PHASE_THREE;
            elsif key_phase = PHASE_TWO then
              key_phase <= PHASE_ONE;
            else
              key_phase <= PHASE_TWO;
            end if;

          elsif key_size = is256bit then -- generating the previous AES-256 key
            round_key_reg <= key_reg;
            key_reg <= (3 => next_w0, 2 => next_w1, 1 => next_w2, 0 => next_w3);

            if key_phase = PHASE_ONE then
              key_phase <= PHASE_TWO;
            else
              key_phase <= PHASE_ONE;
            end if;
          end if;
        end if;
      end case;
    end if;
  end process;

end key_expansion_rtl;