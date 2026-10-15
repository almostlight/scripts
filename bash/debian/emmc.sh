#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
	echo "This script must be run as root." >&2
	exit 1
fi

EMMC_DEVICES=()
for device in /sys/block/mmcblk[0-9]*; do
	[[ -e "${device}" ]] || continue
	EMMC_DEVICES+=("/dev/$(basename "${device}")")
done

if [[ "${#EMMC_DEVICES[@]}" -eq 0 ]]; then
	echo "No eMMC device detected; skipping storage tuning."
	exit 0
fi

echo "==> Configuring eMMC-backed filesystems"
echo "Detected: ${EMMC_DEVICES[*]}"

if [[ ! -e /etc/fstab.backup-before-emmc ]]; then
	cp /etc/fstab /etc/fstab.backup-before-emmc
fi

awk '
$0 !~ /^[[:space:]]*#/ &&
$3 ~ /^(ext4|ext3|xfs|btrfs)$/ &&
$4 !~ /(^|,)noatime(,|$)/ {
	gsub(/(^|,)relatime(,|$)/, "", $4)
	gsub(/^,|,$/, "", $4)
	gsub(/,,+/, ",", $4)
	if ($4 == "")
		$4 = "noatime"
	else
		$4 = "noatime," $4
}
{ print }
' /etc/fstab > /etc/fstab.new
mv /etc/fstab.new /etc/fstab

if [[ "$(findmnt -no FSTYPE /tmp 2>/dev/null || true)" != "tmpfs" ]] &&
	! awk '$1 !~ /^[[:space:]]*#/ && $2 == "/tmp" && $3 == "tmpfs" { found = 1 } END { exit !found }' /etc/fstab; then
	cat >> /etc/fstab <<'EOF'

# RAM-backed temporary storage
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
EOF
fi

install -d /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/emmc.conf <<'EOF'
[Journal]
SystemMaxUse=50M
SystemMaxFileSize=10M
RuntimeMaxUse=30M
EOF

systemctl restart systemd-journald
if systemctl list-unit-files --type=timer | grep -q '^fstrim.timer'; then
	systemctl enable --now fstrim.timer
else
	echo "fstrim.timer unavailable; skipping."
fi

echo "==> Mounted eMMC filesystems"
findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS |
	while read -r source target fstype options; do
		for device in "${EMMC_DEVICES[@]}"; do
			if [[ "${source}" == "${device}"* ]]; then
				printf '%-18s %-12s %s\n' "${source}" "${target}" "${fstype}"
				break
			fi
		done
	done
