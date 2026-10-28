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

#ifdef _WIN32
/* Requests a graceful shutdown of the running process tree without sending a console event. */
void process_tree_request_shutdown(void);
#endif

#ifdef __cplusplus
}
#endif

#endif
