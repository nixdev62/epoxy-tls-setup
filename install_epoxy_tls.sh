#!/usr/bin/env bash

set -e

echo "=== Epoxy-TLS Auto Installer + Quick Tunnel ==="

# -----------------------------
# 1. Check for dependencies
# -----------------------------

check_dep() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[!] Missing: $1"
        return 1
    else
        echo "[✓] Found: $1"
        return 0
    fi
}

echo "Checking dependencies..."

MISSING=0

check_dep git || MISSING=1
check_dep cargo || MISSING=1
check_dep cloudflared || MISSING=1

# -----------------------------
# 2. Install missing deps
# -----------------------------

if [ "$MISSING" -eq 1 ]; then
    echo "Installing missing dependencies..."

    # Install git
    if ! command -v git >/dev/null 2>&1; then
        echo "Installing git..."
        sudo apt-get update && sudo apt-get install -y git
    fi

    # Install Rust
    if ! command -v cargo >/dev/null 2>&1; then
        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi

    # Install cloudflared
    if ! command -v cloudflared >/dev/null 2>&1; then
        echo "Installing cloudflared..."
        curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
        chmod +x cloudflared
        sudo mv cloudflared /usr/local/bin/
    fi
fi

echo "All dependencies installed."

# -----------------------------
# 3. Clone epoxy-tls
# -----------------------------

if [ ! -d "epoxy-tls" ]; then
    echo "Cloning epoxy-tls..."
    git clone https://github.com/MercuryWorkshop/epoxy-tls.git
else
    echo "epoxy-tls already exists — pulling latest..."
    cd epoxy-tls
    git pull
    cd ..
fi

cd epoxy-tls

# -----------------------------
# 4. Create config.toml
# -----------------------------

CONFIG_FILE="config.toml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating config.toml..."
    cat <<EOF > config.toml
bind = "0.0.0.0:8080"
EOF
else
    echo "config.toml already exists."
fi

# -----------------------------
# 5. Build epoxy-server
# -----------------------------

echo "Building epoxy-server..."
cargo build --release --manifest-path epoxy-server/Cargo.toml

# -----------------------------
# 6. Start epoxy-server
# -----------------------------

echo "Starting Epoxy-TLS server..."
./target/release/epoxy-server ./config.toml &
EPOXY_PID=$!

sleep 2

# -----------------------------
# 7. Start Cloudflare Quick Tunnel
# -----------------------------

echo "Starting Cloudflare Quick Tunnel..."
TUNNEL_URL=$(cloudflared tunnel --url http://localhost:8080 2>&1 | grep -o "https://[-a-z0-9]*\.trycloudflare\.com")

echo ""
echo "==============================================="
echo " Epoxy-TLS is LIVE!"
echo " Wisp URL:"
echo "   wss://$(echo "$TUNNEL_URL" | sed 's/https:\/\//''/')"
echo "==============================================="
echo ""

wait $EPOXY_PID
