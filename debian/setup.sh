#!/usr/bin/env bash
set -euo pipefail

if command -v lsb_release >/dev/null 2>&1; then
	DEBIAN_RELEASE="$(lsb_release -cs)"
else
	DEBIAN_RELEASE="$(. /etc/os-release && printf '%s\n' "${VERSION_CODENAME}")"
fi

if [[ -z "${DEBIAN_RELEASE}" ]]; then
	echo "Unable to determine Debian release." >&2
	exit 1
fi

TMP_DIR="$(mktemp -d)"
ROOT_HOME="/root"
ADMIN_USER="adminer"
CONFIG_REPO="https://github.com/almostlight/headless_debian.git"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

cleanup() {
	rm -rf "${TMP_DIR}"
}

trap cleanup EXIT


if [[ "${EUID}" -ne 0 ]]; then
	echo "This script must be run as root." >&2
	exit 1
fi


export DEBIAN_FRONTEND=noninteractive


echo "==> Configuring APT"

apt-get update
apt-get install -y ca-certificates curl

mkdir -p --mode=0755 /usr/share/keyrings

curl -fsSL \
	https://yazi-rs.github.io/builds/yazi-keyring.gpg \
	-o /usr/share/keyrings/yazi-keyring.gpg

cat > /etc/apt/sources.list.d/yazi.list <<'EOF'
deb [signed-by=/usr/share/keyrings/yazi-keyring.gpg] https://yazi-rs.github.io/builds/ stable main
EOF


curl -fsSL \
	"https://pkgs.tailscale.com/stable/debian/${DEBIAN_RELEASE}.noarmor.gpg" \
	-o /usr/share/keyrings/tailscale-archive-keyring.gpg

curl -fsSL \
	"https://pkgs.tailscale.com/stable/debian/${DEBIAN_RELEASE}.tailscale-keyring.list" \
	-o /etc/apt/sources.list.d/tailscale.list

echo "==> Updating package lists"
apt-get -y update
apt-get -y full-upgrade

echo "==> Installing packages"
apt-get install -y \
	ca-certificates \
	curl \
	fastfetch \
	fish \
	git \
	jq \
	lsb-release \
	sudo \
	openssh-client \
	openssh-server \
	plocate \
	trash-cli \
	tree \
	unzip \
	vim \
	wget \
	yazi \
	zstd

echo "==> Creating ${ADMIN_USER} user"

if ! id -u "${ADMIN_USER}" >/dev/null 2>&1; then
	useradd \
		--create-home \
		--shell /usr/bin/fish \
		"${ADMIN_USER}"
fi

echo "==> Granting ${ADMIN_USER} sudo access"

usermod --append --groups sudo "${ADMIN_USER}"

FISH_SHELL="$(command -v fish)"

if ! grep -Fxq "${FISH_SHELL}" /etc/shells; then
	echo "${FISH_SHELL}" >> /etc/shells
fi


echo "==> Configuring login shell"

usermod --shell "${FISH_SHELL}" root
usermod --shell "${FISH_SHELL}" "${ADMIN_USER}"


echo "==> Cloning configuration repository"

if [[ -d "${SCRIPT_DIR}/home" ]]; then
	cp -a "${SCRIPT_DIR}" "${TMP_DIR}/headless_debian"
else
	git clone \
		--depth 1 \
		"${CONFIG_REPO}" \
		"${TMP_DIR}/headless_debian"
fi

tree "${TMP_DIR}"

CONFIG_DIR="${TMP_DIR}/headless_debian"


echo "==> Configuring root"

install -d \
	-m 700 \
	"${ROOT_HOME}/.config"


if [[ -f "${CONFIG_DIR}/home/.vimrc" ]]; then
	install \
		-o root \
		-g root \
		-m 644 \
		"${CONFIG_DIR}/home/.vimrc" \
		"${ROOT_HOME}/.vimrc"
fi

if [[ -d "${CONFIG_DIR}/home/.config" ]]; then
	cp -a "${CONFIG_DIR}/home/.config/." "${ROOT_HOME}/.config/"
	chown -R root:root "${ROOT_HOME}/.config"
fi


echo "==> Configuring ${ADMIN_USER}"

install -d \
	-o "${ADMIN_USER}" \
	-g "${ADMIN_USER}" \
	-m 700 \
	"/home/${ADMIN_USER}/.config"


if [[ -f "${CONFIG_DIR}/home/.vimrc" ]]; then
	install \
		-o "${ADMIN_USER}" \
		-g "${ADMIN_USER}" \
		-m 644 \
		"${CONFIG_DIR}/home/.vimrc" \
		"/home/${ADMIN_USER}/.vimrc"
fi

if [[ -d "${CONFIG_DIR}/home/.config" ]]; then
	cp -a "${CONFIG_DIR}/home/.config/." "/home/${ADMIN_USER}/.config/"
	chown -R "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/.config"
fi


echo "==> Enabling services"
systemctl enable --now ssh

if [[ -x "${SCRIPT_DIR}/emmc.sh" ]]; then
	"${SCRIPT_DIR}/emmc.sh"
else
	echo "==> eMMC helper not found; skipping storage tuning."
fi


echo "==> Cleaning up"
apt-get autoremove -y
apt-get clean

echo
echo "=========================================="
echo " Debian bootstrap complete"
echo "=========================================="
echo
echo "Hostname: $(hostname)"
echo "Release:  ${DEBIAN_RELEASE}"
echo "Kernel:   $(uname -r)"
echo
echo "Memory:"
free -h
echo
echo "Disk:"
df -h /
echo
echo "Services:"
echo "SSH: $(systemctl is-active ssh)"
echo "A reboot is recommended."
