#!/bin/bash
# MOBA 3v3 PC 端启动器（macOS）
DIR="$(cd "$(dirname "$0")"; pwd)"
cd "$DIR/server"
if ! lsof -ti:8080 >/dev/null 2>&1; then
    nohup node server.js >/dev/null 2>&1 &
    sleep 2
fi
open "http://localhost:8080"
