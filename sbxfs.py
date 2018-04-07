#!/usr/bin/env python

# Based on the following resources
# - https://medium.com/the-python-corner/writing-a-fuse-filesystem-in-python-5e0f2de3a813
# - https://gist.github.com/mastro35/0c87b3b96278ef1bd0a6401ff552195e#file-fuse-stavros-py
# - https://gist.github.com/mastro35/9ae0e4f4bbe6bda0c540986cb9f7c47c#file-dfs-py
# - https://github.com/ttsiodras/rsbep-backup/blob/master/contrib/poorZFS.py

from __future__ import with_statement

import os
import sys
import errno
import hashlib

from subprocess import check_output

from fuse import FUSE, FuseOSError, Operations


class SBXContained(Operations):
    def __init__(self, root):
        self.root = root

    # Helpers
    # =======

    def _full_path(self, partial):
        if partial.startswith("/"):
            partial = partial[1:]
        path = os.path.join(self.root, partial)
        return path

    def _cont_path(self, partial):
        return self._full_path(partial) + ".sbxfs.sbx"

    def _cont_exists(self, partial):
        return os.path.exists(self._cont_path(partial))

    def _contain(self, partial):
        full_path = self._full_path(partial)
        cont_path = self._cont_path(partial)
        check_output("rsbx encode --force --sbx-version 17 --rs-data 10 --rs-parity 2 --burst 10 --pv 0 {} {}".format(full_path, cont_path), shell=True)

    def _file_hash(self, partial):
        BUF_SIZE = 65536

        sha256 = hashlib.sha256()

        with open(self._full_path(partial), 'rb') as f:
            while True:
                data = f.read(BUF_SIZE)
                if not data:
                    break
                sha256.update(data)
        return sha256.hexdigest()

    def _repair(self, partial):
        if self._cont_exists(partial):
            full_path = self._full_path(partial)
            cont_path = self._cont_path(partial)

            cont_hash = check_output('rsbx show '+cont_path+' | grep "Hash" | awk \'{ print $5 }\'', shell=True).decode("utf-8").strip("\n")
            file_hash = self._file_hash(partial)
            if cont_hash != file_hash:
                out = check_output('rsbx repair --skip-warning --pv 0 '+cont_path+' | grep "Number of blocks failed" | tr "\n" " " | awk \'{ print $8,$17 }\'', shell=True)
                out = out.split()
                failed_to_process = int(out[0])
                failed_to_repair  = int(out[1])
                if failed_to_process > 0:
                    if failed_to_repair > 0:
                        return FuseOsError(errno.EIO)
                check_output('rsbx decode --force --pv 0 {} {}'.format(cont_path, full_path), shell=True)

    # Filesystem methods
    # ==================

    def access(self, path, mode):
        full_path = self._full_path(path)
        if not os.access(full_path, mode):
            raise FuseOSError(errno.EACCES)

    def chmod(self, path, mode):
        full_path = self._full_path(path)
        os.chmod(full_path, mode)
        if self._cont_exists(path):
            cont_path = self._cont_path(path)
            os.chmod(cont_path, mode)

    def chown(self, path, uid, gid):
        full_path = self._full_path(path)
        os.chown(full_path, uid, gid)
        if self._cont_exists(path):
            cont_path = self._cont_path(path)
            os.chmod(cont_path, mode)

    def getattr(self, path, fh=None):
        full_path = self._full_path(path)
        st = os.lstat(full_path)
        return dict((key, getattr(st, key)) for key in ('st_atime', 'st_ctime',
                     'st_gid', 'st_mode', 'st_mtime', 'st_nlink', 'st_size', 'st_uid'))

    def readdir(self, path, fh):
        full_path = self._full_path(path)

        dirents = ['.', '..']
        if os.path.isdir(full_path):
            dirents.extend(os.listdir(full_path))
        for r in dirents:
            if not r.endswith(".sbxfs.sbx"):
                yield r

    def readlink(self, path):
        pathname = os.readlink(self._full_path(path))
        if pathname.startswith("/"):
            # Path name is absolute, sanitize it.
            return os.path.relpath(pathname, self.root)
        else:
            return pathname

    def mknod(self, path, mode, dev):
        return os.mknod(self._full_path(path), mode, dev)

    def rmdir(self, path):
        full_path = self._full_path(path)
        return os.rmdir(full_path)

    def mkdir(self, path, mode):
        return os.mkdir(self._full_path(path), mode)

    def statfs(self, path):
        full_path = self._full_path(path)
        stv = os.statvfs(full_path)
        return dict((key, getattr(stv, key)) for key in ('f_bavail', 'f_bfree',
            'f_blocks', 'f_bsize', 'f_favail', 'f_ffree', 'f_files', 'f_flag',
            'f_frsize', 'f_namemax'))

    def unlink(self, path):
        if self._cont_exists(path):
            ret = os.unlink(self._cont_path(path))
            if ret != None:
                return ret
        return os.unlink(self._full_path(path))

    def symlink(self, name, target):
        if self._cont_exists(path):
            ret = os.symlink(target+".sbxfs.sbx", self._cont_path(path))
            if ret != None:
                return ret
        return os.symlink(target, self._full_path(name))

    def rename(self, old, new):
        if self._cont_exists(old):
            ret = os.rename(self._cont_path(old), self_cont_path(new))
            if ret != None:
                return ret
        return os.rename(self._full_path(old), self._full_path(new))

    def link(self, target, name):
        if self._cont_exists(old):
            ret = os.link(self._cont_path(name), self_cont_path(target))
            if ret != None:
                return ret
        return os.link(self._full_path(name), self._full_path(target))

    def utimens(self, path, times=None):
        return os.utime(self._full_path(path), times)

    # File methods
    # ============

    def open(self, path, flags):
        ret = self._repair(path)
        #if ret != None:
            #return ret
        full_path = self._full_path(path)
        return os.open(full_path, flags)

    def create(self, path, mode, fi=None):
        full_path = self._full_path(path)
        return os.open(full_path, os.O_WRONLY | os.O_CREAT, mode)

    def read(self, path, length, offset, fh):
        os.lseek(fh, offset, os.SEEK_SET)
        return os.read(fh, length)

    def write(self, path, buf, offset, fh):
        os.lseek(fh, offset, os.SEEK_SET)
        return os.write(fh, buf)

    def truncate(self, path, length, fh=None):
        full_path = self._full_path(path)
        with open(full_path, 'r+') as f:
            f.truncate(length)
        self._contain(path)

    def flush(self, path, fh):
        return os.fsync(fh)

    def release(self, path, fh):
        os.close(fh)
        self._contain(path)

    def fsync(self, path, fdatasync, fh):
        return self.flush(path, fh)

def main(root, mountpoint):
    FUSE(SBXContained(root), mountpoint, nothreads=True, foreground=True)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
