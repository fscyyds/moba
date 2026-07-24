#!/bin/bash
# MOBA 3v3 PC 端启动器（macOS）
DIR="$(cd "$(dirname "$0")"; pwd)"
cd "$DIR/server"

# 强制关闭旧进程
kill $(lsof -ti:8080) 2>/dev/null
sleep 1

# 启动服务端
nohup node server.js > server.log 2>&1 &
sleep 2

# 打开浏览器
open "http://localhost:8080"

echo "服务端已启动，浏览器已打开。"
echo "如无法加入，请关闭所有 localhost:8080 标签页后重试。"
