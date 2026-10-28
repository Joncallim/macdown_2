#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void path(char *out, size_t cap, const char *dir, const char *leaf) {
    if (snprintf(out, cap, "%s/%s", dir, leaf) >= (int)cap) exit(2);
}

static void put(int fd, const char *bytes) {
    if (write(fd, bytes, strlen(bytes)) != (ssize_t)strlen(bytes)) exit(3);
}

int main(void) {
    char base[] = "/tmp/mt-f14-held-parent-XXXXXX";
    if (!mkdtemp(base)) { perror("mkdtemp"); return 2; }
    char root[PATH_MAX], outside[PATH_MAX], insideDir[PATH_MAX], movedDir[PATH_MAX], movedFile[PATH_MAX];
    path(root, sizeof(root), base, "root");
    path(outside, sizeof(outside), base, "outside");
    path(insideDir, sizeof(insideDir), root, "dir");
    path(movedDir, sizeof(movedDir), outside, "dir");
    path(movedFile, sizeof(movedFile), movedDir, "a.md");
    if (mkdir(root, 0700) || mkdir(outside, 0700) || mkdir(insideDir, 0700)) { perror("mkdir"); return 2; }
    int rootFD = open(root, O_RDONLY | O_DIRECTORY);
    int parentFD = openat(rootFD, "dir", O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    if (rootFD < 0 || parentFD < 0) { perror("open root/parent"); return 2; }
    int fileFD = openat(parentFD, "a.md", O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fileFD < 0) { perror("open original"); return 2; }
    put(fileFD, "before");
    close(fileFD);
    if (rename(insideDir, movedDir) || symlink(movedDir, insideDir)) { perror("move/symlink"); return 2; }
    int stagedFD = openat(parentFD, "staged.md", O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (stagedFD < 0) { perror("stage"); return 2; }
    put(stagedFD, "after");
    close(stagedFD);
    if (renameatx_np(parentFD, "staged.md", parentFD, "a.md", RENAME_SWAP)) {
        perror("held-parent exchange"); return 2;
    }
    int readFD = open(movedFile, O_RDONLY | O_NOFOLLOW);
    char bytes[32] = {0};
    ssize_t count = read(readFD, bytes, sizeof(bytes) - 1);
    if (count < 0) { perror("read result"); return 2; }
    printf("held_parent_swap=%s outside_file=%s\n", count == 5 && strcmp(bytes, "after") == 0 ? "succeeded" : "other", bytes);
    close(readFD);
    close(parentFD);
    close(rootFD);
    char stagedPath[PATH_MAX];
    path(stagedPath, sizeof(stagedPath), movedDir, "staged.md");
    unlink(stagedPath); unlink(movedFile); unlink(insideDir);
    rmdir(movedDir); rmdir(outside); rmdir(root); rmdir(base);
    return count == 5 && strcmp(bytes, "after") == 0 ? 0 : 1;
}
