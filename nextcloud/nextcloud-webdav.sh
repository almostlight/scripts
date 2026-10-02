#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/nextcloud-webdav"
CONFIG_FILE="${CONFIG_DIR}/config"
DAVFS_DIR="${HOME}/.davfs2"
SECRETS_FILE="${DAVFS_DIR}/secrets"
readonly DAVFS_CONFIG="/etc/davfs2/davfs2.conf"

NEXTCLOUD_URL=""
NEXTCLOUD_USER=""
NEXTCLOUD_PASSWORD=""

REMOTE_DIRECTORY=""
MOUNT_POINT=""

# ============================================================
# Logging
# ============================================================

log() {
	echo "==> $*"
}

warn() {
	echo "WARNING: $*" >&2
}

die() {
	echo "ERROR: $*" >&2
	exit 1
}

# ============================================================
# Requirements
# ============================================================

require_command() {
	local command_name="${1}"

	if ! command -v "${command_name}" >/dev/null 2>&1; then
		die "Required command not found: ${command_name}"
	fi
}

require_root() {
	if (( EUID != 0 )); then
		die "This operation requires root privileges."
	fi
}

# ============================================================
# Configuration
# ============================================================

load_config() {
	if ! config_is_valid; then
		die "Nextcloud config is missing or corrupted. Run: nextcloud-webdav setup"
	fi

	# shellcheck disable=SC1090
	source "${CONFIG_FILE}"

	if [[ -z "${NEXTCLOUD_URL:-}" ]]; then
		die "NEXTCLOUD_URL is missing from ${CONFIG_FILE}"
	fi

	if [[ -z "${NEXTCLOUD_USER:-}" ]]; then
		die "NEXTCLOUD_USER is missing from ${CONFIG_FILE}"
	fi
}

config_is_valid() {
	[[ -f "${CONFIG_FILE}" && -r "${CONFIG_FILE}" ]] || return 1

	bash -n "${CONFIG_FILE}" >/dev/null 2>&1 || return 1

	(
		unset NEXTCLOUD_URL NEXTCLOUD_USER
		# shellcheck disable=SC1090
		source "${CONFIG_FILE}" >/dev/null 2>&1
		[[ -n "${NEXTCLOUD_URL:-}" && -n "${NEXTCLOUD_USER:-}" ]]
	)
}

save_config() {
	local temporary_file

	mkdir -p -- "${CONFIG_DIR}"
	chmod 700 "${CONFIG_DIR}"

	temporary_file="$(mktemp)"

	printf 'NEXTCLOUD_URL=%q\n' "${NEXTCLOUD_URL}" \
		> "${temporary_file}"

	printf 'NEXTCLOUD_USER=%q\n' "${NEXTCLOUD_USER}" \
		>> "${temporary_file}"

	chmod 600 "${temporary_file}"

	mv -- "${temporary_file}" "${CONFIG_FILE}"
}

load_credentials() {
	local webdav_url
	local secret_line

	webdav_url="$(build_webdav_url)"

	if [[ ! -r "${SECRETS_FILE}" ]]; then
		die "Nextcloud credentials are missing. Run: nextcloud-webdav setup"
	fi

	secret_line="$(awk -v url="${webdav_url}" -v user="${NEXTCLOUD_USER}" \
		'$1 == url && $2 == user { print; exit }' \
		"${SECRETS_FILE}")"

	if [[ -z "${secret_line}" ]]; then
		die "No credentials found for ${webdav_url}. Run: nextcloud-webdav setup"
	fi

	read -r _ _ NEXTCLOUD_PASSWORD _ <<< "${secret_line}"
}

# ============================================================
# URL encoding
# ============================================================

urlencode() {
	local value="${1}"
	local encoded=""
	local character
	local index

	LC_ALL=C

	for (( index = 0; index < ${#value}; index++ )); do
		character="${value:index:1}"

		case "${character}" in
			[a-zA-Z0-9.~_-])
				encoded+="${character}"
				;;

			*)
				printf -v character '%%%02X' "'${character}"
				encoded+="${character}"
				;;
		esac
	done

	printf '%s' "${encoded}"
}

urlencode_path() {
	local path="${1}"
	local encoded=""
	local component

	while [[ "${path}" == */* ]]; do
		component="${path%%/*}"
		path="${path#*/}"

		if [[ -n "${encoded}" ]]; then
			encoded+="/"
		fi

		encoded+="$(urlencode "${component}")"
	done

	if [[ -n "${encoded}" ]]; then
		encoded+="/"
	fi

	encoded+="$(urlencode "${path}")"

	printf '%s' "${encoded}"
}

build_webdav_url() {
	local encoded_user
	local encoded_directory

	encoded_user="$(urlencode "${NEXTCLOUD_USER}")"

	if [[ -n "${REMOTE_DIRECTORY}" ]]; then
		encoded_directory="$(urlencode_path "${REMOTE_DIRECTORY}")"

		printf '%s/remote.php/dav/files/%s/%s/' \
			"${NEXTCLOUD_URL}" \
			"${encoded_user}" \
			"${encoded_directory}"
	else
		printf '%s/remote.php/dav/files/%s/' \
			"${NEXTCLOUD_URL}" \
			"${encoded_user}"
	fi
}

# ============================================================
# Path handling
# ============================================================

normalize_remote_directory() {
	REMOTE_DIRECTORY="${REMOTE_DIRECTORY#/}"
	REMOTE_DIRECTORY="${REMOTE_DIRECTORY%/}"

	if [[ "${REMOTE_DIRECTORY}" == "." ||
		"${REMOTE_DIRECTORY}" == ".." ||
		"${REMOTE_DIRECTORY}" == */../* ||
		"${REMOTE_DIRECTORY}" == ../* ||
		"${REMOTE_DIRECTORY}" == */.. ]]; then
		die "Invalid remote directory: ${REMOTE_DIRECTORY}"
	fi
}

normalize_mount_point() {
	if [[ "${MOUNT_POINT}" == "~/"* ]]; then
		MOUNT_POINT="${HOME}/${MOUNT_POINT#~/}"
	fi

	MOUNT_POINT="${MOUNT_POINT%/}"

	if [[ -z "${MOUNT_POINT}" ]]; then
		die "Mount point cannot be empty."
	fi

	if [[ "${MOUNT_POINT}" == "/" ]]; then
		die "Refusing to use / as a mount point."
	fi
}

# ============================================================
# davfs2 configuration
# ============================================================

configure_davfs() {
	require_root

	if [[ ! -f "${DAVFS_CONFIG}" ]]; then
		die "davfs2 configuration file not found: ${DAVFS_CONFIG}"
	fi

	if grep -qE '^[[:space:]]*use_locks[[:space:]]+' "${DAVFS_CONFIG}"; then
		sed -i \
			's/^[[:space:]]*use_locks[[:space:]]*.*/use_locks 0/' \
			"${DAVFS_CONFIG}"
	else
		printf '\nuse_locks 0\n' >> "${DAVFS_CONFIG}"
	fi
}

configure_secrets() {
	local webdav_url
	local temporary_file

	webdav_url="$(build_webdav_url)"

	mkdir -p -- "${DAVFS_DIR}"
	touch "${SECRETS_FILE}"

	chmod 700 "${DAVFS_DIR}"
	chmod 600 "${SECRETS_FILE}"

	temporary_file="$(mktemp)"

	grep -Fv "${webdav_url} " "${SECRETS_FILE}" \
		> "${temporary_file}" || true

	printf '%s %s %s\n' \
		"${webdav_url}" \
		"${NEXTCLOUD_USER}" \
		"${NEXTCLOUD_PASSWORD}" \
		>> "${temporary_file}"

	chmod 600 "${temporary_file}"

	mv -- "${temporary_file}" "${SECRETS_FILE}"
}

# ============================================================
# Setup
# ============================================================

setup() {
	local real_user
	local real_home

	require_root

	real_user="${SUDO_USER:-}"

	if [[ -z "${real_user}" ]]; then
		real_user="$(logname 2>/dev/null || true)"
	fi

	if [[ -z "${real_user}" || "${real_user}" == "root" ]]; then
		die "Run setup with sudo from a normal user account."
	fi

	real_home="$(getent passwd "${real_user}" | cut -d: -f6)"

	if [[ -z "${real_home}" || ! -d "${real_home}" ]]; then
		die "Could not determine home directory for ${real_user}."
	fi

	HOME="${real_home}"
	CONFIG_DIR="${real_home}/.config/nextcloud-webdav"
	CONFIG_FILE="${CONFIG_DIR}/config"
	DAVFS_DIR="${real_home}/.davfs2"
	SECRETS_FILE="${DAVFS_DIR}/secrets"

	echo
	echo "Nextcloud WebDAV setup"
	echo "======================"
	echo

	if config_is_valid; then
		load_config

		read -r -p \
			"Nextcloud URL [${NEXTCLOUD_URL}]: " \
			input

		if [[ -n "${input}" ]]; then
			NEXTCLOUD_URL="${input}"
		fi

		read -r -p \
			"Nextcloud username [${NEXTCLOUD_USER}]: " \
			input

		if [[ -n "${input}" ]]; then
			NEXTCLOUD_USER="${input}"
		fi
	else
		if [[ -e "${CONFIG_FILE}" ]]; then
			warn "Config is missing or corrupted; creating a new one."
		fi

		NEXTCLOUD_URL=""
		NEXTCLOUD_USER=""

		read -r -p "Nextcloud URL: " NEXTCLOUD_URL
		read -r -p "Nextcloud username: " NEXTCLOUD_USER
	fi

	read -r -s \
		-p "Nextcloud application password: " \
		NEXTCLOUD_PASSWORD

	echo

	NEXTCLOUD_URL="${NEXTCLOUD_URL%/}"

	if [[ -z "${NEXTCLOUD_URL}" ]]; then
		die "Nextcloud URL cannot be empty."
	fi

	if [[ -z "${NEXTCLOUD_USER}" ]]; then
		die "Nextcloud username cannot be empty."
	fi

	if [[ -z "${NEXTCLOUD_PASSWORD}" ]]; then
		die "Application password cannot be empty."
	fi

	save_config

	configure_davfs

	DAVFS_DIR="${real_home}/.davfs2"
	SECRETS_FILE="${DAVFS_DIR}/secrets"

	configure_secrets

	chown -R "${real_user}:${real_user}" \
		"${CONFIG_DIR}" \
		"${DAVFS_DIR}"

	chmod 700 "${CONFIG_DIR}"
	chmod 700 "${DAVFS_DIR}"
	chmod 600 "${CONFIG_FILE}"
	chmod 600 "${SECRETS_FILE}"

	echo
	log "Configuration complete."
}

# ============================================================
# WebDAV requests
# ============================================================

webdav_request() {
	local webdav_url
	local response

	webdav_url="$(build_webdav_url)"

	if ! response="$(curl \
		--silent \
		--show-error \
		--fail \
		--request PROPFIND \
		--header "Depth: 1" \
		--header "Content-Type: application/xml" \
		--user "${NEXTCLOUD_USER}:${NEXTCLOUD_PASSWORD}" \
		--data '<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
	<d:prop>
		<d:resourcetype/>
	</d:prop>
</d:propfind>' \
		"${webdav_url}")"; then
		die "WebDAV request failed. Check the server URL, username, and application password."
	fi

	[[ -n "${response}" ]] || die "WebDAV server returned an empty response."

	printf '%s' "${response}"
}

# ============================================================
# Directory listing
# ============================================================

list_remote_directory() {
	local directory="${1:-}"
	local xml

	load_config

	require_command curl
	require_command python3

	REMOTE_DIRECTORY="${directory}"
	normalize_remote_directory
	load_credentials

	xml="$(webdav_request)"

	python3 -c '
import sys
import urllib.parse
import xml.etree.ElementTree as ET

root = ET.fromstring(sys.stdin.read())

for response in root.findall("{DAV:}response"):
	href = response.findtext("{DAV:}href")

	if not href:
		continue

	resource_type = response.find("{DAV:}propstat/{DAV:}prop/{DAV:}resourcetype")
	is_directory = resource_type is not None and resource_type.find("{DAV:}collection") is not None

	if not is_directory:
		continue

	path = urllib.parse.unquote(
		urllib.parse.urlparse(href).path
	).rstrip("/")

	name = path.split("/")[-1]

	if name:
		print(name)
' <<< "${xml}"
}

# ============================================================
# Mount
# ============================================================

mount_webdav() {
	local webdav_url

	require_root
	load_config

	require_command mount.davfs
	require_command mountpoint

	normalize_remote_directory
	normalize_mount_point

	if mountpoint -q "${MOUNT_POINT}"; then
		die "Already mounted: ${MOUNT_POINT}"
	fi

	mkdir -p -- "${MOUNT_POINT}"

	webdav_url="$(build_webdav_url)"

	log "Mounting ${REMOTE_DIRECTORY:-/}"
	log "	${webdav_url}"
	log "	→ ${MOUNT_POINT}"

	mount.davfs \
		"${webdav_url}" \
		"${MOUNT_POINT}"

	log "Mounted successfully."
}

# ============================================================
# Unmount
# ============================================================

unmount_webdav() {
	require_root

	require_command mountpoint
	require_command umount

	normalize_mount_point

	if ! mountpoint -q "${MOUNT_POINT}"; then
		log "Already unmounted: ${MOUNT_POINT}"
		return
	fi

	log "Unmounting ${MOUNT_POINT}..."

	umount -- "${MOUNT_POINT}"

	log "Unmounted successfully."
}

# ============================================================
# Status
# ============================================================

status() {
	require_command mountpoint

	normalize_mount_point

	if mountpoint -q "${MOUNT_POINT}"; then
		echo "mounted"
	else
		echo "unmounted"
	fi
}

# ============================================================
# Fish completion
# ============================================================

complete_remote() {
	local directory="${1:-}"

	list_remote_directory "${directory}"
}

# ============================================================
# CLI
# ============================================================

usage() {
	cat <<EOF
Usage:
	${0##*/} setup
	${0##*/} list [DIRECTORY]
	${0##*/} mount --remote DIRECTORY --mount PATH
	${0##*/} unmount --mount PATH
	${0##*/} status --mount PATH

Commands:
	setup
		Configure the Nextcloud account and davfs2.

	list [DIRECTORY]
		List remote directories.

	mount
		Mount a remote Nextcloud directory.

	unmount
		Unmount a WebDAV mount.

	status
		Show mount status.

Examples:
	${0##*/} setup

	${0##*/} list

	${0##*/} list "Books"

	${0##*/} mount \\
		--remote "Books/Audiobooks" \\
		--mount "\${HOME}/Nextcloud/Audiobooks"

	${0##*/} unmount \\
		--mount "\${HOME}/Nextcloud/Audiobooks"

	${0##*/} status \\
		--mount "\${HOME}/Nextcloud/Audiobooks"
EOF
}

parse_mount_arguments() {
	local command="${1:-}"

	shift || true

	while (( $# > 0 )); do
		case "${1}" in
			--remote)
				[[ $# -ge 2 ]] ||
					die "--remote requires an argument"

				REMOTE_DIRECTORY="${2}"

				shift 2
				;;

			--mount)
				[[ $# -ge 2 ]] ||
					die "--mount requires an argument"

				MOUNT_POINT="${2}"

				shift 2
				;;

			-h|--help)
				usage
				exit 0
				;;

			*)
				die "Unknown option: ${1}"
				;;
		esac
	done

	case "${command}" in
		mount)
			[[ -n "${REMOTE_DIRECTORY}" ]] ||
				die "mount requires --remote"

			[[ -n "${MOUNT_POINT}" ]] ||
				die "mount requires --mount"
			;;

		unmount|status)
			[[ -n "${MOUNT_POINT}" ]] ||
				die "${command} requires --mount"
			;;
	esac
}

# ============================================================
# Main
# ============================================================

main() {
	local command="${1:-}"

	case "${command}" in
		setup)
			setup
			;;

		list)
			shift
			list_remote_directory "${1:-}"
			;;

		mount)
			parse_mount_arguments "$@"
			mount_webdav
			;;

		unmount)
			parse_mount_arguments "$@"
			unmount_webdav
			;;

		status)
			parse_mount_arguments "$@"
			status
			;;

		__complete-remote)
			shift
			complete_remote "${1:-}"
			;;

		-h|--help|"")
			usage
			;;

		*)
			die "Unknown command: ${command}. Use --help."
			;;
	esac
}

main "$@"
