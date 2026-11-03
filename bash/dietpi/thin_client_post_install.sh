set -euo pipefail

DISK=/dev/sda          # USB data drive (never the eMMC: /dev/mmcblk0)
PART=${DISK}1
MNT=/mnt/data

step() { echo; echo "== $* =="; }

#------------------------------------------------------------------------------
step "blacklist dw_dmac"
if [ ! -f /etc/modprobe.d/blacklist-dw_dmac.conf ]; then
    printf 'blacklist dw_dmac\nblacklist dw_dmac_core\n' \
        > /etc/modprobe.d/blacklist-dw_dmac.conf
    update-initramfs -u
fi
echo "ok (fixes shutdown/reboot hang after next reboot)"

#------------------------------------------------------------------------------
step "USB data drive -> $MNT"
case "$DISK" in /dev/mmcblk*) echo "refusing to touch the eMMC"; exit 1;; esac

# create one GPT partition spanning the drive, only if there is none
if [ ! -b "$PART" ]; then
    PTTYPE=$(blkid -p -s PTTYPE -o value "$DISK" 2>/dev/null || true)
    if [ -n "$PTTYPE" ]; then
        read -r -p "$DISK has an existing $PTTYPE partition table. Overwrite it? [y/N] " answer
        case "$answer" in
            [yY]|[yY][eE][sS]) ;;
            *) echo "refusing to overwrite the existing partition table"; exit 1 ;;
        esac
    fi
    echo "label: gpt, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4" | sfdisk "$DISK"
    for _ in 1 2 3 4 5; do [ -b "$PART" ] && break; sleep 1; done
fi

# format the partition as ext4 when it is not already ext4
if [ "$(lsblk -fno FSTYPE "$PART")" != ext4 ]; then
    echo "formatting $PART as ext4"
    mkfs.ext4 -qF -L data "$PART"
fi

# stable UUID for fstab (survives replug / device renaming)
UUID=$(blkid -s UUID -o value "$PART")
[ -n "$UUID" ] || { echo "failed to determine UUID for $PART" >&2; exit 1; }

if awk -v mountpoint="$MNT" \
    '$1 !~ /^#/ && $2 == mountpoint { found = 1 } END { exit !found }' /etc/fstab; then
    awk -v mountpoint="$MNT" -v uuid="$UUID" '
        $1 !~ /^#/ && $2 == mountpoint {
            $1 = "UUID=" uuid
            $3 = "ext4"
            n = split($4, o, ","); out = ""; nofail = 0; timeout = 0
            for (i = 1; i <= n; i++) {
                if (o[i] == "") continue
                if (o[i] == "nofail") nofail = 1
                if (o[i] ~ /^x-systemd.device-timeout=/) timeout = 1
                out = out (out ? "," : "") o[i]
            }
            if (!nofail) out = "nofail," out
            if (!timeout) out = out ",x-systemd.device-timeout=5s"
            $4 = out
        }
        { print }
    ' /etc/fstab > /etc/fstab.tmp && mv /etc/fstab.tmp /etc/fstab
else
    echo "UUID=$UUID  $MNT  ext4  nofail,noatime,lazytime,commit=60,x-systemd.device-timeout=5s  0  2" >> /etc/fstab
fi

mount -a
mkdir -p "$MNT/docker" "$MNT/adguardhome" "$MNT/downloads" "$MNT/backups" "$MNT/logs" "$MNT/caddy/storage"
chown -R caddy:caddy "$MNT/caddy"
echo "$MNT -> $(findmnt -no SOURCE "$MNT")"

#------------------------------------------------------------------------------
step "eMMC root: noatime, lazytime, commit=60"
# rewrite the options field of the "/" fstab line; all other options kept
awk '
    $1 !~ /^#/ && $2 == "/" {
        n = split($4, o, ","); out = ""; commit = 0
        for (i = 1; i <= n; i++) {
            if (o[i] == "") continue
            if (o[i] ~ /^commit=/) {
                if (!commit) { out = out (out?",":"") "commit=60"; commit = 1 }
                continue
            }
            out = out (out?",":"") o[i]
        }
        if (!commit) out = out (out?",":"") "commit=60"
        if (out !~ /(^|,)noatime(,|$)/)  out = out ",noatime"
        if (out !~ /(^|,)lazytime(,|$)/) out = out ",lazytime"
        $4 = out
    }
    { print }
' /etc/fstab > /etc/fstab.tmp && mv /etc/fstab.tmp /etc/fstab
mount -o remount,noatime,lazytime,commit=60 /
echo "root opts: $(findmnt -no OPTIONS / | cut -d, -f1-6)"

#------------------------------------------------------------------------------
step "swap: zram instead of eMMC swapfile"
if ! swapon --noheadings 2>/dev/null | grep -q zram; then
    /boot/dietpi/func/dietpi-set_swapfile 0
    /boot/dietpi/func/dietpi-set_swapfile zram
fi
swapon --show

#------------------------------------------------------------------------------
step "RAM logging check"
if [ "$(findmnt -no FSTYPE /var/log 2>/dev/null)" = tmpfs ]; then
    echo "ok: /var/log is tmpfs, no log writes to eMMC"
else
    echo "NOT tmpfs — run: dietpi-software -> Log System -> DietPi-RAMlog #1"
fi

#------------------------------------------------------------------------------
step "Docker: data-root on the USB drive"
if command -v docker >/dev/null; then
    if [ ! -f /etc/docker/daemon.json ]; then
        printf '{ "data-root": "%s/docker", "log-driver": "journald" }\n' "$MNT" \
            > /etc/docker/daemon.json
    elif ! grep -q '"data-root"' /etc/docker/daemon.json; then
        echo "note: daemon.json exists — add \"data-root\": \"$MNT/docker\" to it"
    fi
    if ! docker info 2>/dev/null | grep -q "Docker Root Dir: $MNT/docker"; then
        if [ -d /var/lib/docker ] && [ -n "$(ls -A /var/lib/docker 2>/dev/null)" ]; then
            systemctl stop docker docker.socket 2>/dev/null || true
            cp -a /var/lib/docker/. "$MNT/docker/"
            mv /var/lib/docker /var/lib/docker.emmc-backup
        fi
        systemctl restart docker
        docker info 2>/dev/null | grep -q "Docker Root Dir: $MNT/docker" \
            && rm -rf /var/lib/docker.emmc-backup
    fi
    docker info 2>/dev/null | grep "Docker Root Dir"
else
    echo "docker not installed — skipping"
fi

#------------------------------------------------------------------------------
step "AdGuard Home: data on the USB drive"
AG=/mnt/dietpi_userdata/adguardhome
if [ -d "$AG" ] && [ ! -L "$AG" ]; then
    systemctl stop adguardhome
    mv "$AG" "$MNT/adguardhome"
    ln -s "$MNT/adguardhome" "$AG"
    systemctl start adguardhome
fi
[ -L "$AG" ] && echo "ok: $AG -> $(readlink "$AG")" \
    || echo "adguard not installed — skipping"

#------------------------------------------------------------------------------
step "Tailscale: stop it managing this host's DNS"
if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
    tailscale set --accept-dns=false
    tailscale set --advertise-routes=192.168.1.0/24
    tailscale set --advertise-exit-node=true
    echo "ok: accept-dns off (micro resolves via AdGuard, not via the tunnel)"
else
    echo "tailscale not installed / not logged in — skipping"
fi

# this box resolves through its own AdGuard on loopback.
# (swap for 9.9.9.9 if you want DNS to survive AdGuard being down)
if ss -tln 2>/dev/null | grep -q ':53 '; then
    printf 'nameserver 127.0.0.1\nsearch home\n' > /etc/resolv.conf
    echo "resolv.conf -> 127.0.0.1"
fi

#------------------------------------------------------------------------------
step "weekly TRIM"
systemctl is-enabled fstrim.timer >/dev/null 2>&1 \
    || systemctl enable --now fstrim.timer
echo "fstrim.timer: $(systemctl is-enabled fstrim.timer)"
