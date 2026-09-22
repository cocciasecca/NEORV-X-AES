// aes cfs driver

#include <neorv32.h>
#include "aes.h"

#define REG_INPUT_STATE0 0
#define REG_KEY0 4
#define REG_OUTPUT_STATE0 12
#define REG_CONTROL 16

#define CONTROL_START (1u << 0)
#define CONTROL_IRQ_ACK (1u << 1)
#define CONTROL_KEY_MODE_SHIFT 2
#define CONTROL_OPERATION_SHIFT 4

// set by the assembly interrupt handler
volatile uint32_t aes_completed;

// direct machine mode interrupt handler
extern void aes_direct_trap_entry(void);

static uint32_t aes_key_words(aes_key_size_t key_size){
  if (key_size == is128bit)
    return 4;
  if (key_size == is192bit)
    return 6;
  if (key_size == is256bit)
    return 8;
  return 0;
}

int aes_cfs_irq_setup(void){
  aes_completed = 0;

  // clear a pending interrupt before enabling the interrupt channel
  NEORV32_CFS->REG[REG_CONTROL] = CONTROL_IRQ_ACK;

  // use the small aes handler instead of the generic rte handler
  neorv32_cpu_csr_write(CSR_MTVEC, (uint32_t)(uintptr_t)&aes_direct_trap_entry);

  // enable the cfs interrupt and global machine interrupts
  neorv32_cpu_csr_set(CSR_MIE, 1u << CFS_FIRQ_ENABLE);
  neorv32_cpu_csr_set(CSR_MSTATUS, 1u << CSR_MSTATUS_MIE);
  return 0;
}

void aes_process_block(aes_operation_t operation, aes_key_size_t key_size, const uint32_t *key, const uint32_t input_state[4], uint32_t output_state[4]){
  uint32_t key_words = aes_key_words(key_size); // number of words used by the selected key size
  uint32_t control_word = CONTROL_START | // command sent to the cfs control register
                          ((uint32_t)key_size << CONTROL_KEY_MODE_SHIFT) |
                          ((uint32_t)operation << CONTROL_OPERATION_SHIFT);

  for (int i = 0; i < 4; i++){
    NEORV32_CFS->REG[REG_INPUT_STATE0 + i] = input_state[i];
  }

  // the first four key words are used by every aes key size
  NEORV32_CFS->REG[REG_KEY0 + 0] = key[0];
  NEORV32_CFS->REG[REG_KEY0 + 1] = key[1];
  NEORV32_CFS->REG[REG_KEY0 + 2] = key[2];
  NEORV32_CFS->REG[REG_KEY0 + 3] = key[3];

  // aes 192 and aes 256 also use words four and five
  if (key_words >= 6){
    NEORV32_CFS->REG[REG_KEY0 + 4] = key[4];
    NEORV32_CFS->REG[REG_KEY0 + 5] = key[5];
  }

  // only aes 256 uses the last two words
  if (key_words == 8){
    NEORV32_CFS->REG[REG_KEY0 + 6] = key[6];
    NEORV32_CFS->REG[REG_KEY0 + 7] = key[7];
  }

  // clear the software flag before starting a new operation
  aes_completed = 0;

  NEORV32_CFS->REG[REG_CONTROL] = control_word; // start the selected operation

  // sleep until the interrupt handler reports completion
  while (aes_completed == 0){
    neorv32_cpu_sleep();
  }

  for (int i = 0; i < 4; i++){
    output_state[i] = NEORV32_CFS->REG[REG_OUTPUT_STATE0 + i];
  }
}

void aes_encrypt_block(aes_key_size_t key_size, const uint32_t *key, const uint32_t input_state[4], uint32_t output_state[4]){
  aes_process_block(encrypt, key_size, key, input_state, output_state);
}

void aes_decrypt_block(aes_key_size_t key_size, const uint32_t *key, const uint32_t input_state[4], uint32_t output_state[4]){
  aes_process_block(decrypt, key_size, key, input_state, output_state);
}
