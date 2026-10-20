#include "CBonsai.h"
#include <Security/Authorization.h>
#include <Security/AuthorizationTags.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <poll.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <time.h>

/* Explicit user-triggered, read-only inventory. No caller-supplied command,
 * arguments, environment, file path, password, or persistent privileged helper.
 * This deprecated public API is isolated here until a signed read-only XPC
 * helper can be shipped with Developer ID. No write operation uses this path. */
int bonsai_read_login_inventory(char **output) {
    *output=NULL;
    AuthorizationRef auth=NULL;
    OSStatus status=AuthorizationCreate(NULL,kAuthorizationEmptyEnvironment,kAuthorizationFlagDefaults,&auth);
    if(status!=errAuthorizationSuccess) return (int)status;
    FILE *stream=NULL;char *args[]={"dumpbtm",NULL};
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    status=AuthorizationExecuteWithPrivileges(auth,"/usr/bin/sfltool",kAuthorizationFlagDefaults,args,&stream);
#pragma clang diagnostic pop
    if(status!=errAuthorizationSuccess || !stream) {AuthorizationFree(auth,kAuthorizationFlagDestroyRights);return status ? (int)status : -1;}
    int fd=fileno(stream);fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK);
    const size_t capacity=2*1024*1024;char *buffer=calloc(capacity+1,1);
    if(!buffer) {fclose(stream);AuthorizationFree(auth,kAuthorizationFlagDestroyRights);return -2;}
    size_t used=0;int complete=0;
    /* 150 x 100ms after the authorization sheet closes. The sheet itself is
     * owned by macOS; the person may cancel it without entering credentials. */
    struct timespec started,now;clock_gettime(CLOCK_MONOTONIC,&started);
    for(;;) {
        clock_gettime(CLOCK_MONOTONIC,&now);
        if(used>=capacity || now.tv_sec-started.tv_sec>=15) break;
        struct pollfd p={fd,POLLIN,0};int ready=poll(&p,1,100);
        if(ready<0 && errno!=EINTR) break;
        if(ready>0) {ssize_t n=read(fd,buffer+used,capacity-used);if(n>0) {used+=(size_t)n;}
            else if(n==0) {complete=1;break;} else if(errno!=EAGAIN && errno!=EINTR) break;}
    }
    fclose(stream);AuthorizationFree(auth,kAuthorizationFlagDestroyRights);
    if(!complete || used==0) {free(buffer);return -3;}
    *output=buffer;return 0;
}
void bonsai_free_inventory(char *output) {free(output);}
