#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
void *cz_manga_create(const char *path, int accelerate);
void cz_manga_destroy(void *model);
int64_t cz_manga_run(void *model, const float *input, const int64_t *shape, int rank,
                    float *output, int64_t capacity, int64_t *output_shape, int *output_rank);
#ifdef __cplusplus
}
#endif
