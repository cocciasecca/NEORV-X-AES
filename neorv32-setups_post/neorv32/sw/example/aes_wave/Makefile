# Run the AES firmware on the complete NEORV32 testbench and record only the
# AES CFS hierarchy in a compact GHDL waveform.

MARCH = rv32imc_zicsr_zifencei
EFFORT = -Os
USER_FLAGS += -ggdb -gdwarf-3
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=16k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=8k

APP_SRC += $(wildcard ./*.c)
APP_SRC += $(wildcard ./*.S)
APP_INC += -I .

NEORV32_HOME ?= ../../..

include $(NEORV32_HOME)/sw/common/common.mk

WAVE_FILE ?= $(CURDIR)/aes_wave.ghw
VCD_FILE  ?= $(CURDIR)/aes_wave.vcd
WAVE_OPT  ?= $(CURDIR)/aes_wave.opt
GTKW_FILE ?= $(CURDIR)/aes_wave.gtkw
STOP_TIME ?= 10ms

.PHONY: wave wave-ghw view-wave clean-wave

# Use direct text output so UART messages do not run at the physical baud rate.
wave wave-ghw: USER_FLAGS += -DUART0_SIM_MODE

wave: install
	$(ECHO) "Simulating the complete NEORV32; recording AES signals as VCD..."
	$(Q)$(CHMOD) +rx $(NEORV32_SIM_PATH)/ghdl.sh
	$(Q)$(NEORV32_SIM_PATH)/ghdl.sh --stop-time=$(STOP_TIME) \
	  --read-wave-opt=$(WAVE_OPT) --vcd=$(VCD_FILE)
	$(ECHO) "VCD waveform generated: $(VCD_FILE)"

wave-ghw: install
	$(ECHO) "Simulating the complete NEORV32; recording only AES signals..."
	$(Q)$(CHMOD) +rx $(NEORV32_SIM_PATH)/ghdl.sh
	$(Q)$(NEORV32_SIM_PATH)/ghdl.sh --stop-time=$(STOP_TIME) \
	  --read-wave-opt=$(WAVE_OPT) --wave=$(WAVE_FILE)
	$(ECHO) "Waveform generated: $(WAVE_FILE)"

view-wave:
	gtkwave $(VCD_FILE) $(GTKW_FILE)

clean-wave:
	$(Q)$(RM) -f $(WAVE_FILE) $(VCD_FILE)
