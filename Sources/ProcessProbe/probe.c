#include "ProcessProbe.h"
#include <libproc.h>
#include <sys/resource.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>

int wr_list_pids(int32_t *buffer, int bytes) {
    return proc_listallpids(buffer, bytes);
}

int wr_read_process(int32_t pid, WRProcess *output) {
    struct proc_bsdinfo before = {0}, after = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &before, sizeof(before)) != sizeof(before))
        return 0;
    memset(output, 0, sizeof(*output));
    output->pid = pid;
    output->parent = before.pbi_ppid;
    output->start_seconds = before.pbi_start_tvsec;
    output->start_microseconds = before.pbi_start_tvusec;
    snprintf(output->name, sizeof(output->name), "%s", before.pbi_name[0] ? before.pbi_name : before.pbi_comm);
    proc_pidpath(pid, output->path, sizeof(output->path));
    struct rusage_info_v0 usage = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V0, (rusage_info_t *)&usage) == 0)
        output->footprint = usage.ri_phys_footprint;
    else
        output->memory_error = errno ? errno : EACCES;
    // Reject processes which exited or whose PID was reused during sampling.
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &after, sizeof(after)) != sizeof(after)
        || before.pbi_start_tvsec != after.pbi_start_tvsec
        || before.pbi_start_tvusec != after.pbi_start_tvusec) return 0;
    return 1;
}
