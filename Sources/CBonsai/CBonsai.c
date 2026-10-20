#include "CBonsai.h"
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <dispatch/dispatch.h>
#include <sys/sysctl.h>
#include <libproc.h>
#include <sys/proc_info.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <pwd.h>
#include <sys/resource.h>

bonsai_stats bonsai_system(void) {
    bonsai_stats result = {0}; host_cpu_load_info_data_t cpu; mach_msg_type_number_t cpu_count = HOST_CPU_LOAD_INFO_COUNT;
    mach_port_t host = mach_host_self();
    if(host_statistics(host,HOST_CPU_LOAD_INFO,(host_info_t)&cpu,&cpu_count)==KERN_SUCCESS) {
        result.user=cpu.cpu_ticks[CPU_STATE_USER]; result.system=cpu.cpu_ticks[CPU_STATE_SYSTEM]; result.idle=cpu.cpu_ticks[CPU_STATE_IDLE]; result.nice=cpu.cpu_ticks[CPU_STATE_NICE]; result.valid=1;
    }
    vm_statistics64_data_t vm; mach_msg_type_number_t count=HOST_VM_INFO64_COUNT;
    vm_size_t page; host_page_size(host,&page);
    if(host_statistics64(host,HOST_VM_INFO64,(host_info64_t)&vm,&count)==KERN_SUCCESS) {
        result.free_memory=(uint64_t)(vm.free_count+vm.inactive_count)*page; result.active_memory=(uint64_t)vm.active_count*page;
        result.wired_memory=(uint64_t)vm.wire_count*page; result.compressed_memory=(uint64_t)vm.compressor_page_count*page;
    }
    size_t len=sizeof(result.total_memory); sysctlbyname("hw.memsize",&result.total_memory,&len,NULL,0);
    result.pressure=-1; len=sizeof(result.pressure); sysctlbyname("kern.memorystatus_vm_pressure_level",&result.pressure,&len,NULL,0);
    mach_port_deallocate(mach_task_self(),host); return result;
}
int bonsai_interfaces(bonsai_interface *out,int capacity) {
    int mib[6]={CTL_NET,PF_ROUTE,0,AF_UNSPEC,NET_RT_IFLIST2,0}; size_t length=0;
    if(sysctl(mib,6,NULL,&length,NULL,0)!=0 || length>2*1024*1024) return -1;
    char *buffer=malloc(length); if(!buffer) return -1;
    if(sysctl(mib,6,buffer,&length,NULL,0)!=0) { free(buffer); return -1; }
    int count=0;
    for(char *p=buffer;p<buffer+length && count<capacity;) {
        struct if_msghdr *header=(struct if_msghdr *)p;
        if(header->ifm_msglen==0 || p+header->ifm_msglen>buffer+length) break;
        if(header->ifm_type==RTM_IFINFO2 && header->ifm_msglen>=sizeof(struct if_msghdr2)) {
            struct if_msghdr2 *info=(struct if_msghdr2 *)p;
            if((info->ifm_flags&IFF_UP) && !(info->ifm_flags&IFF_LOOPBACK)) {
                if(if_indextoname(info->ifm_index,out[count].name)) {
                    out[count].received=info->ifm_data.ifi_ibytes; out[count].sent=info->ifm_data.ifi_obytes; count++;
                }
            }
        }
        p+=header->ifm_msglen;
    }
    free(buffer); return count;
}
static mach_timebase_info_data_t cpu_timebase;
static dispatch_once_t cpu_timebase_once;
static void load_cpu_timebase(void *context) {(void)context;mach_timebase_info(&cpu_timebase);}
uint64_t bonsai_cpu_nanoseconds(uint64_t ticks) {
    dispatch_once_f(&cpu_timebase_once,NULL,load_cpu_timebase);
    if(!cpu_timebase.denom) return 0;
    __uint128_t value=(__uint128_t)ticks*cpu_timebase.numer/cpu_timebase.denom;
    return value>UINT64_MAX ? UINT64_MAX:(uint64_t)value;
}
int bonsai_process_identity(int pid,bonsai_process *out) {
    struct proc_bsdinfo bsd;
    memset(out,0,sizeof(*out));
    if(proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&bsd,sizeof(bsd))==sizeof(bsd)) {
        out->pid=pid;out->parent_pid=bsd.pbi_ppid;out->uid=bsd.pbi_uid;out->start_sec=bsd.pbi_start_tvsec;out->start_usec=bsd.pbi_start_tvusec;
        strncpy(out->name,bsd.pbi_comm,sizeof(out->name)-1);
    } else {
        // Public process identity remains readable even when task metrics are
        // restricted. Keep the real owner/start time; never infer ownership.
        struct kinfo_proc info={0};size_t size=sizeof(info);int mib[]={CTL_KERN,KERN_PROC,KERN_PROC_PID,pid};
        if(sysctl(mib,4,&info,&size,NULL,0)!=0 || size!=sizeof(info) || info.kp_proc.p_pid!=pid) return 0;
        out->pid=pid;out->parent_pid=info.kp_eproc.e_ppid;out->uid=info.kp_eproc.e_ucred.cr_uid;
        out->start_sec=info.kp_proc.p_starttime.tv_sec;out->start_usec=info.kp_proc.p_starttime.tv_usec;
        strncpy(out->name,info.kp_proc.p_comm,sizeof(out->name)-1);
    }
    char name[256]={0};if(proc_name(pid,name,sizeof(name))>0) {strncpy(out->name,name,sizeof(out->name)-1);}
    if(proc_pidpath(pid,out->executable,sizeof(out->executable))<=0) out->executable[0]=0;
    struct proc_taskinfo task;
    if(proc_pidinfo(pid,PROC_PIDTASKINFO,0,&task,sizeof(task))==sizeof(task)) { out->metrics_valid=1; out->resident=task.pti_resident_size; out->cpu_ns=bonsai_cpu_nanoseconds(task.pti_total_user+task.pti_total_system); }
    struct rusage_info_v6 energy={0};
    if(proc_pid_rusage(pid,RUSAGE_INFO_V6,(rusage_info_t *)&energy)==0) {
        out->wakeups_valid=1;out->idle_wakeups=energy.ri_pkg_idle_wkups;
        if(energy.ri_energy_nj>0) {out->energy_valid=1;out->energy_nj=energy.ri_energy_nj;}
    } else {
        struct rusage_info_v2 fallback={0};
        if(proc_pid_rusage(pid,RUSAGE_INFO_V2,(rusage_info_t *)&fallback)==0) {out->wakeups_valid=1;out->idle_wakeups=fallback.ri_pkg_idle_wkups;}
    }
    return 1;
}
int bonsai_processes(bonsai_process *out,int capacity) {
    int needed=proc_listallpids(NULL,0); if(needed<=0) return -1;
    int size=needed+256; int *pids=calloc(size,sizeof(int)); if(!pids) return -1;
    int n=proc_listallpids(pids,size*sizeof(int)); int count=0;
    for(int i=0;i<n && i<size && count<capacity;i++) if(pids[i]>0 && bonsai_process_identity(pids[i],&out[count])) count++;
    free(pids); return count;
}

// On-demand, bounded metadata only. Never reads arguments, environment or file contents.
int bonsai_process_details(int pid,bonsai_process_detail *out) {
    memset(out,0,sizeof(*out));
    if(!bonsai_process_identity(pid,&out->identity)) return 0;
    struct proc_bsdinfo bsd;
    if(proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&bsd,sizeof(bsd))==sizeof(bsd)) {
        if(bsd.pbi_uid!=out->identity.uid || bsd.pbi_start_tvsec!=out->identity.start_sec || bsd.pbi_start_tvusec!=out->identity.start_usec) return 0;
        // pbi_nfiles is descriptor-table capacity, not the number of open FDs.
        // Count only descriptor metadata; never resolve paths or read contents.
        const int stride=sizeof(struct proc_fdinfo),limit=16384*stride;
        int needed=proc_pidinfo(pid,PROC_PIDLISTFDS,0,NULL,0);
        if(needed>0 && needed<=limit-64*stride) {
            int capacity=needed+64*stride;void *fds=malloc(capacity);
            if(fds) {
                int count=proc_pidinfo(pid,PROC_PIDLISTFDS,0,fds,capacity);
                if(count>0 && count<capacity && count%stride==0) {out->files_valid=1;out->open_files=count/stride;}
                free(fds);
            }
        }
    }
    struct proc_taskinfo task;
    if(proc_pidinfo(pid,PROC_PIDTASKINFO,0,&task,sizeof(task))==sizeof(task)) {out->threads_valid=1;out->threads=task.pti_threadnum;}
    struct rusage_info_v2 usage={0};
    if(proc_pid_rusage(pid,RUSAGE_INFO_V2,(rusage_info_t *)&usage)==0) {out->io_valid=1;out->bytes_read=usage.ri_diskio_bytesread;out->bytes_written=usage.ri_diskio_byteswritten;}
    struct proc_vnodepathinfo vnode;
    if(proc_pidinfo(pid,PROC_PIDVNODEPATHINFO,0,&vnode,sizeof(vnode))==sizeof(vnode)) {out->cwd_valid=1;strncpy(out->cwd,vnode.pvi_cdir.vip_path,sizeof(out->cwd)-1);}
    struct passwd account,*found=NULL;char buffer[4096];
    if(getpwuid_r(out->identity.uid,&account,buffer,sizeof(buffer),&found)==0 && found) strncpy(out->user,found->pw_name,sizeof(out->user)-1);
    bonsai_process after;
    if(!bonsai_process_identity(pid,&after) || after.uid!=out->identity.uid || after.start_sec!=out->identity.start_sec || after.start_usec!=out->identity.start_usec) {memset(out,0,sizeof(*out));return 0;}
    return 1;
}
