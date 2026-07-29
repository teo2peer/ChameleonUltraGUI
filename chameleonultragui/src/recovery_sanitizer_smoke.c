#include <assert.h>
#include <stdbool.h>
#include <stdint.h>

#include "recovery.h"

static bool contains_key(const uint64_t *keys, uint32_t count, uint64_t expected)
{
  for (uint32_t index = 0; index < count; index++)
  {
    if (keys[index] == expected) return true;
  }
  return false;
}

int main(void)
{
  DarksideItem darkside_items[] = {
    {913032415u, 216745674933338888ull, 0u, 0u, 0u},
    {913032415u, 1010230244403446283ull, 0u, 1u, 0u},
  };
  Darkside darkside_input = {
    2374329723u,
    darkside_items,
    (uint32_t)(sizeof(darkside_items) / sizeof(darkside_items[0])),
  };
  uint32_t key_count = 0;
  uint64_t *keys = darkside(&darkside_input, &key_count);
  assert(keys != NULL);
  assert(contains_key(keys, key_count, 0xffffffffffffull));
  recovery_free(keys);

  Nested nested_input = {
    2374329723u,
    613u,
    1999585272u,
    3173333529u,
    3u,
    128306861u,
    2363514210u,
    7u,
  };
  keys = nested(&nested_input, &key_count);
  assert(keys != NULL);
  assert(contains_key(keys, key_count, 0xffffffffffffull));
  recovery_free(keys);

  StaticEncryptedNested static_input = {
    0x72000003u,
    0x82d91e42u,
    0x98b90e04u,
    1011u,
  };
  keys = static_encrypted_nested(&static_input, &key_count);
  assert(keys != NULL);
  assert(contains_key(keys, key_count, 0x55654483da14ull));
  recovery_free(keys);

  return 0;
}
