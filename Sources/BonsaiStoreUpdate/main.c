#include <CommonCrypto/CommonDigest.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <libproc.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <spawn.h>
#include <unistd.h>
#include <pwd.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <signal.h>
#include <errno.h>

/* A one-shot update of an existing App Store bundle. No shell, passwords,
 * arbitrary executable, purchase/get command, or persistent privileged service.
 * Owned-app redownload additionally requires an existing matching app receipt.
 * AuthorizationExecuteWithPrivileges preserves the real approving user ID.
 * mas needs SUDO_UID/GID for its Spotlight and Store account operations. */
static int finish(int status) {printf("\nBonsaiStoreExit:%d\n",status);fflush(stdout);return status;}
static int pinned(const char *path) {
 int fd=open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);if(fd<0)return 0;
 struct stat before,after;int ok=fstat(fd,&before)==0 && S_ISREG(before.st_mode) && before.st_size>0 && before.st_size<32*1024*1024;
 CC_SHA256_CTX hash;CC_SHA256_Init(&hash);unsigned char chunk[32768],digest[CC_SHA256_DIGEST_LENGTH];ssize_t n=0;
 while(ok && (n=read(fd,chunk,sizeof(chunk)))>0)CC_SHA256_Update(&hash,chunk,(CC_LONG)n);
 if(n<0)ok=0;CC_SHA256_Final(digest,&hash);
 ok=ok && fstat(fd,&after)==0 && before.st_dev==after.st_dev && before.st_ino==after.st_ino && before.st_size==after.st_size && before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec;
 close(fd);char value[65];for(int i=0;i<32;i++)sprintf(value+i*2,"%02x",digest[i]);
 return ok && strcmp(value,"1a9ec80879b029b67fe3de485203722cfdbee8589fdd70d3bf3c3df59c9f32c9")==0;
}
int main(int argc,char **argv) {
 setvbuf(stdout,NULL,_IONBF,0);dup2(STDOUT_FILENO,STDERR_FILENO);
 if((argc!=2 && argc!=3) || strlen(argv[1])<2 || strlen(argv[1])>255 || !isalnum((unsigned char)argv[1][0])) {puts("Invalid update bundle identifier.");return finish(64);}
 for(const char *p=argv[1];*p;p++)if(!isalnum((unsigned char)*p) && *p!='.' && *p!='_' && *p!='-') {puts("Invalid update bundle identifier.");return finish(64);}
 if(argc==3) {
  char canonicalApp[PROC_PIDPATHINFO_MAXSIZE],receipt[PROC_PIDPATHINFO_MAXSIZE],identifier[256];struct stat st;
  size_t appLength=strlen(argv[2]);
  if(appLength<5 || appLength>3000 || strcmp(argv[2]+appLength-4,".app")!=0 || !realpath(argv[2],canonicalApp) || strcmp(argv[2],canonicalApp)!=0) {puts("Redownload requires a canonical installed application.");return finish(65);}
  snprintf(receipt,sizeof(receipt),"%s/Contents/_MASReceipt/receipt",canonicalApp);
  if(lstat(receipt,&st)!=0 || !S_ISREG(st.st_mode)) {puts("Installed App Store receipt is required.");return finish(65);}
  CFURLRef appURL=CFURLCreateFromFileSystemRepresentation(NULL,(const UInt8 *)canonicalApp,strlen(canonicalApp),true);
  CFBundleRef bundle=appURL ? CFBundleCreate(NULL,appURL):NULL;CFStringRef bundleID=bundle ? CFBundleGetIdentifier(bundle):NULL;
  int valid=bundleID && CFStringGetCString(bundleID,identifier,sizeof(identifier),kCFStringEncodingUTF8) && strcmp(identifier,argv[1])==0;
  if(bundle)CFRelease(bundle);if(appURL)CFRelease(appURL);
  if(!valid) {puts("Installed application identity does not match this update.");return finish(65);}
 }
 uid_t user=getuid();gid_t group=getgid();
 if(geteuid()!=0 || user==0) {puts("Approve this update through Bonsai's macOS authorization sheet.");return finish(77);}
 char own[PROC_PIDPATHINFO_MAXSIZE],canonical[PROC_PIDPATHINFO_MAXSIZE];
 if(proc_pidpath(getpid(),own,sizeof(own))<=0 || !realpath(own,canonical) || strcmp(own,canonical)!=0) {puts("Update helper path is not canonical.");return finish(65);}
 const char *suffix=".app/Contents/Helpers/BonsaiStoreUpdate";size_t length=strlen(own),suffixLength=strlen(suffix);
 if(length<=suffixLength || strcmp(own+length-suffixLength,suffix)!=0) {puts("Update helper must be inside the application bundle.");return finish(65);}
 char *last=strrchr(own,'/');strcpy(last+1,"mas");
 if(!realpath(own,canonical) || strcmp(own,canonical)!=0 || !pinned(own)) {puts("App Store tool integrity check failed.");return finish(65);}
 CFURLRef url=CFURLCreateFromFileSystemRepresentation(NULL,(const UInt8 *)own,strlen(own),false);SecStaticCodeRef code=NULL;
 OSStatus signature=SecStaticCodeCreateWithPath(url,kSecCSDefaultFlags,&code);CFRelease(url);
 if(!signature)signature=SecStaticCodeCheckValidity(code,kSecCSStrictValidate,NULL);if(code)CFRelease(code);
 if(signature) {puts("App Store tool signature check failed.");return finish(65);}
 struct passwd *account=getpwuid(user);if(!account) {puts("Approving user is unavailable.");return finish(65);}
 char uid[32],gid[32];snprintf(uid,sizeof(uid),"SUDO_UID=%u",user);snprintf(gid,sizeof(gid),"SUDO_GID=%u",group);
 char home[PROC_PIDPATHINFO_MAXSIZE],name[256];snprintf(home,sizeof(home),"HOME=%s",account->pw_dir);snprintf(name,sizeof(name),"SUDO_USER=%s",account->pw_name);
 char *environment[]={uid,gid,home,name,"PATH=/usr/bin:/bin:/usr/sbin:/sbin","TMPDIR=/private/tmp","LC_ALL=en_US.UTF-8","MAS_NO_AUTO_INDEX=1",NULL};
 /* Set the real IDs only within this explicitly authorized, short-lived process.
  * mas drops effective IDs back to SUDO_UID/GID to access the user's metadata. */
 if(setgid(0)!=0 || setuid(0)!=0) {puts("Unable to establish authorized update identity.");return finish(77);}
 char *updateArgs[]={own,"update","--force","--bundle",argv[1],"--verbose",NULL};
 char *redownloadArgs[]={own,"install","--force","--bundle",argv[1],NULL};
 char **args=argc==3 ? redownloadArgs:updateArgs;
 posix_spawnattr_t attributes;posix_spawnattr_init(&attributes);posix_spawnattr_setflags(&attributes,POSIX_SPAWN_SETPGROUP);posix_spawnattr_setpgroup(&attributes,0);
 pid_t pid;int result=posix_spawn(&pid,own,NULL,&attributes,args,environment);posix_spawnattr_destroy(&attributes);
 if(result) {printf("Cannot start update tool: %s\n",strerror(result));return finish(70);}
 struct timespec start,now;clock_gettime(CLOCK_MONOTONIC,&start);int status;
 for(;;) {
  pid_t done=waitpid(pid,&status,WNOHANG);if(done==pid)return finish(WIFEXITED(status)?WEXITSTATUS(status):128+WTERMSIG(status));
  if(done<0 && errno!=EINTR) {puts("Update process status unavailable.");return finish(70);}
  clock_gettime(CLOCK_MONOTONIC,&now);
  if(now.tv_sec-start.tv_sec>=590) {kill(-pid,SIGTERM);sleep(1);if(waitpid(pid,&status,WNOHANG)==0){kill(-pid,SIGKILL);waitpid(pid,&status,0);}puts("Update timed out. Apple downloads can continue independently; refresh installed versions before retrying.");return finish(124);}
  struct timespec pause={0,100000000};nanosleep(&pause,NULL);
 }
}
