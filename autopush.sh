#!/bin/bash
# Auto-commit and push changes to GitHub whenever files in this directory change.
# Managed by ~/Library/LaunchAgents/com.edconway.weather-autopush.plist

REPO="/Users/edconway/Developer/Weather"
LOG="$HOME/Library/Logs/weather-autopush.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

log "Watcher started."
cd "$REPO" || { log "ERROR: cannot cd to $REPO"; exit 1; }

# Pull any remote changes first
git pull --rebase --quiet origin main >> "$LOG" 2>&1

/opt/homebrew/bin/fswatch -o --exclude='\.git' --exclude='\.DS_Store' "$REPO" | while read -r _; do
  sleep 2  # brief debounce — wait for rapid saves to settle

  if [ -n "$(git status --porcelain)" ]; then
    git add index.html styles.css app.js charts.js search.js icons.js nuggt-export.js nuggt-config.js nuggt-config.example.js
    MSG="Auto-update: $(date '+%Y-%m-%d %H:%M:%S')"
    git commit -m "$MSG" >> "$LOG" 2>&1 && \
      git push origin main >> "$LOG" 2>&1 && \
      log "Pushed: $MSG" || \
      log "ERROR: push failed (see above)"
  fi
done
