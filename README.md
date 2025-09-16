# Streaming Server (Navidrome + Caddy + DuckDNS + optional Tailscale/Autorip)

A complete, ready-to-go music streaming server for Ubuntu. Features automatic SSL certificates, secure file uploads, and optional CD ripping.

## Quick Start (Ready-to-Go Experience)

### Option 1: One-Command Setup
```bash
# Download and run setup script (handles everything)
curl -fsSL <setup-script-url> | bash -s <git-repo-url>
```

### Option 2: Manual Setup
```bash
# Clone and install in one go
git clone <this repo> /opt/streamingserver
cd /opt/streamingserver
sudo ./install.sh
```

The installer will:
- ✅ Automatically create all configuration files
- ✅ Guide you through DuckDNS setup (free dynamic DNS)
- ✅ Install Docker and all dependencies
- ✅ Set up SSL certificates automatically
- ✅ Configure optional features (Tailscale, Autorip)

**All you need:** 
- A DuckDNS account (free at [duckdns.org](https://www.duckdns.org))
- Choose a unique subdomain name (e.g., "mymusic")
- Your DuckDNS token

## What You Get

- 🎵 **Navidrome** - Modern web-based music player
- 📤 **File Upload** - Drag & drop music files via web interface
- 🔒 **SSL/HTTPS** - Automatic certificates via Caddy
- 🌐 **Dynamic DNS** - Access from anywhere via DuckDNS
- 🔐 **Optional Tailscale** - Secure VPN for remote access
- 💿 **Optional Autorip** - Automatic CD ripping when inserted

## DuckDNS Setup

1. **Create Account**: Go to [duckdns.org](https://www.duckdns.org) and sign up (free)
2. **Choose Subdomain**: Pick a unique name like "mymusic" (will become mymusic.duckdns.org)
3. **Get Token**: Copy your token from the DuckDNS control panel
4. **Run Installer**: The installer will prompt for both your subdomain and token

## Manual Configuration (Advanced)

If you prefer to configure manually:
```bash
cp config/*.env.example config/*.env
# edit config files as needed
sudo ./install.sh
```
