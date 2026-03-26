# Garbanzo AI — Development Setup

Complete setup guide for a fresh Linux/WSL2 machine.

---

## 1. System Tools

### just (command runner)
```bash
sudo snap install just --classic
```

### uv (Python package manager)
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
# Then add to PATH (uv installer does this automatically):
source ~/.local/bin/env
```
Requires Python 3.12+.

### Docker
```bash
# Install Docker Engine (WSL2):
sudo apt-get install -y docker.io docker-compose-plugin
sudo service docker start

# Allow running docker without sudo:
sudo usermod -aG docker $USER
# Log out and back in for this to take effect
```
> **WSL2:** Add `sudo service docker start` to your `~/.bashrc` or start it manually before running `just docker-up`.

---

## 2. Flutter & Dart

### Install Flutter SDK
```bash
# Download and extract to ~/flutter
cd ~
git clone https://github.com/flutter/flutter.git -b stable
# or download the archive from https://flutter.dev/docs/get-started/install/linux
```

### Add to PATH (`~/.bashrc`)
```bash
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```
This makes both `flutter` and `dart` available (required for `dart-mcp-server` MCP tool).

### Verify
```bash
flutter doctor
dart --version
```

### Linux Desktop Build Dependencies
```bash
# GStreamer (audio — required for audioplayers + record packages)
sudo apt-get install -y \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad

# LLVM linker (required for Flutter Linux desktop builds)
sudo apt-get install -y lld

# Other Linux desktop Flutter deps
sudo apt-get install -y \
    clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev libstdc++-12-dev
```

Or use the justfile shortcut for GStreamer:
```bash
just dev-deps
```

---

## 3. Node.js / npm

Required for the `chrome-devtools` MCP server (`npx chrome-devtools-mcp`).

```bash
# Install via nvm (recommended):
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install --lts

# Or via apt:
sudo apt-get install -y nodejs npm
```

---

## 4. Ollama (LLM)

```bash
curl -fsSL https://ollama.com/install.sh | sh

# Pull the default model:
ollama pull llama3.2

# Or a larger model:
ollama pull qwen3:8b
```

> On WSL2 with Ollama running on the Windows host, set `OLLAMA_BASE_URL=http://host.docker.internal:11434` in `backend/.env`.

---

## 5. Android (for `just android`)

Only needed if building the Android APK.

### Java (JDK 17)
```bash
sudo apt-get install -y openjdk-17-jdk
```

### Android Studio / SDK
1. Download from [developer.android.com/studio](https://developer.android.com/studio)
2. Install and launch Android Studio
3. Open **SDK Manager** → install:
   - Android SDK (API 34+)
   - Android SDK Build-Tools
   - Android SDK Platform-Tools
4. Set environment variables in `~/.bashrc`:
```bash
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$PATH"
```

### AVD (Android Virtual Device)
1. In Android Studio → **AVD Manager** → Create Virtual Device
2. Pick a Pixel device, API 34, x86_64 image
3. Or via command line:
```bash
avdmanager create avd -n Pixel8 -k "system-images;android-34;google_apis;x86_64"
emulator -avd Pixel8
```

### Accept Android Licenses
```bash
flutter doctor --android-licenses
```

---

## 6. ngrok (for `just android` with remote backend)

```bash
# Install:
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
sudo apt-get update && sudo apt-get install -y ngrok

# Authenticate (get token from ngrok.com):
ngrok config add-authtoken <YOUR_TOKEN>
```

Set `NGROK_DOMAIN=your-domain.ngrok-free.app` in `backend/.env`.

---

## 7. Project Setup

### Clone & configure
```bash
git clone <repo-url>
cd garbanzo-ai

# Copy and edit environment config
cp backend/.env.example backend/.env
# Edit SECRET_KEY, OLLAMA_BASE_URL, TEST_USER_EMAIL/PASSWORD, etc.
```

### Install all dependencies
```bash
just install        # uv sync (backend) + flutter pub get (frontend)
just dev-deps       # GStreamer audio libs (Linux desktop only — run once)
```

### Start PostgreSQL
```bash
just docker-up-db   # PostgreSQL only
# or
just docker-up      # PostgreSQL + Faster Whisper STT
```

### Apply migrations (if any)
```bash
just db-migrate
```

### Start everything
```bash
just dev            # Docker + backend + frontend together
# or separately:
just be-dev         # Backend only (port 8000)
just fe-run         # Flutter Linux desktop
```

---

## 8. Claude Code MCP Servers

The project uses three MCP servers configured in `.mcp.json`:

| Server | Purpose | Requires |
|--------|---------|---------|
| `dart-mcp-server` | Launch/control Flutter app | `dart` in PATH (Flutter SDK) |
| `marionette` | Tap/type/scroll in the running app | `marionette_mcp` in PATH |
| `chrome-devtools` | Browser automation | `node` / `npx` in PATH |

### Install Marionette MCP

```bash
dart pub global activate marionette_mcp

# Add pub-cache bin to PATH (~/.bashrc):
echo 'export PATH="$PATH":"$HOME/.pub-cache/bin"' >> ~/.bashrc
source ~/.bashrc
```

All three servers are auto-started by Claude Code on launch. Run the E2E testing skill with `/e2e-testing` once all are working.

---

## Quick Checklist

```
[ ] just installed
[ ] uv installed, Python 3.12+ available
[ ] Docker running (sudo service docker start in WSL2)
[ ] ~/flutter/bin in PATH (.bashrc)
[ ] dart --version works
[ ] flutter doctor passes (or only Android warnings if not needed)
[ ] GStreamer installed (just dev-deps)
[ ] lld installed (sudo apt-get install -y lld)
[ ] Node.js/npx available
[ ] marionette_mcp activated (dart pub global activate marionette_mcp)
[ ] ~/.pub-cache/bin in PATH (.bashrc)
[ ] Ollama running with at least one model pulled
[ ] backend/.env configured (SECRET_KEY, DATABASE_URL, OLLAMA_BASE_URL)
[ ] just docker-up-db succeeds
[ ] just be-dev starts without errors
[ ] just fe-run opens the app
```
