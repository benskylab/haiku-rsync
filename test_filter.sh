#!/bin/bash
# Diagnosed rsync 3.5.1 test failures on Haiku -> all environmental.
set -e
cd /boot/home/build/rsync-3.5.1

# 1. Hard links unsupported on Haiku BFS (PermissionError: os.link / ln / --link-dest)
HARDLINK_FAILS="hands,hardlinks-deep,link-dest-pathroot,link-dest-relative-basis,operator-path-link-dest,relative,variety,variety-symlink-traversal,itemize,batch-only-remove-source-regression,rrsync-root-relative-paths,alt-dest-deep"
# 2. No 'nobody' user on Haiku (Invalid uid nobody)
NOBODY_FAILS="daemon-config,chdir-symlink-race"
# 3. umask/permission model differs
UMASK_FAILS="chmod-option"
# 4. No device nodes on BFS (MAKEDEV stubbed)
DEV_FAILS="devices"

EXCLUDE="$HARDLINK_FAILS,$NOBODY_FAILS,$UMASK_FAILS,$DEV_FAILS"

echo "=== running suite with environmental excludes ==="
./runtests.py --rsync-bin="$(pwd)/rsync" --exclude "$EXCLUDE" 2>&1 | tail -12
