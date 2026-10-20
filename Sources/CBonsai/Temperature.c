#include "CBonsai.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <string.h>
#include <math.h>

/* Read-only AppleSMC wire format. Only key-info (9) and read-bytes (5)
 * requests are admitted. No fan, charging or other hardware writes.
 * Sensor-key reference: github.com/exelban/stats Modules/Sensors/values.swift.
 */
typedef struct {
    uint32_t key;
    struct {uint8_t major,minor,build,reserved;uint16_t release;} version;
    struct {uint16_t version,length;uint32_t cpu,gpu,memory;} limits;
    struct {uint32_t size,type;uint8_t attributes;} info;
    uint8_t result,status,command;
    uint32_t index;
    uint8_t bytes[32];
} bonsai_smc_packet;
_Static_assert(sizeof(bonsai_smc_packet)==80,"Unexpected SMC wire layout");
static uint32_t fourcc(const char *s) {return (uint32_t)(uint8_t)s[0]<<24|(uint32_t)(uint8_t)s[1]<<16|(uint32_t)(uint8_t)s[2]<<8|(uint8_t)s[3];}
double bonsai_decode_temperature(uint32_t type,const uint8_t *bytes,size_t size) {
    double value=NAN;
    if(!bytes) return NAN;
    if(type==fourcc("flt ") && size==4) {float raw;memcpy(&raw,bytes,4);value=raw;}
    else if(type==fourcc("sp78") && size==2) {int16_t raw=(int16_t)((uint16_t)bytes[0]<<8|bytes[1]);value=(double)raw/256.0;}
    return isfinite(value) && value>=5 && value<=125 ? value:NAN;
}
static double temperature(io_connect_t connection,const char *key) {
    bonsai_smc_packet in={0},out={0};size_t size=sizeof(out);
    in.key=fourcc(key);in.command=9;
    if(IOConnectCallStructMethod(connection,2,&in,sizeof(in),&out,&size)!=KERN_SUCCESS || size!=sizeof(out) || out.result || out.info.size>32) return NAN;
    in.info=out.info;in.command=5;memset(&out,0,sizeof(out));size=sizeof(out);
    if(IOConnectCallStructMethod(connection,2,&in,sizeof(in),&out,&size)!=KERN_SUCCESS || size!=sizeof(out) || out.result) return NAN;
    return bonsai_decode_temperature(in.info.type,out.bytes,in.info.size);
}
static double average(io_connect_t connection,const char *const *keys,size_t count) {
    double total=0;size_t measured=0;
    for(size_t i=0;i<count;i++) {double t=temperature(connection,keys[i]);if(isfinite(t)) {total+=t;measured++;}}
    return measured ? total/measured:NAN;
}
int bonsai_temperatures(double *cpu,double *gpu) {
    if(!cpu || !gpu) return 0;*cpu=NAN;*gpu=NAN;
    const char *m1cpu[]={"Tp09","Tp0T","Tp01","Tp05","Tp0D","Tp0H","Tp0L","Tp0P","Tp0X","Tp0b"};
    const char *m1gpu[]={"Tg05","Tg0D","Tg0L","Tg0T"};
    const char *m2cpu[]={"Tp1h","Tp1t","Tp1p","Tp1l","Tp01","Tp05","Tp09","Tp0D","Tp0X","Tp0b","Tp0f","Tp0j"};
    const char *m2gpu[]={"Tg0f","Tg0j"};
    const char *m3cpu[]={"Te05","Te0L","Te0P","Te0S","Tf04","Tf09","Tf0A","Tf0B","Tf0D","Tf0E","Tf44","Tf49","Tf4A","Tf4B","Tf4D","Tf4E"};
    const char *m3gpu[]={"Tf14","Tf18","Tf19","Tf1A","Tf24","Tf28","Tf29","Tf2A"};
    const char *m4cpu[]={"Te05","Te0S","Te09","Te0H","Tp01","Tp05","Tp09","Tp0D","Tp0V","Tp0Y","Tp0b","Tp0e"};
    const char *m4gpu[]={"Tg0G","Tg0H","Tg1U","Tg1k","Tg0K","Tg0L","Tg0d","Tg0e","Tg0j","Tg0k"};
    const char *m5cpu[]={"Tp00","Tp04","Tp08","Tp0C","Tp0G","Tp0K","Tp0O","Tp0R","Tp0U","Tp0X","Tp0a","Tp0d","Tp0g","Tp0j","Tp0m","Tp0p","Tp0u","Tp0y"};
    const char *m5gpu[]={"Tg0U","Tg0X","Tg0d","Tg0g","Tg0j","Tg1Y","Tg1c","Tg1g"};
    char brand[128]={0};size_t brandSize=sizeof(brand);if(sysctlbyname("machdep.cpu.brand_string",brand,&brandSize,NULL,0)!=0) return 0;
    const char *const *ck=NULL,*const *gk=NULL;size_t cn=0,gn=0;
#define SELECT(n) if(strstr(brand,"Apple M" #n)) {ck=m##n##cpu;cn=sizeof(m##n##cpu)/sizeof(char*);gk=m##n##gpu;gn=sizeof(m##n##gpu)/sizeof(char*);}
    SELECT(1) else SELECT(2) else SELECT(3) else SELECT(4) else SELECT(5)
#undef SELECT
    if(!ck) return 0;
    io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));if(!service) return 0;
    io_connect_t connection=0;kern_return_t status=IOServiceOpen(service,mach_task_self(),0,&connection);IOObjectRelease(service);
    if(status!=KERN_SUCCESS) return 0;
    *cpu=average(connection,ck,cn);*gpu=average(connection,gk,gn);IOServiceClose(connection);
    return (isfinite(*cpu)?1:0)|(isfinite(*gpu)?2:0);
}
