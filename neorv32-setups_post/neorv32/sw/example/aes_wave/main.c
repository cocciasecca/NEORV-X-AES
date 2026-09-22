// aes cfs known answer tests for 128, 192 and 256 bit keys

#include <neorv32.h>
#include <stdint.h>
#include "aes.h"

#define BAUD_RATE 19200

static int words_equal(const uint32_t a[4], const uint32_t b[4]){
  for (int i = 0; i < 4; i++){
    if (a[i] != b[i])
      return 0;
  }
  return 1;
}

static void print_block(const char *label, const uint32_t block[4]){
  neorv32_uart0_printf("%s: %x %x %x %x\n", label, block[0], block[1], block[2], block[3]);
}

static int run_aes_test(const char *name, aes_operation_t operation, aes_key_size_t key_size, const uint32_t *key, const uint32_t input_state[4], const uint32_t expected_output_state[4]){
  uint32_t start_cycles; // cycle counter before starting the operation
  uint32_t hw_cycles; // cycles used by the driver and the accelerator
  uint32_t output_state[4]; // result read from the cfs

  start_cycles = neorv32_cpu_get_cycle();
  aes_process_block(operation, key_size, key, input_state, output_state);
  hw_cycles = neorv32_cpu_get_cycle() - start_cycles;

  neorv32_uart0_printf("\n- %s\n", name);
  print_block("Input state: ", input_state);
  print_block("Output state: ", output_state);
  print_block("Expected: ", expected_output_state);

  if (words_equal(output_state, expected_output_state))
    neorv32_uart0_printf("%s test: PASS\n", name);
  else
    neorv32_uart0_printf("%s test: FAIL\n", name);

  neorv32_uart0_printf("%s cycles: %u\n", name, hw_cycles);

  return words_equal(output_state, expected_output_state) ? 0 : 1;
}

int main(){
  int failures = 0; // number of failed known answer tests

  // input state is CiaoMamaComeStai
  const uint32_t input_state[4] = {
      0x4369616f, 0x4d616d61, 0x436f6d65, 0x53746169};

  // aes 128 key is passwordsemplice
  const uint32_t key128[4] = {
      0x70617373, 0x776f7264, 0x73656d70, 0x6c696365};

  // aes 192 key is "PasswordSemplicePeròCon."
  // latin 1 byte f2 is used for the accented o
  const uint32_t key192[6] = {
      0x50617373, 0x776f7264, 0x53656d70, 0x6c696365,
      0x506572f2, 0x436f6e2e};

  // aes 256 key is "PasswordSemplicePeròCon.eCharEsp"
  const uint32_t key256[8] = {
      0x50617373, 0x776f7264, 0x53656d70, 0x6c696365,
      0x506572f2, 0x436f6e2e, 0x65436861, 0x72457370};

  const uint32_t encrypted_state128[4] = {
      0xce3ec947, 0x06147189, 0x3c930073, 0x0cf50d95};

  const uint32_t encrypted_state192[4] = {
      0x6205ff8e, 0x7f7bfeb8, 0x5b563ac8, 0x78a24fda};

  const uint32_t encrypted_state256[4] = {
      0x82fb1e7a, 0x80341847, 0x71957dbb, 0x941f6b65};

  neorv32_rte_setup();
  neorv32_uart0_setup(BAUD_RATE, 0);

  // wait for one uart character only on the fpga
  if (neorv32_sysinfo_is_sim() == 0)
    neorv32_uart0_getc();

  neorv32_uart0_printf("=== AES CFS demo: encrypt/decrypt 128/192/256 ===\n");

  // stop if the cfs was not synthesized
  if (neorv32_cfs_available() == 0){
    neorv32_uart0_printf("Error: CFS is not synthesized.\n");
    return 1;
  }

  // configure the cfs interrupt
  if (aes_cfs_irq_setup() != 0){
    neorv32_uart0_printf("Error: CFS interrupt setup failed.\n");
    return 1;
  }

  failures = failures + run_aes_test("AES-128 encrypt", encrypt, is128bit, key128, input_state, encrypted_state128);
  failures = failures + run_aes_test("AES-128 decrypt", decrypt, is128bit, key128, encrypted_state128, input_state);
  failures = failures + run_aes_test("AES-192 encrypt", encrypt, is192bit, key192, input_state, encrypted_state192);
  failures = failures + run_aes_test("AES-192 decrypt", decrypt, is192bit, key192, encrypted_state192, input_state);
  failures = failures + run_aes_test("AES-256 encrypt", encrypt, is256bit, key256, input_state, encrypted_state256);
  failures = failures + run_aes_test("AES-256 decrypt", decrypt, is256bit, key256, encrypted_state256, input_state);

  neorv32_uart0_printf("\nAES CFS summary: %s\n", failures == 0 ? "PASS" : "FAIL");


  return failures == 0 ? 0 : 1;
}
