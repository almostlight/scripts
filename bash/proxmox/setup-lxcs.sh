#!/bin/bash

set -u

[[ $EUID -eq 0 ]] || { echo "ERROR: Run as root."; exit 1; }
command -v pct >/dev/null || { echo "ERROR: pct not found."; exit 1; }

SSH_KEYS="$HOME/.ssh/authorized_keys"

[[ -f "$SSH_KEYS" ]] || {
    echo "ERROR: $SSH_KEYS not found."
    exit 1
}

for CTID in $(pct list | awk 'NR>1 && $2=="running" {print $1}'); do
    echo "==> CT $CTID"

    # Make sure required packages are installed
    pct exec "$CTID" -- bash -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y sudo curl
		sudo curl -sSL https://raw.githubusercontent.com/almostlight/headless_debian/setup.sh | sh
    ' || {
        echo "ERROR: CT $CTID package setup failed"
        continue
    }

    # Create/configure admin account
    pct exec "$CTID" -- bash -c '
        if ! id admin >/dev/null 2>&1; then
            useradd -m -s /usr/bin/fish admin
            echo "Created admin account"
        else
            echo "admin already exists"
            usermod -s /usr/bin/fish admin
        fi

        usermod -aG sudo admin

        mkdir -p /home/admin/.ssh
        chown admin:admin /home/admin/.ssh
        chmod 700 /home/admin/.ssh
    '

    # Copy host SSH authorized keys into the container
    pct push "$CTID" "$SSH_KEYS" /home/admin/.ssh/authorized_keys

    pct exec "$CTID" -- bash -c '
        chown admin:admin /home/admin/.ssh/authorized_keys
        chmod 600 /home/admin/.ssh/authorized_keys
    ' || {
        echo "ERROR: CT $CTID SSH key setup failed"
        continue
    }

    echo "==> CT $CTID done"
done

