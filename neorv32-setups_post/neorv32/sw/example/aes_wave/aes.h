#ifndef AES_CFS_H
#define AES_CFS_H

#include <stdint.h>

// operation written in the cfs control register
typedef enum{
  encrypt = 0,
  decrypt = 1
} aes_operation_t;

// key size mode written in the cfs control register
typedef enum{
  is128bit = 1,
  is192bit = 2,
  is256bit = 3
} aes_key_size_t;

// configure the cfs interrupt
int aes_cfs_irq_setup(void);

// process one 128 bit state
void aes_process_block(aes_operation_t operation, aes_key_size_t key_size,
                       const uint32_t *key, const uint32_t input_state[4],
                       uint32_t output_state[4]);


#endif
