-- =================== --
--   AES control FSM   --
-- =================== --
-- This module includes a FSM that counts the actual round number. Also it outputs a initial flag, when the state_i is going through the first round and a final flag for when it's going through the 10th round, if the key is 128 bit, 12 if 192, 14 if 256. Finally, a done flag is raised when the accelerator is processing and when the result's ready.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.aes_package.all;

entity aes_control_fsm is
  Port(
    clk_i : in  std_ulogic;
    resetn_i : in  std_ulogic;

    start : in  std_ulogic; -- start cypher process
    end_round : in std_ulogic; -- the datapath just finished a round's processing
    key_size : in key_size_type; -- indicates how many rounds the AES has to go through (10, 12, 14)

    round_counter : out integer; -- number indicating current round

    initial : out std_ulogic; -- doing initial AddRoundKey / loading state_i
    final : out std_ulogic; -- indicates final round is processing
    done : out std_ulogic -- valid result
  );
end entity;

architecture control_fsm_rtl of aes_control_fsm is
  type state_type is (AES_IDLE, AES_INITIAL, AES_ROUND, AES_FINAL);
  signal state : state_type;
  signal round_counter_reg : integer range 0 to 14;
  signal round_number : integer range 0 to 14;

begin

  -- selecting correct number of round iterations
  with key_size select round_number <=
    10 when is128bit,
    12 when is192bit,
    14 when is256bit,
    0 when Others;

  -- handling output flags
  initial <= '1' when state = AES_INITIAL
    else '0';
  final <= '1' when state = AES_FINAL
    else '0';

  -- synchronous process, asynchronous reset
  process(clk_i, resetn_i)
  begin
    if resetn_i = '0' then
      state <= AES_IDLE;
      -- resetting all non combinatory outputs
      round_counter_reg <= 0;
      done <= '0'; -- async reset, in case done was high, it won't remain high until the next rising edge, causing a bug

    elsif rising_edge(clk_i) then
      -- default output flags
      done <= '0';
      -- actual FSM
      case state is
        when AES_IDLE =>
          if start = '1' then
            state <= AES_INITIAL;
          end if;

        when AES_INITIAL => -- initial step of aes-ing go
          if end_round = '1' then
            round_counter_reg <= 1;
            state <= AES_ROUND;
          end if;
        
        when AES_ROUND => -- change state
          if end_round = '1' then
            if round_number = 0 then
              round_counter_reg <= 0;
              state <= AES_IDLE;
            elsif round_counter_reg = round_number - 1 then
              state <= AES_FINAL;
              round_counter_reg <= round_counter_reg + 1;
            else
              round_counter_reg <= round_counter_reg + 1;
            end if;
          end if;
        
        when AES_FINAL => -- final step
          if end_round = '1' then -- the final result was accepted
            round_counter_reg <= 0;
            state <= AES_IDLE;
            done <= '1';
          end if;
          
      end case;
    end if;
  end process;

round_counter <= round_counter_reg;

end control_fsm_rtl;