-- ============ --
--   AES core   --
-- ============ --
-- The core includes an instance of all the submodules, connects them toghether.
-- It only has a process that saves the current state_o in state_i for the next round or gives it in output when the operations are done.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.aes_package.all;

entity aes_core is
Port(
  clk_i : in std_ulogic;
  resetn_i : in std_ulogic;

  start : in std_ulogic; -- start conversion signal
  clear_output : in std_ulogic; -- flag used to clear output when it's no longer needed
  key_size : in key_size_type; -- indicates key size in bits: 128, 192, 256
  operation : in operation_type; -- encrypt or decrypt

  cipher_key : in key_type;
  state_i : in text_type;

  state_o : out text_type;
  done : out std_ulogic -- aes is done signal
);
end entity;

architecture core_rtl of aes_core is
  signal state_i_reg : text_type;
  signal round_key_sig : round_key_type;
  signal round_counter_sig : integer;
  signal initial_sig : std_ulogic;
  signal final_sig : std_ulogic;
  signal done_sig : std_ulogic;
  signal end_round_sig : std_ulogic;
  signal round_start_sig : std_ulogic;
  signal datapath_ready_sig : std_ulogic;
  signal round_key_valid_sig : std_ulogic;
  signal round_key_ready_sig : std_ulogic;
  signal state_o_valid_sig : std_ulogic;
  signal state_o_ready_sig : std_ulogic;
  signal state_available : std_ulogic; -- state_i_reg contains a state ready for the next round
  signal state_o_sig : text_type; -- connected to datapath output
  signal state_o_reg : text_type; -- registered final output state
  signal output_valid : std_ulogic;

begin

  state_o <= state_o_reg;
  done <= done_sig;

  -- simple LID implementation
  round_start_sig <= state_available and round_key_valid_sig; 
  round_key_ready_sig <= state_available and datapath_ready_sig; -- the datapath can accept the current round key
  state_o_ready_sig <= '1' when final_sig = '0' else not output_valid; 
  end_round_sig <= state_o_valid_sig and state_o_ready_sig;

  datapath_inst : entity work.aes_datapath(datapath_rtl)
  Port Map(
    clk_i       => clk_i,
    resetn_i    => resetn_i,
    state_i     => state_i_reg,
    round_key   => round_key_sig,
    round_start => round_start_sig,
    datapath_ready => datapath_ready_sig,
    operation   => operation,
    initial     => initial_sig,
    final       => final_sig,
    state_o_valid => state_o_valid_sig,
    state_o_ready => state_o_ready_sig,
    state_o     => state_o_sig
  );

  control_fsm_inst : entity work.aes_control_fsm(control_fsm_rtl)
  Port Map(
    clk_i         => clk_i,
    resetn_i      => resetn_i,
    start         => start,
    end_round     => end_round_sig,
    key_size      => key_size,
    round_counter => round_counter_sig,
    initial       => initial_sig,
    final         => final_sig,
    done          => done_sig
  );

  key_expansion_inst : entity work.aes_key_expansion(key_expansion_rtl)
  Port Map(
    clk_i         => clk_i,
    resetn_i      => resetn_i,
    cipher_key    => cipher_key,
    key_size      => key_size,
    round_counter => round_counter_sig,
    key_set       => start, -- key expansion starts working right away
    final         => final_sig,
    operation     => operation,
    round_key_valid => round_key_valid_sig,
    round_key_ready => round_key_ready_sig,
    round_key     => round_key_sig
  );

  process(clk_i, resetn_i)
  begin
    if resetn_i = '0' then
      state_i_reg <= (Others => (Others => '0'));
      state_o_reg <= (Others => (Others => '0'));
      state_available <= '0';
      output_valid <= '0';

    elsif rising_edge(clk_i) then
      if clear_output = '1' then
        state_o_reg <= (Others => (Others => '0'));
        output_valid <= '0';
      end if;

      if start = '1' then
        state_i_reg <= state_i;
        state_o_reg <= (Others => (Others => '0'));
        state_available <= '1';
        output_valid <= '0';

      elsif round_start_sig = '1' and datapath_ready_sig = '1' then
        state_available <= '0';

      elsif end_round_sig = '1' then
        if final_sig = '1' then
          state_i_reg <= (Others => (Others => '0'));
          state_o_reg <= state_o_sig;
          output_valid <= '1'; -- core's output is finally valid
        else
          state_i_reg <= state_o_sig;
          state_available <= '1';
        end if;
      end if;
    end if;
  end process;

end core_rtl;