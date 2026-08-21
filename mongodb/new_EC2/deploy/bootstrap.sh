#!/usr/bin/env bash
# Server-side bootstrap: install Docker Engine + the Compose v2 plugin on a
# fresh box, auto-detecting the distro. Idempotent — safe to re-run.
#
# Supported: Amazon Linux 2023, Ubuntu/Debian, Rocky/RHEL/CentOS/Alma/Fedora.
# Anything else falls back to the official get.docker.com convenience script.
#
# Run as root (deploy.sh calls it with sudo). The login user to grant docker
# access to is taken from $SUDO_USER or $DEPLOY_USER.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

COMPOSE_FALLBACK_VERSION="${COMPOSE_VERSION:-v2.32.4}"
TARGET_USER="${DEPLOY_USER:-${SUDO_USER:-}}"

. /etc/os-release
echo "==> detected: ${PRETTY_NAME:-$ID}"

have_docker() { command -v docker >/dev/null 2>&1; }

install_amazon() {
    dnf -y install docker
}

install_rhel() {
    dnf -y install dnf-plugins-core
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null \
        || dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
    dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_ubuntu() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get -y install ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

if have_docker; then
    echo "==> docker already installed, skipping engine install"
else
    case "$ID" in
        amzn)                              install_amazon ;;
        ubuntu|debian)                     install_ubuntu ;;
        rocky|rhel|centos|almalinux|fedora) install_rhel  ;;
        *)
            echo "==> unknown distro '$ID' — using get.docker.com"
            curl -fsSL https://get.docker.com | sh
            ;;
    esac
fi

systemctl enable --now docker

# Some distro packages (notably Amazon Linux's `docker`) ship without the
# Compose v2 plugin. Install it manually if `docker compose` is missing.
if ! docker compose version >/dev/null 2>&1; then
    echo "==> installing docker compose plugin ${COMPOSE_FALLBACK_VERSION}"
    arch=$(uname -m)
    mkdir -p /usr/libexec/docker/cli-plugins
    curl -fsSL \
        "https://github.com/docker/compose/releases/download/${COMPOSE_FALLBACK_VERSION}/docker-compose-linux-${arch}" \
        -o /usr/libexec/docker/cli-plugins/docker-compose
    chmod +x /usr/libexec/docker/cli-plugins/docker-compose
fi

# Let the login user drive docker without sudo going forward (takes effect on
# next login; deploy.sh still uses sudo for this first run).
if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
    usermod -aG docker "$TARGET_USER" 2>/dev/null || true
fi

# If firewalld is active (common on Rocky/RHEL), open port 80 for the lab.
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=http >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    echo "==> firewalld: opened http (port 80)"
fi

echo "==> docker: $(docker --version)"
echo "==> compose: $(docker compose version | head -1)"
echo "==> bootstrap complete"
