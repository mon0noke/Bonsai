#include "CBonsai.h"
#include <fts.h>
#include <sys/stat.h>
#include <time.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

static double monotonic(void) {struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (double)t.tv_sec+(double)t.tv_nsec/1e9;}
// Physical traversal: no symbolic link is followed, no working directory changed.
// fts supplies the single lstat snapshot used for read-only allocation accounting.
int bonsai_disk_walk(const char *root,uint64_t max_nodes,double seconds,void *context,bonsai_disk_visit visit) {
    char *copy=strdup(root);if (!copy) return -ENOMEM;
    char *paths[]={copy,NULL};FTS *tree=fts_open(paths,FTS_PHYSICAL|FTS_NOCHDIR,NULL);
    if (!tree) {int e=errno;free(copy);return -e;}
    uint64_t count=0;double deadline=monotonic()+seconds;int result=0;
    FTSENT *entry;
    while (1) {
        errno=0;entry=fts_read(tree);if (!entry) {if (errno) result=-errno;break;}
        if (entry->fts_info==FTS_DP) continue;
        if (count>=max_nodes || monotonic()>deadline) {result=2;break;}
        ++count;
        int error=entry->fts_errno;
        bonsai_disk_node node,*snapshot=NULL;
        if ((entry->fts_info==FTS_D || entry->fts_info==FTS_DNR || entry->fts_info==FTS_F || entry->fts_info==FTS_SL || entry->fts_info==FTS_SLNONE || entry->fts_info==FTS_DEFAULT) && entry->fts_statp) {
            struct stat *s=entry->fts_statp;
            node=(bonsai_disk_node){s->st_dev,s->st_ino,s->st_uid,s->st_mode,s->st_nlink,s->st_size,s->st_mtimespec.tv_sec,s->st_mtimespec.tv_nsec,(uint64_t)(s->st_blocks>0 ? s->st_blocks:0)*512};snapshot=&node;
        }
        if (entry->fts_info==FTS_DNR || entry->fts_info==FTS_ERR || entry->fts_info==FTS_NS) {if (!error) error=EIO;}
        if (visit(context,entry->fts_path,snapshot,error)) {result=1;break;}
    }
    fts_close(tree);free(copy);return result;
}
