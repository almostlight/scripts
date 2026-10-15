#!/bin/bash

set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "ERROR: Run as root." >&2; exit 1; }
[[ -n "${ADMIN_PUBLIC_KEY:-}" ]] || {
	echo "ERROR: Set ADMIN_PUBLIC_KEY to the admin user's SSH public key." >&2
	exit 1
}

printf '%s\n' "$ADMIN_PUBLIC_KEY" | ssh-keygen -lf - >/dev/null 2>&1 || {
	echo "ERROR: ADMIN_PUBLIC_KEY is not a valid SSH public key." >&2
	exit 1
}

# Script to configure basic system after installation
up_ifs=$(ip -br a | awk '$2 == "UP" {print $1}')
pkgs="fish htop kexec-tools exfatprogs plocate drm-info kbd acpi vim lm-sensors"
# update system
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y
# install software
echo "Installing packages: $pkgs sudo openssh-server"
apt-get install -y $pkgs sudo openssh-server

# create a key-only administrator account
if ! id admin >/dev/null 2>&1; then
	useradd --create-home --shell /usr/bin/fish admin
fi
usermod --shell /usr/bin/fish --append --groups sudo admin
passwd --lock admin >/dev/null

admin_home=$(getent passwd admin | cut -d: -f6)
install -d -o admin -g admin -m 700 "$admin_home/.ssh"
install -o admin -g admin -m 600 /dev/null "$admin_home/.ssh/authorized_keys"
printf '%s\n' "$ADMIN_PUBLIC_KEY" > "$admin_home/.ssh/authorized_keys"

printf '%s\n' 'admin ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/admin
chmod 440 /etc/sudoers.d/admin
visudo --check --file=/etc/sudoers.d/admin

# disable root and password-based SSH authentication
install -d -m 755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-admin-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitEmptyPasswords no
EOF
chmod 644 /etc/ssh/sshd_config.d/99-admin-hardening.conf
sshd -t
systemctl enable --now ssh
systemctl reload ssh

# enable WOL
for i in $up_ifs; do
	if ethtool $i 2>/dev/null | grep -q "Wake-on:.*g"; then
		ethtool -s $i wol g && \
			echo "Wake-on with 'g' is enabled on $i"
	else
		echo "Wake-on with 'g' is NOT enabled on $i"
	fi
done

# housekeeping
apt-get autoremove -y
apt-get autoclean
updatedb &
