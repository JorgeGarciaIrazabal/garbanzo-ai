# Enabling WebGL in WSL2

Flutter web may show `WARNING: Falling back to CPU-only rendering. Reason: webGLVersion is -1` when WebGL isn't available. Try these options:

---

## Option 1: Chrome flags (quick test)

This project includes a Chrome wrapper with WebGL/GPU flags:

```bash
just fe-run-webgl
```

Or manually:
```bash
CHROME_EXECUTABLE="$(pwd)/scripts/chrome-webgl" just fe-run
```

---

## Option 2: WSLg D3D12 (GPU passthrough)

Uses your Windows GPU for OpenGL/WebGL in WSL. Requires Windows 11 and updated drivers.

1. **Install mesa-utils** (to verify):
   ```bash
   sudo apt install mesa-utils
   ```

2. **Create WSLg profile**:
   ```bash
   sudo tee /etc/profile.d/wslg.sh << 'EOF'
   export GALLIUM_DRIVER=d3d12
   
   for i in /mnt/wslg/runtime-dir/*; do
     [ "$XDG_RUNTIME_DIR" = "$HOME" ] && XDG_RUNTIME_DIR="/var/run/user/$UID"
     if [ ! -L "$XDG_RUNTIME_DIR$(basename "$i")" ]; then
       [ -d "$XDG_RUNTIME_DIR$(basename "$i")" ] && rm -r "$XDG_RUNTIME_DIR$(basename "$i")"
       ln -s "$i" "$XDG_RUNTIME_DIR$(basename "$i")"
     fi
   done
   EOF
   ```

3. **Restart WSL** (from PowerShell or CMD):
   ```powershell
   wsl --shutdown
   ```
   Then reopen your WSL terminal.

4. **Verify** (should show D3D12, not llvmpipe):
   ```bash
   glxinfo -B | grep Device
   ```

---

## Option 3: Chrome settings

1. Open `chrome://flags` in Chrome
2. Search for **"Override software rendering list"** → Enable
3. Search for **"WebGL"** → ensure any WebGL options are enabled
4. Open `chrome://settings/system` → enable **"Use hardware acceleration when available"**
5. Restart Chrome completely (all windows)
6. Verify at `chrome://gpu` that WebGL shows as **Enabled**

---

## Option 4: Run from Windows (best performance)

Use Flutter from WSL but open the app in **Windows Chrome**:

1. Start Flutter web server (no browser):
   ```bash
   just fe-run-test-server
   ```

2. In **Windows** (PowerShell or normal CMD), open Chrome and go to:
   ```
   http://localhost:8080
   ```

   WSL shares localhost with Windows, so this works. Windows Chrome has full GPU support.

---

## Prerequisites (all options)

- **Windows**: 10 build 19044+ or Windows 11
- **WSL**: `wsl --update` (run from PowerShell)
- **GPU drivers**: Install latest drivers for NVIDIA/AMD/Intel from the manufacturer

---

## If it still doesn't work

WSL2 GPU graphics support is improving but not perfect. CPU-only rendering is slower but functional for development. For production builds or performance testing, run Flutter/Chrome natively on Windows or Linux.
