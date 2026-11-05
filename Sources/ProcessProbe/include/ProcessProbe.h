#ifndef PROCESS_PROBE_H
#define PROCESS_PROBE_H
#include <stdint.h>
typedef struct {
    int32_t pid, parent;
    uint64_t start_seconds, start_microseconds, footprint;
    int memory_error;
    char name[256];
    char path[4096];
} WRProcess;
int wr_list_pids(int32_t *buffer, int bytes);
int wr_read_process(int32_t pid, WRProcess *output);
#endif
