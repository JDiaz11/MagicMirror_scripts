#!/bin/bash
#
# cleanup.sh - Reclaim disk space on a MagicMirror install.
#
# Clears apt package cache, trims the systemd journal, clears the npm
# package cache, flushes pm2 logs, and prunes old cached Electron
# binary downloads (keeps the 2 most recent).
#
# On a Raspberry Pi running MagicMirror as a kiosk via pm2, these are
# the most common causes of the SD card filling up over time - none
# of them are needed for MagicMirror to keep running, they're just
# accumulated cache/log cruft from repeated npm installs and updates.
#
# usage: ./cleanup.sh [--dry-run]

USER=`whoami`
HOME_DIR=$(eval echo "~$USER")
MM_DIR="$HOME_DIR/MagicMirror"
DRY_RUN=0

if [ "$1" == "--dry-run" ]; then
  DRY_RUN=1
  echo "dry-run mode, no changes will be made"
fi

if [ ! -d "$MM_DIR" ]; then
  echo "It appears MagicMirror has not been installed on this system."
  echo "(expected to find it at $MM_DIR)"
  exit 1
fi

LOGDIR="$MM_DIR/installers"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/cleanup.log"

run() {
  echo "+ $*" | tee -a "$LOGFILE"
  if [ "$DRY_RUN" == "0" ]; then
    eval "$@" >>"$LOGFILE" 2>&1
  fi
}

echo "cleanup starting - $(date +"%a %b %e %H:%M:%S %Z %Y")" | tee -a "$LOGFILE"

before=$(df -h / | awk 'NR==2{print $4}')

OS=`uname -s`

if [ "$OS" == "Linux" ]; then
  echo "clearing apt package cache..."
  run "sudo apt-get clean"

  if command -v journalctl >/dev/null 2>&1; then
    echo "trimming systemd journal to 50M..."
    run "sudo journalctl --vacuum-size=50M"
  fi
fi

if command -v npm >/dev/null 2>&1; then
  echo "clearing npm cache..."
  run "npm cache clean --force"
fi

if command -v pm2 >/dev/null 2>&1; then
  echo "flushing pm2 logs..."
  run "pm2 flush"
fi

ELECTRON_CACHE="$HOME_DIR/.cache/electron"
if [ -d "$ELECTRON_CACHE" ]; then
  echo "pruning old cached electron downloads (keeping 2 newest)..."
  old_versions=$(find "$ELECTRON_CACHE" -maxdepth 1 -mindepth 1 -type d \
    -exec stat -c '%Y %n' {} \; 2>/dev/null | sort -rn | tail -n +3 | cut -d' ' -f2-)
  if [ -n "$old_versions" ]; then
    while IFS= read -r dir; do
      run "rm -rf \"$dir\""
    done <<< "$old_versions"
  fi
fi

after=$(df -h / | awk 'NR==2{print $4}')

echo "cleanup finished - $(date +"%a %b %e %H:%M:%S %Z %Y")" | tee -a "$LOGFILE"
echo "free space before: $before  after: $after" | tee -a "$LOGFILE"
