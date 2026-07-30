#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#include "recovery.h"

uint64_t *most_frequent_uint64(uint64_t *keys, uint32_t size, uint32_t *outputKeyCount);

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
  uint64_t unique_candidates[] = {3u, 1u, 2u};
  uint32_t key_count = 0;
  uint64_t *keys = most_frequent_uint64(unique_candidates, 3u, &key_count);
  assert(keys != NULL);
  assert(key_count == 3u);
  recovery_free(keys);

  const uint32_t large_candidate_count = 100001u;
  uint64_t *large_candidates = malloc(large_candidate_count * sizeof(uint64_t));
  assert(large_candidates != NULL);
  for (uint32_t index = 0; index < large_candidate_count; index++)
  {
    large_candidates[index] = index;
  }
  keys = most_frequent_uint64(large_candidates, large_candidate_count, &key_count);
  assert(keys != NULL);
  assert(key_count == large_candidate_count);
  recovery_free(keys);
  free(large_candidates);

  uint64_t mixed_candidates[] = {7u, 9u, 7u, 5u, 9u, 7u};
  keys = most_frequent_uint64(mixed_candidates, 6u, &key_count);
  assert(keys != NULL);
  assert(key_count == 3u);
  assert(keys[0] == 7u);
  assert(keys[1] == 9u);
  assert(keys[2] == 5u);
  recovery_free(keys);

  DarksideItem darkside_items[] = {
    {913032415u, 216745674933338888ull, 0u, 0u, 0u},
    {913032415u, 1010230244403446283ull, 0u, 1u, 0u},
  };
  Darkside darkside_input = {
    2374329723u,
    darkside_items,
    (uint32_t)(sizeof(darkside_items) / sizeof(darkside_items[0])),
  };
  key_count = 0;
  keys = darkside(&darkside_input, &key_count);
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

  nested_input.dist = 13u;
  keys = nested(&nested_input, &key_count);
  assert(key_count == 0u);
  recovery_free(keys);

  nested_input.dist = 65535u;
  keys = nested(&nested_input, &key_count);
  assert(key_count == 0u);
  recovery_free(keys);

  nested_input.dist = UINT32_MAX;
  keys = nested(&nested_input, &key_count);
  assert(key_count == 0u);
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
