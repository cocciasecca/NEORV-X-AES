-- =================================================== --
--     NEORV32 CFS x AES accelerator     --
-- =================================================== --
-- Register map, word addresses:
-- (all registers are 32-bit words, but the CPU still considers them as bytes, so every REG[n] is located at CFS base address + 4*n
--
--   REG[0]   input state word 0      bits 127 downto 96
--   REG[1]   input state word 1      bits 95 downto 64
--   REG[2]   input state word 2      bits 63 downto 32
--   REG[3]   input state word 3      bits 31 downto 0
--
--   REG[4]   key word 0              bits 255 downto 224
--   REG[5]   key word 1              bits 223 downto 192
--   REG[6]   key word 2              bits 191 downto 160
--   REG[7]   key word 3              bits 159 downto 128
--   REG[8]   key word 4              bits 127 downto 96
--   REG[9]   key word 5              bits 95 downto 64
--   REG[10]  key word 6              bits 63 downto 32
--   REG[11]  key word 7              bits 31 downto 0
--
--   REG[12]  output state word 0     bits 127 downto 96
--   REG[13]  output state word 1     bits 95 downto 64
--   REG[14]  output state word 2     bits 63 downto 32
--   REG[15]  output state word 3     bits 31 downto 0
--
--   REG[16]  control, write-only:
--              bit 0 = START pulse
--              bit 1 = IRQ_ACK pulse
--              bits 3 downto 2 = key mode: 01 AES-128, 10 AES-192,
--                                11 AES-256, 00 invalid
--              bit 4 = operation: 0 encrypt, 1 decrypt
--
--   REG[17]  status, read-only:
--              bit 0 = DONE, latched until IRQ_ACK
--              bit 1 = BUSY

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

library work;
use work.aes_package.all;


entity neorv32_cfs is
  Port(
    -- Global clock and reset.
    clk_i     : in  std_ulogic;
    rstn_i    : in  std_ulogic; -- rstn_i is active-low, like most NEORV32 reset signals.

    -- CPU bus interface.
    -- The CPU sends memory-mapped CFS accesses through bus_req_i.
    -- This module answers through bus_rsp_o.
    bus_req_i : in  bus_req_t;
    bus_rsp_o : out bus_rsp_t;

    irq_o     : out std_ulogic; -- interrupt output

    -- not used in this project
    cfs_in_i  : in  std_ulogic_vector(255 downto 0);
    cfs_out_o : out std_ulogic_vector(255 downto 0)
  );
end entity;

architecture neorv32_cfs_rtl of neorv32_cfs is

  -- Register word indexes.
  -- bus_req_i.addr is a byte address; bus_access drops addr(1 downto 0) to
  -- decode these 32-bit register indexes.
  constant REG_INPUTSTATE0    : natural := 0;
  constant REG_INPUTSTATE1    : natural := 1;
  constant REG_INPUTSTATE2    : natural := 2;
  constant REG_INPUTSTATE3    : natural := 3;
  constant REG_KEY0           : natural := 4;
  constant REG_KEY1           : natural := 5;
  constant REG_KEY2           : natural := 6;
  constant REG_KEY3           : natural := 7;
  constant REG_KEY4           : natural := 8;
  constant REG_KEY5           : natural := 9;
  constant REG_KEY6           : natural := 10;
  constant REG_KEY7           : natural := 11;
  constant REG_OUTPUTSTATE0   : natural := 12;
  constant REG_OUTPUTSTATE1   : natural := 13;
  constant REG_OUTPUTSTATE2   : natural := 14;
  constant REG_OUTPUTSTATE3   : natural := 15;
  constant REG_CONTROL        : natural := 16;
  constant REG_STATUS         : natural := 17;

  -- control register bit positions
  constant CTRL_START : natural := 0;
  constant CTRL_IRQ_ACK : natural := 1;

  -- status register bit positions
  constant STATUS_DONE : natural := 0;
  constant STATUS_BUSY : natural := 1;

  -- configuration bit positions inside the control/status word
  constant CONFIG_KEY_MODE_LSB : natural := 2;
  constant CONFIG_KEY_MODE_MSB : natural := 3;
  constant CONFIG_OPERATION : natural := 4;

  signal done_persistent : std_ulogic; -- aes_done value is persistent until the acknowledgement of the cpu, it's connected to irq_o
  -- -------------------------------- --
  --   AES-facing registers/signals   --
  -- -------------------------------- --

  signal input_state_reg : text_type;
  signal cipher_key : key_type;
  signal key_size : key_size_type;
  signal operation : operation_type;
  signal output_state_reg : text_type;
  signal aes_start : std_ulogic;
  signal aes_busy : std_ulogic;
  signal aes_done : std_ulogic;
  signal aes_clear_output : std_ulogic;


begin

  -- external CFS conduits are not used in this example
  cfs_out_o <= (Others => '0');

  -- simple interrupt mechanism
  irq_o <= done_persistent;

  -- --------------------- --
  --   AES core instance   --
  -- --------------------- --

  aes_core_inst : entity work.aes_core(core_rtl)
    Port Map(
      clk_i     => clk_i,
      resetn_i  => rstn_i,
      start     => aes_start,
      clear_output => aes_clear_output,
      key_size  => key_size,
      operation => operation,
      cipher_key => cipher_key,
      state_i   => input_state_reg,
      state_o   => output_state_reg,
      done      => aes_done
    );

  -- ---------------------- --
  --   Bus access process
  -- ---------------------- --
  --   bus_req_i.stb  = one valid access request from CPU.
  --   bus_req_i.rw   = '1' for write, '0' for read.
  --   bus_req_i.addr = byte address inside the CFS address space.
  --   bus_req_i.data = write data from CPU.
  --
  --   bus_rsp_o.ack  = acknowledge the access.
  --   bus_rsp_o.err  = bus error flag.
  --   bus_rsp_o.data = read data back to CPU.
  --
  -- This example acknowledges every access immediately in the next clocked
  -- bus cycle and returns zero for unmapped reads.

  bus_access : process(rstn_i, clk_i)
    variable reg_addr_v : natural range REG_INPUTSTATE0 to REG_STATUS;
  begin
    if rstn_i = '0' then
      input_state_reg <= (Others => (Others => '0'));
      cipher_key <= (Others => (Others => '0'));
      key_size <= invalid;
      operation <= encrypt;
      aes_clear_output <= '0';
      aes_start <= '0';
      done_persistent <= '0';
      bus_rsp_o <= rsp_terminate_c;
      aes_busy <= '0';

    elsif rising_edge(clk_i) then
      -- defaults for every cycle
      aes_start       <= '0'; -- aes_start is intentionally a one clock cycle pulse
      aes_clear_output <= '0';
      bus_rsp_o.ack   <= bus_req_i.stb;
      bus_rsp_o.err   <= '0';
      bus_rsp_o.data  <= (Others => '0');

      if aes_start = '1' then -- resetting cipher key and state_i which have already been stored respectively in key_expansion and in core in state_i_reg
        cipher_key <= (Others => (Others => '0'));
        input_state_reg <= (Others => (Others => '0'));
      elsif aes_done = '1' then -- keep done value until new conversion or explicit clear
        done_persistent <= '1';
        aes_busy <= '0';
      end if;
      
      -- decode word address from byte address
      reg_addr_v := to_integer(unsigned(bus_req_i.addr(15 downto 2)));

      if bus_req_i.stb = '1' then

        -- CPU write access
        if bus_req_i.rw = '1' then
          -- when the accelerator is busy, the input cannot be changed so all the CPU writes are ignored
          if aes_busy = '0' then
            case reg_addr_v is
              -- input state writes
              -- if aes is busy, input state word doesn't change
              when REG_INPUTSTATE0 =>
                input_state_reg(input_state_reg'HIGH) <= bus_req_i.data;

              when REG_INPUTSTATE1 =>
                input_state_reg(input_state_reg'HIGH - 1) <= bus_req_i.data;

              when REG_INPUTSTATE2 =>
                input_state_reg(input_state_reg'HIGH - 2) <= bus_req_i.data;

              when REG_INPUTSTATE3 =>
                input_state_reg(input_state_reg'HIGH - 3) <= bus_req_i.data;

              -- Reads from these registers return zero below.
              when REG_KEY0 =>
                cipher_key(cipher_key'HIGH) <= bus_req_i.data;

              when REG_KEY1 =>
                cipher_key(cipher_key'HIGH - 1) <= bus_req_i.data;

              when REG_KEY2 =>
                cipher_key(cipher_key'HIGH - 2) <= bus_req_i.data;

              when REG_KEY3 =>
                cipher_key(cipher_key'HIGH - 3) <= bus_req_i.data;

              when REG_KEY4 =>
                cipher_key(cipher_key'HIGH - 4) <= bus_req_i.data;

              when REG_KEY5 =>
                cipher_key(cipher_key'HIGH - 5) <= bus_req_i.data;

              when REG_KEY6 =>
                cipher_key(cipher_key'HIGH - 6) <= bus_req_i.data;

              when REG_KEY7 =>
                cipher_key(cipher_key'HIGH - 7) <= bus_req_i.data;

              -- Control register.
              -- START is not stored as a persistent bit. A write with bit 0 set
              -- creates a one-clock pulse to aes_core.start_i.
              -- CLEAR_KEY zeroizes the key register.
              when REG_CONTROL =>
                if bus_req_i.data(CTRL_START) = '1' then
                  aes_start <= '1';
                  aes_busy <= '1';
                elsif bus_req_i.data(CTRL_IRQ_ACK) = '1' then
                  done_persistent <= '0'; -- done_persistent connected to irq_o
                  bus_rsp_o.data <= (Others => '0'); -- resetting output data bus
                end if;

                if bus_req_i.data(CONFIG_KEY_MODE_MSB downto CONFIG_KEY_MODE_LSB) = "01" then
                  key_size <= is128bit;
                elsif bus_req_i.data(CONFIG_KEY_MODE_MSB downto CONFIG_KEY_MODE_LSB) = "10" then
                  key_size <= is192bit;
                elsif bus_req_i.data(CONFIG_KEY_MODE_MSB downto CONFIG_KEY_MODE_LSB) = "11" then
                  key_size <= is256bit;
                else
                  key_size <= invalid;
                end if;

                if bus_req_i.data(CONFIG_OPERATION) = '1' then
                  operation <= decrypt;
                else
                  operation <= encrypt;
                end if;
                
              when Others => null;

            end case;
          end if;

        -- CPU read access
        else
          case reg_addr_v is -- the only readable thing is the

            -- check status of accelerator
            when REG_STATUS =>
              bus_rsp_o.data(STATUS_DONE) <= done_persistent;
              bus_rsp_o.data(STATUS_BUSY) <= aes_busy;
              
            -- output state registers
            when REG_OUTPUTSTATE0 =>
              bus_rsp_o.data <= output_state_reg(output_state_reg'HIGH);
            when REG_OUTPUTSTATE1 =>
              bus_rsp_o.data <= output_state_reg(output_state_reg'HIGH - 1);
            when REG_OUTPUTSTATE2 =>
              bus_rsp_o.data <= output_state_reg(output_state_reg'HIGH - 2);
            when REG_OUTPUTSTATE3 =>
              bus_rsp_o.data <= output_state_reg(output_state_reg'HIGH - 3);
              aes_clear_output <= '1'; -- clear the output the clock cycle after the end of the reading
            
            -- input state, key and control registers are intentionally write-only
            when Others =>
              bus_rsp_o.data <= (Others => '0');
            
          end case;
        end if;
      end if;
    end if;
  end process bus_access;
end architecture;
