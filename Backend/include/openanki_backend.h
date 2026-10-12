#ifndef OPENANKI_BACKEND_H
#define OPENANKI_BACKEND_H
#include <stddef.h>
#include <stdint.h>
void *openanki_backend_create(const uint8_t *data, size_t length);
void openanki_backend_call(void *backend, const char *name, const uint8_t *data, size_t length, uint8_t **response, size_t *response_length);
void openanki_backend_free(uint8_t *data, size_t length);
void openanki_backend_destroy(void *backend);
#endif
