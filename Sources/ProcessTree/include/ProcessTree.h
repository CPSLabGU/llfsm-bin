#ifndef PROCESS_TREE_H
#define PROCESS_TREE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Returns zero on success or a platform error code; arguments are NULL-terminated. */
int process_tree_run(
    const char *executable,
    const char *const arguments[],
    uint32_t grace_period_milliseconds,
    int32_t *exit_status
);

#ifdef __cplusplus
}
#endif

#endif
