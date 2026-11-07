#pragma once
#include <stdint.h>

// Returns 0 on success. *size is in/out: buffer capacity in, bytes read out.
int smc_read(const char *key, uint8_t *buf, uint32_t *size, uint32_t *type);
// Returns 0 on success. Writing requires root.
int smc_write(const char *key, const uint8_t *buf, uint32_t size);
int smc_has_key(const char *key);

// Native macOS charge limit (PowerUI). get: 100 when off, -1 if unavailable. set: 100 turns it off; 0 on success.
int native_limit_get(void);
int native_limit_set(int limit);
