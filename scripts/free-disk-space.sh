#!/bin/bash
set -euo pipefail

echo "===> Checking current disk space"
df -h

echo "===> Removing large unnecessary directories to free up space"
# Dotnet
sudo rm -rf /usr/share/dotnet
# Android
sudo rm -rf /usr/local/lib/android
# GHC (Haskell)
sudo rm -rf /opt/ghc
# Boost
sudo rm -rf "/usr/local/share/boost"
# CodeQL
sudo rm -rf "$AGENT_TOOLSDIRECTORY"

echo "===> Running Docker system prune"
docker system prune -af

echo "===> Final disk space"
df -h
