#!/usr/bin/env bash
set -euo pipefail

REPO="$HOME/Self-Healing-CICD-Pipeline"
APP_DIR="$REPO/basic_app"
GOOD="$HOME/last-good-sha"
TARGET="${1:-main}"

if [ "$TARGET" = "rollback" ]; then
  [ -f "$GOOD" ] || { echo "no last-good version recorded"; exit 1; }
  TARGET=$(cat "$GOOD")
  echo "ROLLING BACK to $TARGET"
fi

cd "$REPO"
git fetch -q origin
if [ "$TARGET" = "main" ]; then
  git checkout -q main
  git pull -q origin main
else
  git checkout -q "$TARGET"
fi
SHA=$(git rev-parse HEAD)

cd "$APP_DIR"
venv/bin/pip install -q -r requirements.txt

pkill -f '[a]pp.py' || true
sleep 1
APP_ENV="${APP_ENV:-production}" nohup venv/bin/python app.py < /dev/null > /tmp/app.log 2>&1 &

for _ in $(seq 1 10); do
  if curl -fs localhost:5000/health > /dev/null; then
    echo "$SHA" > "$GOOD"
    echo "HEALTHY: $SHA"
    exit 0
  fi
  sleep 2
done
echo "UNHEALTHY: $SHA"
exit 1