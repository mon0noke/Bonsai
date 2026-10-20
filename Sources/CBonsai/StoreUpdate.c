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
#include <ctype.h>
#include <time.h>
/* Explicit per-update macOS approval; never accepts a password or shell script.
 * Swift verifies the pinned mas helper before this fixed update-only invocation. */
static int store_action(const char *helper,const char *bundle,const char *app,char **output) {
 *output=NULL;
 if(!helper || !bundle || strlen(bundle)>255 || !strstr(helper,".app/Contents/Helpers/BonsaiStoreUpdate")) return -1;
 for(const char *p=bundle;*p;p++) if(!isalnum((unsigned char)*p) && *p!='.' && *p!='-' && *p!='_') return -1;
 AuthorizationRef auth=NULL;
 OSStatus status=AuthorizationCreate(NULL,kAuthorizationEmptyEnvironment,kAuthorizationFlagDefaults,&auth);
 if(status) return (int)status;
 AuthorizationItem right={kAuthorizationRightExecute,0,NULL,0};
 AuthorizationRights rights={1,&right};
 status=AuthorizationCopyRights(auth,&rights,kAuthorizationEmptyEnvironment,kAuthorizationFlagInteractionAllowed|kAuthorizationFlagExtendRights|kAuthorizationFlagPreAuthorize,NULL);
 if(status) {AuthorizationFree(auth,kAuthorizationFlagDestroyRights);return (int)status;}
 FILE *stream=NULL;char *args[]={(char *)bundle,(char *)app,NULL};
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
 status=AuthorizationExecuteWithPrivileges(auth,helper,kAuthorizationFlagDefaults,args,&stream);
#pragma clang diagnostic pop
 if(status || !stream) {AuthorizationFree(auth,kAuthorizationFlagDestroyRights);return status ? (int)status : -1;}
 int fd=fileno(stream);fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK);
 const size_t capacity=131072;char *buffer=calloc(capacity+1,1);
 if(!buffer) {fclose(stream);AuthorizationFree(auth,kAuthorizationFlagDestroyRights);return -2;}
 size_t used=0;int complete=0;struct timespec started,now;clock_gettime(CLOCK_MONOTONIC,&started);
 for(;;) {
  clock_gettime(CLOCK_MONOTONIC,&now);if(now.tv_sec-started.tv_sec>=600) break;
  struct pollfd p={fd,POLLIN,0};int ready=poll(&p,1,100);
  if(ready<0 && errno!=EINTR) break;
  if(ready>0) {char chunk[4096];ssize_t n=read(fd,chunk,sizeof(chunk));if(n>0) {size_t take=(size_t)n;if(take>capacity-used)take=capacity-used;memcpy(buffer+used,chunk,take);used+=take;}else if(n==0){complete=1;break;}else if(errno!=EAGAIN && errno!=EINTR)break;}
 }
 fclose(stream);AuthorizationFree(auth,kAuthorizationFlagDestroyRights);*output=buffer;
 if(!complete)return -3;
 char *marker=strstr(buffer,"\nBonsaiStoreExit:");
 if(!marker)return -4;
 int childStatus=atoi(marker+strlen("\nBonsaiStoreExit:"));
 return childStatus==0 ? 0 : 50000+childStatus;
}

int bonsai_update_store(const char *helper,const char *bundle,char **output) {return store_action(helper,bundle,NULL,output);}
int bonsai_redownload_store(const char *helper,const char *bundle,const char *app,char **output) {
 if(!app || app[0]!='/' || strlen(app)>3000) {if(output)*output=NULL;return -1;}
 return store_action(helper,bundle,app,output);
}
