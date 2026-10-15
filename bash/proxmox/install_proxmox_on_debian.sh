#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
	echo "This script must be run as root." >&2
	exit 1
fi

if command -v lsb_release >/dev/null 2>&1; then
	DEBIAN_RELEASE="$(lsb_release -cs)"
else
	DEBIAN_RELEASE="$(. /etc/os-release && printf '%s\n' "${VERSION_CODENAME:-}")"
fi

case "${DEBIAN_RELEASE}" in
	bookworm|trixie) ;;
	*)
		echo "Unsupported Debian release: ${DEBIAN_RELEASE:-unknown}" >&2
		exit 1
		;;
esac

apt-get update
apt-get install -y ca-certificates curl

curl -fsSL "https://enterprise.proxmox.com/debian/proxmox-archive-keyring-${DEBIAN_RELEASE}.gpg" \
	-O "/usr/share/keyrings/proxmox-archive-keyring.gpg"
cat > /etc/apt/sources.list.d/pve-install-repo.sources << EOL
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: ${DEBIAN_RELEASE}
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOL

apt-get update
apt-get install -y proxmox-default-kernel proxmox-ve postfix open-iscsi chrony

update-grub

