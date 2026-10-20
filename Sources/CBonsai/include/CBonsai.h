#ifndef CBONSAI_H
#define CBONSAI_H
#include <stdint.h>
#include <stddef.h>
typedef struct { uint64_t user, system, idle, nice, total_memory, free_memory, active_memory, wired_memory, compressed_memory; int pressure, valid; } bonsai_stats;
typedef struct { char name[64]; uint64_t received, sent; } bonsai_interface;
typedef struct { int32_t pid, parent_pid; uint32_t uid; uint64_t start_sec, start_usec, resident, cpu_ns, energy_nj, idle_wakeups; int metrics_valid, energy_valid, wakeups_valid; char name[256], executable[1024]; } bonsai_process;
typedef struct { bonsai_process identity; int threads_valid, files_valid, io_valid, cwd_valid; uint32_t threads, open_files; uint64_t bytes_read, bytes_written; char cwd[1024], user[256]; } bonsai_process_detail;
int bonsai_process_details(int pid, bonsai_process_detail *out);
bonsai_stats bonsai_system(void);
int bonsai_interfaces(bonsai_interface *out, int capacity);
int bonsai_processes(bonsai_process *out, int capacity);
uint64_t bonsai_cpu_nanoseconds(uint64_t ticks);
int bonsai_process_identity(int pid, bonsai_process *out);
int bonsai_read_login_inventory(char **output);
int bonsai_extract_update(const char *archive_path,const char *destination);
int bonsai_update_store(const char *helper,const char *bundle,char **output);
int bonsai_redownload_store(const char *helper,const char *bundle,const char *app,char **output);
void bonsai_free_inventory(char *output);
typedef struct { int32_t device; uint64_t inode; uint32_t owner; uint16_t mode, links; int64_t size, modified, nanos; uint64_t allocated; } bonsai_disk_node;
typedef int (*bonsai_disk_visit)(void *context,const char *path,const bonsai_disk_node *node,int error);
int bonsai_disk_walk(const char *root,uint64_t max_nodes,double seconds,void *context,bonsai_disk_visit visit);
int bonsai_temperatures(double *cpu,double *gpu);
double bonsai_decode_temperature(uint32_t type,const uint8_t *bytes,size_t size);
#endif
