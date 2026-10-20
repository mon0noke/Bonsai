#include "CBonsai.h"
#include "vendor/archive.h"
#include "vendor/archive_entry.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
/* Each directory is opened relative to an owned extraction FD with NOFOLLOW.
 * Links may point inside the archive, but are never traversed while extracting. */
static int safe_name(const char *p) {
 if(!p || !*p || *p=='/' || strlen(p)>4096) return 0;
 const char *s=p;for(;;){const char *e=strchr(s,'/');size_t n=e ? (size_t)(e-s) : strlen(s);if(n==2 && s[0]=='.' && s[1]=='.')return 0;if(!e)break;s=e+1;}return 1;
}
static int safe_link(const char *name,const char *target) {
 if(!target || !*target || *target=='/' || strlen(target)>4096)return 0;
 int depth=0;for(const char *p=name;*p;p++)if(*p=='/')depth++;
 const char *s=target;for(;;){const char *e=strchr(s,'/');size_t n=e?(size_t)(e-s):strlen(s);if(n==2 && s[0]=='.' && s[1]=='.'){if(--depth<0)return 0;}else if(n && !(n==1 && *s=='.'))depth++;if(!e)break;s=e+1;}return 1;
}
int bonsai_extract_update(const char *archive_path,const char *destination) {
 int root=open(destination,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);if(root<0)return -1;
 struct archive *a=archive_read_new();archive_read_support_format_zip(a);archive_read_support_filter_all(a);
 int result=-2,count=0;long long total=0;
 if(archive_read_open_filename(a,archive_path,65536)!=ARCHIVE_OK)goto done;
 struct archive_entry *entry;int status;
 while((status=archive_read_next_header(a,&entry))==ARCHIVE_OK){
  const char *name=archive_entry_pathname(entry);if(!safe_name(name) || ++count>100000 || archive_entry_hardlink(entry))goto done;
  char *copy=strdup(name);if(!copy)goto done;size_t length=strlen(copy);while(length && copy[length-1]=='/')copy[--length]=0;
  if(!length){free(copy);continue;}
  int parent=dup(root);char *save=NULL,*part=strtok_r(copy,"/",&save),*next;int failed=0;
  while(part && (next=strtok_r(NULL,"/",&save))){if(strcmp(part,".")){if(mkdirat(parent,part,0755)<0 && errno!=EEXIST){failed=1;break;}int fd=openat(parent,part,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);close(parent);parent=fd;if(fd<0){failed=1;break;}}part=next;}
  if(failed || !part){if(parent>=0)close(parent);free(copy);goto done;}
  mode_t type=archive_entry_filetype(entry);
  if(type==AE_IFDIR){if(strcmp(part,".") && mkdirat(parent,part,0755)<0 && errno!=EEXIST)failed=1;}
  else if(type==AE_IFLNK){const char *target=archive_entry_symlink(entry);if(!safe_link(name,target) || symlinkat(target,parent,part)<0)failed=1;}
  else if(type==AE_IFREG){
   long long size=archive_entry_size(entry);if(size<0 || size>2147483648LL || total+size>4294967296LL)failed=1;
   else {int fd=openat(parent,part,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,archive_entry_perm(entry)&0755);if(fd<0)failed=1;else {char buffer[65536];ssize_t n;long long written=0;while((n=archive_read_data(a,buffer,sizeof(buffer)))>0){written+=n;if(written>size){failed=1;break;}size_t pos=0;while(pos<(size_t)n){ssize_t w=write(fd,buffer+pos,(size_t)n-pos);if(w<=0){failed=1;break;}pos+=(size_t)w;}if(failed)break;}if(n<0 || written!=size)failed=1;close(fd);total+=written;}}
  }else failed=1;
  close(parent);free(copy);if(failed)goto done;
 }
 if(status==ARCHIVE_EOF)result=0;
 done:archive_read_free(a);close(root);return result;
}
