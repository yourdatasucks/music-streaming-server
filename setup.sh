#!/usr/bin/env bash
set -euo pipefail

# Quick setup script for streaming server
# This script handles the initial clone and runs the installer

REPO_URL="${1:-}"
INSTALL_DIR="/opt/streamingserver"

if [[ -z "$REPO_URL" ]]; then
  echo "Usage: $0 <git-repo-url>"
  echo "Example: $0 https://github.com/yourdatasucks/music-streaming-server.git"
  exit 1
fi

echo "🚀 Setting up Streaming Server..."
echo "Repository: $REPO_URL"
echo "Install directory: $INSTALL_DIR"
echo

# Check if running as root
if [[ $EUID -eq 0 ]]; then
  echo "❌ Don't run this script as root. It will use sudo when needed."
  exit 1
fi

# Check if directory already exists
if [[ -d "$INSTALL_DIR" ]]; then
  echo "⚠️  Directory $INSTALL_DIR already exists."
  read -p "Remove and reinstall? [y/N]: " -r
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo rm -rf "$INSTALL_DIR"
  else
    echo "Aborted."
    exit 1
  fi
fi

echo "📥 Cloning repository..."
sudo git clone "$REPO_URL" "$INSTALL_DIR"

echo "🔧 Running installer..."
cd "$INSTALL_DIR"
sudo ./install.sh

echo
echo "✅ Setup complete! Your streaming server is ready."
echo "Access it at: https://yourdomain.duckdns.org"
