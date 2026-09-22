-- ============================================================= --
--   AES datapath: SubBytes, ShiftRow, MixColumns, AddRoundKey   --
-- ============================================================= --

-- This module operates on the state given in input, based on the round number, and gives in output the processed state when the round is over, also rising a flag useful to other core components.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.aes_package.all;

entity aes_datapath is
  Port(
    clk_i : in std_ulogic;
    resetn_i : in std_ulogic;

    state_i : in text_type; -- text given in input to the datapath
    round_key : in round_key_type; -- it's this round's key

    round_start : in std_ulogic;
    operation : in operation_type;
    initial : in std_ulogic;
    final : in std_ulogic; -- when high (10th round), the text doesn't go through MixColumns
    state_o_ready : in std_ulogic; -- the core can accept state_o

    datapath_ready : out std_ulogic; -- the datapath can accept a new round
    state_o_valid : out std_ulogic; -- state_o contains a completed round
    state_o : out text_type -- text given in output from the datapath
  );
end entity;

architecture datapath_rtl of aes_datapath is
  -- describing the AES matrix
  constant MATRIX_N : integer := 4;
  type type_matrix is array (0 to MATRIX_N - 1, 0 to MATRIX_N - 1) of byte;
  type type_halfmatrix is array (0 to 1, 0 to MATRIX_N - 1) of byte;
  type processing_clock_cycle_type is (FIRST, SECOND);

  signal matrix_i : type_matrix;
  signal matrix_substituted : type_matrix;
  signal sbox_input : type_halfmatrix;
  signal sbox_output : type_halfmatrix;
  signal matrix_substituted_reg : type_halfmatrix; -- register necessary for increasing the operating frequency

  signal matrix_shifted : type_matrix;
  signal matrix_mixed : type_matrix;

  signal processing_clock_cycle : processing_clock_cycle_type;
  signal datapath_active : std_ulogic;
  signal operation_reg : operation_type;
  signal final_reg : std_ulogic;
  signal state_i_round_reg : text_type;
  signal round_key_reg : round_key_type;
  signal sbox_operation : operation_type;
  signal state_o_valid_reg : std_ulogic;
  signal state_o_reg : text_type;
  signal state_o_temp : text_type; -- completed non-initial round

begin

  sbox_operation <= operation when datapath_active = '0' else operation_reg;

  -- -------------------- --
  --   vector to matrix   --
  -- -------------------- --
  matrix_row : for r in 0 to MATRIX_N-1 generate
    matrix_col : for c in 0 to MATRIX_N-1 generate
    begin
      matrix_i(r, c) <= state_i_round_reg(3-c)(31 - 8*r downto 24 - 8*r);
    end generate;
  end generate;

  -- ------------ --
  --   SubBytes   --
  -- ------------ --
  -- only eight matrix elements at a time are processed so that the accelerator fully uses the two clock cycles per round
  -- also instancing two subwords occupies half of the area
  SubBytes_row0 : for r in 0 to (MATRIX_N/2)-1 generate
    SubBytes_col0 : for c in 0 to MATRIX_N-1 generate
    begin
      sbox_inst : entity work.aes_sbox(sbox_rtl)
      Port Map(
        clk_i => clk_i,
        resetn_i => resetn_i,
        byte_in => sbox_input(r, c),
        operation => sbox_operation, -- operation is sampled with the round
        byte_out => sbox_output(r, c)
      );
      -- on the first rising edge after round_start the first half is sampled directly, the second half follows one cycle later
      sbox_input(r, c) <=
        state_i(3-c)(31 - 8*r downto 24 - 8*r) when datapath_active = '0' and round_start = '1' and initial = '0' -- equivalent to the matrix_i(r, c)
        else matrix_i(r + 2, c) when datapath_active = '1' and processing_clock_cycle = SECOND
        else matrix_i(r, c);
    end generate;
  end generate;

  SubBytes_first_half_row : for r in 0 to (MATRIX_N/2)-1 generate
    SubBytes_first_half_col : for c in 0 to MATRIX_N-1 generate
    begin
      matrix_substituted(r, c) <= matrix_substituted_reg(r, c);
    end generate;
  end generate;

  SubBytes_second_half_row : for r in MATRIX_N/2 to MATRIX_N-1 generate
    SubBytes_second_half_col : for c in 0 to MATRIX_N - 1 generate
    begin
      matrix_substituted(r, c) <= sbox_output(r - 2, c);
    end generate;
  end generate;

  -- ------------ --
  --   ShiftRow   --
  -- ------------ --
  ShiftRow_row : for r in 0 to MATRIX_N-1 generate
    ShiftRow_col : for c in 0 to MATRIX_N-1 generate
    begin
      matrix_shifted(r, c) <=
        matrix_substituted(r, (c + r) mod 4) when operation_reg = encrypt
        else
        matrix_substituted(r, (c - r) mod 4) when operation_reg = decrypt
        else
        (Others => '-');
    end generate;
  end generate;

  -- -------------- --
  --   MixColumns   --
  -- -------------- --
  MixColumns_row : for r in 0 to MATRIX_N-1 generate
    MixColumns_col : for c in 0 to MATRIX_N-1 generate
    begin
      matrix_mixed(r, c) <=
        mul2(matrix_shifted(r, c)) xor
        mul3(matrix_shifted((r+1) mod 4, c)) xor
        matrix_shifted((r+2) mod 4, c) xor
        matrix_shifted((r+3) mod 4, c) when final_reg = '0' and operation_reg = encrypt
        else
        mul14(matrix_shifted(r, c)) xor
        mul11(matrix_shifted((r+1) mod 4, c)) xor
        mul13(matrix_shifted((r+2) mod 4, c)) xor
        mul9(matrix_shifted((r+3) mod 4, c)) when final_reg = '0' and operation_reg = decrypt
        else
        (Others => '-');
    end generate;
  end generate;

  -- ---------------------------------- --
  --   AddRoundKey & matrix to vector   --
  -- ---------------------------------- --
  -- if the round number is one, then the state only goes through AddRoundKey, if it's the last one it doesn't go through MixColumns
  state_o_row : for r in 0 to MATRIX_N-1 generate
    state_o_col : for c in 0 to MATRIX_N-1 generate
    begin
      state_o_temp(3-c)(31 - 8*r downto 24 - 8*r) <=
        matrix_shifted(r, c) xor round_key_reg(3-c)(31 - 8*r downto 24 - 8*r) when final_reg = '1' else
        matrix_mixed(r, c) xor round_key_reg(3-c)(31 - 8*r downto 24 - 8*r);
    end generate;
  end generate;

  -- state_o and its valid flag remain stable until the core accepts them
  datapath_ready <= not datapath_active and not state_o_valid_reg;
  state_o_valid <= state_o_valid_reg;
  state_o <= state_o_reg;

  process(clk_i, resetn_i)
  begin
    if resetn_i = '0' then
      processing_clock_cycle <= FIRST;
      datapath_active <= '0';
      operation_reg <= encrypt;
      final_reg <= '0';
      state_i_round_reg <= (Others => (Others => '0'));
      round_key_reg <= (Others => (Others => '0'));
      state_o_valid_reg <= '0';
      state_o_reg <= (Others => (Others => '0'));
      matrix_substituted_reg <= (Others => (Others => (Others => '0')));

    elsif rising_edge(clk_i) then
      if state_o_valid_reg = '1' then
        if state_o_ready = '1' then
          state_o_valid_reg <= '0';
          state_o_reg <= (Others => (Others => '0'));
          state_i_round_reg <= (Others => (Others => '0'));
          round_key_reg <= (Others => (Others => '0'));
          matrix_substituted_reg <= (Others => (Others => (Others => '0')));
        end if;

      elsif datapath_active = '0' then
        if round_start = '1' then
          state_i_round_reg <= state_i;
          round_key_reg <= round_key;
          operation_reg <= operation;
          final_reg <= final;

          if initial = '1' then
            state_o_reg <= (3 => state_i(3) xor round_key(3), 2 => state_i(2) xor round_key(2), 1 => state_i(1) xor round_key(1), 0 => state_i(0) xor round_key(0));
            state_o_valid_reg <= '1';
            processing_clock_cycle <= FIRST;
          else
            datapath_active <= '1';
            processing_clock_cycle <= SECOND;
          end if;
        end if;

      elsif processing_clock_cycle = SECOND then
        -- the first half is read before this edge while the ROMs sample the second half
        matrix_substituted_reg <= sbox_output;
        processing_clock_cycle <= FIRST;

      else
        -- the registered first half and the current second half now form a complete state
        state_o_reg <= state_o_temp;
        state_o_valid_reg <= '1';
        datapath_active <= '0';
        processing_clock_cycle <= FIRST;
      end if;
    end if;
  end process;

end datapath_rtl;