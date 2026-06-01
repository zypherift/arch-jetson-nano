#!/bin/bash

RED="\x1b[1;31m"
GREEN="\x1b[1;32m"
YELLOW="\x1b[1;33m"
CYAN="\x1b[1;36m"
WHITE="\x1b[1;37m"
RESET="\x1b[0m"
# ─────────────────────────────────────────────────────────────────────────────
# root check
# ─────────────────────────────────────────────────────────────────────────────

if ! sudo -v; then
    echo "Root privileges are required."
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# dependency check
# ─────────────────────────────────────────────────────────────────────────────

# detect distro
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# install a package based on distro
install_pkg() {
    local pkg="$1"
    local distro
    distro=$(detect_distro)

    case "$distro" in
        arch|manjaro|endeavouros)
            sudo pacman -S --noconfirm "$pkg" ;;
        ubuntu|debian|linuxmint|pop)
            sudo apt-get install -y "$pkg" ;;
        fedora)
            sudo dnf install -y "$pkg" ;;
        opensuse*|sles)
            sudo zypper install -y "$pkg" ;;
        *)
            echo -e "${RED}unknown distro '$distro', install '$pkg' manually then re-run${RESET}"
            exit 1 ;;
    esac
}

# prompt user to install a missing dep
prompt_install() {
    local pkg="$1"
    local bin="$2"
    echo -e -n "${YELLOW}'${bin}' not found. install '${pkg}' now? (${GREEN}y${WHITE}/${RED}n${WHITE}): "
    read choice
    if [ "$choice" == "y" ]; then
        install_pkg "$pkg"
    else
        echo -e "${RED}can't continue without '${bin}', stopping.${RESET}"
        exit 1
    fi
}

# deps: binary -> package name
declare -A DEPS=(
    [wget]="wget"
    [lsusb]="usbutils"
    [rsync]="rsync"
    [lbzip2]="lbzip2"
    [openssl]="openssl"
)

for bin in "${!DEPS[@]}"; do
    if ! command -v "$bin" &>/dev/null; then
        prompt_install "${DEPS[$bin]}" "$bin"
    fi
done

echo -e "${GREEN}all dependencies satisfied${RESET}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# systemd 256+ dropped linux 4.9 (l4t kernel) support, which causes the
# "failed to mount early api filesystems"
# this snapshot is from 2024-03-01
# ─────────────────────────────────────────────────────────────────────────────
ARCH_ROOTFS_URL="https://web.archive.org/web/20240301120000/http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
ARCH_ROOTFS_FILE="ArchLinuxARM-aarch64-2024-03.tar.gz"

# check if tarballs are already downloaded
if [ ! -f Jetson-210_Linux_R32.7.6_aarch64.tbz2 ]; then
    wget --output-document=Jetson-210_Linux_R32.7.6_aarch64.tbz2 \
        https://developer.nvidia.com/downloads/embedded/l4t/r32_release_v7.6/t210/jetson-210_linux_r32.7.6_aarch64.tbz2
fi

if [ ! -f "$ARCH_ROOTFS_FILE" ]; then
    echo -e "${CYAN}downloading arch arm rootfs from wayback machine...${RESET}"
    wget --output-document="$ARCH_ROOTFS_FILE" "$ARCH_ROOTFS_URL"
fi

# check if directory exists
if [ -d Linux_for_Tegra ]; then
    echo -e -n "${YELLOW}'Linux_for_Tegra' already exists. delete it? (${GREEN}y${WHITE}/${RED}n${WHITE}): "
    read choice
    if [ "$choice" == "y" ]; then
        sudo rm -rf Linux_for_Tegra
    else
        echo -e "${RED}'Linux_for_Tegra' was not deleted, stopping.${RESET}"
        exit 1
    fi
fi

echo -e "${CYAN}extracting jetson and arch linux arm archives...${RESET}"

if [ ! -d Linux_for_Tegra ]; then
    sudo tar jxpf Jetson-210_Linux_R32.7.6_aarch64.tbz2
fi

# ─────────────────────────────────────────────────────────────────────────────
# extract rootfs with sudo so file ownership is preserved as root
# without this systemd refuses to start, it was pretty annoying to find out
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${CYAN}extracting arch arm rootfs (this takes a while)...${RESET}"
sudo tar -xpf "$ARCH_ROOTFS_FILE" -C Linux_for_Tegra/rootfs

echo -e "${GREEN}extracted${WHITE}, modifying nvidia scripts...${RESET}"

# modify apply_binaries.sh
sudo sed -i 's/tar -I lbzip2 -xpmf/tar -I lbzip2 --keep-directory-symlink -xpmf/g' Linux_for_Tegra/apply_binaries.sh

# modify nv_customize_rootfs.sh
sudo sed -i '/ARM_ABI_DIR_ABS="usr\/lib\/aarch64-linux-gnu"/a \ \ \ \ elif [ -d "${LDK_ROOTFS_DIR}\/usr\/lib\/tegra" ]; then\n\ \ \ \ \ \ \ \ ARM_ABI_DIR="${LDK_ROOTFS_DIR}\/usr\/lib"\n' \
    Linux_for_Tegra/nv_tools/scripts/nv_customize_rootfs.sh

# create required folders
mkdir Linux_for_Tegra/nv_tegra/nvidia_drivers \
      Linux_for_Tegra/nv_tegra/config \
      Linux_for_Tegra/nv_tegra/nv_tools \
      Linux_for_Tegra/nv_tegra/nv_sample_apps/nvgstapps

echo -e "${CYAN}extracting nvidia archives...${RESET}"

sudo tar -xpjf Linux_for_Tegra/nv_tegra/nvidia_drivers.tbz2 -C Linux_for_Tegra/nv_tegra/nvidia_drivers/
sudo rm -r Linux_for_Tegra/nv_tegra/nvidia_drivers.tbz2

sudo tar -xpjf Linux_for_Tegra/nv_tegra/config.tbz2 -C Linux_for_Tegra/nv_tegra/config/
sudo rm -r Linux_for_Tegra/nv_tegra/config.tbz2

sudo tar -xpjf Linux_for_Tegra/nv_tegra/nv_tools.tbz2 -C Linux_for_Tegra/nv_tegra/nv_tools/
sudo rm -r Linux_for_Tegra/nv_tegra/nv_tools.tbz2

sudo tar -xpjf Linux_for_Tegra/nv_tegra/nv_sample_apps/nvgstapps.tbz2 -C Linux_for_Tegra/nv_tegra/nv_sample_apps/nvgstapps/
sudo rm -r Linux_for_Tegra/nv_tegra/nv_sample_apps/nvgstapps.tbz2

sudo mv Linux_for_Tegra/nv_tegra/nvidia_drivers/lib/* Linux_for_Tegra/nv_tegra/nvidia_drivers/usr/lib/
sudo rm -r Linux_for_Tegra/nv_tegra/nvidia_drivers/lib/

sudo mv Linux_for_Tegra/nv_tegra/nvidia_drivers/usr/lib/aarch64-linux-gnu/* Linux_for_Tegra/nv_tegra/nvidia_drivers/usr/lib/
sudo rm -r Linux_for_Tegra/nv_tegra/nvidia_drivers/usr/lib/aarch64-linux-gnu/

echo -e "${GREEN}extracted${WHITE}, modifying configs...${RESET}"

sudo sed -i 's/\/usr\/lib\/aarch64-linux-gnu\/tegra\//\/usr\/lib\/tegra\//g' \
    Linux_for_Tegra/nv_tegra/nvidia_drivers/etc/nv_tegra_release

sudo sed -i '$a/usr/lib/tegra-egl' \
    Linux_for_Tegra/nv_tegra/nvidia_drivers/etc/ld.so.conf.d/nvidia-tegra.conf

sudo mv Linux_for_Tegra/nv_tegra/nv_sample_apps/nvgstapps/usr/lib/aarch64-linux-gnu/* \
       Linux_for_Tegra/nv_tegra/nv_sample_apps/nvgstapps/usr/lib/
sudo rm -r Linux_for_Tegra/nv_tegra/nv_sample_apps/nvgstapps/usr/lib/aarch64-linux-gnu/

echo -e "${CYAN}repackaging tegra files...${RESET}"

cd Linux_for_Tegra/nv_tegra/nvidia_drivers && sudo tar -cpjf ../nvidia_drivers.tbz2 *
cd ../config                                && sudo tar -cpjf ../config.tbz2 *
cd ../nv_tools                              && sudo tar -cpjf ../nv_tools.tbz2 *
cd ../nv_sample_apps/nvgstapps             && sudo tar -cpjf ../nvgstapps.tbz2 *
cd ../../../..

echo -e "${CYAN}creating service file and init script...${RESET}"

# ignore linux-aarch64 and systemd in pacman so it doesn't get updated and break things
sudo sed -i 's/^#IgnorePkg\s*=.*/IgnorePkg=linux-aarch64 systemd systemd-libs systemd-sysvcompat mkinitcpio pambase/' \
    Linux_for_Tegra/rootfs/etc/pacman.conf

# create systemd service file
echo '[Unit]
Description=The NVIDIA tegra init script
Before=getty.target systemd-user-sessions.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/nvidia-tegra-init-script

[Install]
WantedBy=multi-user.target' | sudo tee Linux_for_Tegra/rootfs/usr/lib/systemd/system/nvidia-tegra.service > /dev/null

# create first-boot script
sudo tee Linux_for_Tegra/rootfs/usr/local/sbin/first-boot.sh > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

echo "first launch script"
pacman-key --init
pacman-key --populate archlinuxarm

# remove arch kernel and mkinitcpio as they conflict with updates and l4t provides its own kernel
pacman -Rdd --noconfirm linux-aarch64 mkinitcpio 2>/dev/null || true
pacman -Syu --noconfirm --needed sudo
EOF

sudo chmod +x Linux_for_Tegra/rootfs/usr/local/sbin/first-boot.sh

# create first-boot service (runs once on first boot only)
echo '[Unit]
Description=First boot setup
ConditionFirstBoot=yes
Wants=network-online.target
After=network-online.target
Before=getty.target systemd-user-sessions.service

[Service]
Type=oneshot
TimeoutStartSec=0
StandardOutput=journal+console
StandardError=journal+console
ExecStart=/usr/local/sbin/first-boot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target' | sudo tee Linux_for_Tegra/rootfs/usr/lib/systemd/system/first-boot.service > /dev/null

# ensure systemd considers this a first boot
sudo rm -f Linux_for_Tegra/rootfs/etc/machine-id
sudo rm -f Linux_for_Tegra/rootfs/var/lib/dbus/machine-id

# create nvidia-tegra-init-script
sudo tee Linux_for_Tegra/rootfs/usr/bin/nvidia-tegra-init-script > /dev/null <<'EOF'
#!/bin/bash

if [ -e /sys/power/state ]; then
    chmod 0666 /sys/power/state
fi

if [ -e /sys/devices/soc0/family ]; then
    SOCFAMILY="$(cat /sys/devices/soc0/family)"
fi

if [ "$SOCFAMILY" = "Tegra210" ] &&
    [ -e /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq ]; then
    sudo bash -c "echo -n 510000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq"
fi

if [ -d /sys/devices/system/cpu/cpuquiet/tegra_cpuquiet ] ; then
    echo 500 > /sys/devices/system/cpu/cpuquiet/tegra_cpuquiet/down_delay
    echo 1 > /sys/devices/system/cpu/cpuquiet/tegra_cpuquiet/enable
elif [ -w /sys/module/cpu_tegra210/parameters/auto_hotplug ] ; then
    echo 1 > /sys/module/cpu_tegra210/parameters/auto_hotplug
fi

if [ -e /sys/module/cpuidle/parameters/power_down_in_idle ] ; then
    echo "Y" > /sys/module/cpuidle/parameters/power_down_in_idle
elif [ -e /sys/module/cpuidle/parameters/lp2_in_idle ] ; then
    echo "Y" > /sys/module/cpuidle/parameters/lp2_in_idle
fi

if [ -e /sys/block/sda0/queue/read_ahead_kb ]; then
    echo 2048 > /sys/block/sda0/queue/read_ahead_kb
fi
if [ -e /sys/block/sda1/queue/read_ahead_kb ]; then
    echo 2048 > /sys/block/sda1/queue/read_ahead_kb
fi

for uartInst in 0 1 2 3; do
    uartNode="/dev/ttyHS$uartInst"
    if [ -e "$uartNode" ]; then
        ln -s /dev/ttyHS$uartInst /dev/ttyTHS$uartInst
    fi
done

machine=$(cat /sys/devices/soc0/machine)
if [ "${machine}" = "jetson-nano-devkit" ] ; then
    echo 4 > /sys/class/graphics/fb0/blank
    BoardRevision=$(cat /proc/device-tree/chosen/board_info/major_revision)
    if [ "${BoardRevision}" = "A" ] ||
            [ "${BoardRevision}" = "B" ] ||
            [ "${BoardRevision}" = "C" ] ||
            [ "${BoardRevision}" = "D" ]; then
        echo 0 > /sys/devices/platform/tegra-otg/enable_device
        echo 1 > /sys/devices/platform/tegra-otg/enable_host
    fi
fi

if [ -e /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors ]; then
    read governors < /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors
    case $governors in
        *interactive*)
            echo interactive > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
            if [ -e /sys/devices/system/cpu/cpufreq/interactive ] ; then
                echo "1224000" >/sys/devices/system/cpu/cpufreq/interactive/hispeed_freq
                echo "95" >/sys/devices/system/cpu/cpufreq/interactive/target_loads
                echo "20000" >/sys/devices/system/cpu/cpufreq/interactive/min_sample_time
            fi
            ;;
        *)
            ;;
    esac
fi

echo "Success! Exiting!"
exit 0
EOF

sudo chmod +x Linux_for_Tegra/rootfs/usr/bin/nvidia-tegra-init-script

echo -e "${CYAN}applying binaries (apply_binaries.sh)...${RESET}"
cd Linux_for_Tegra
sudo ./apply_binaries.sh --target-overlay | sed 's/^/ /'

echo -e "${CYAN}creating symlinks...${RESET}"

# ─────────────────────────────────────────────────────────────────────────────
# create the /lib -> usr/lib symlink after apply_binaries.sh runs
# doing it before means apply_binaries.sh just messes with it
# also rsync any files from lib/ first before removing it
# ─────────────────────────────────────────────────────────────────────────────
sudo rsync -avxHAX rootfs/lib/ rootfs/usr/lib/
sudo rm -rf rootfs/lib
sudo ln -s usr/lib rootfs/lib

# copy dynamic linker so the kernel can exec /sbin/init
sudo cp rootfs/usr/lib/ld-linux-aarch64.so.1 rootfs/lib/ld-linux-aarch64.so.1

# enable nvidia-tegra service
sudo ln -sr rootfs/usr/lib/systemd/system/nvidia-tegra.service \
            rootfs/etc/systemd/system/sysinit.target.wants/nvidia-tegra.service

# enable first-boot service
sudo ln -sr rootfs/usr/lib/systemd/system/first-boot.service \
            rootfs/etc/systemd/system/multi-user.target.wants/first-boot.service

# ─────────────────────────────────────────────────────────────────────────────
# replace alarm user with jetson-arch
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${CYAN}setting up jetson-arch user and hostname...${RESET}"

ROOTFS="rootfs"

# rename the alarm user entry in /etc/passwd
sudo sed -i \
    's|^alarm:x:1000:1000::/home/alarm:/bin/bash|jetson-arch:x:1000:1000::/home/jetson-arch:/bin/bash|' \
    "$ROOTFS/etc/passwd"

# rename in /etc/shadow
sudo sed -i \
    's|^alarm:|jetson-arch:|' \
    "$ROOTFS/etc/shadow"

# rename the alarm group in /etc/group (group name and member list)
sudo sed -i \
    's|^alarm:x:1000:|jetson-arch:x:1000:|' \
    "$ROOTFS/etc/group"
sudo sed -i \
    's|:alarm$|:jetson-arch|g; s|:alarm,|:jetson-arch,|g; s|,alarm,|,jetson-arch,|g; s|,alarm$|,jetson-arch|g' \
    "$ROOTFS/etc/group"

# same for /etc/gshadow if it exists
if [ -f "$ROOTFS/etc/gshadow" ]; then
    sudo sed -i \
        's|^alarm:|jetson-arch:|' \
        "$ROOTFS/etc/gshadow"
    sudo sed -i \
        's|:alarm$|:jetson-arch|g; s|:alarm,|:jetson-arch,|g' \
        "$ROOTFS/etc/gshadow"
fi

# rename the home directory
if [ -d "$ROOTFS/home/alarm" ]; then
    sudo mv "$ROOTFS/home/alarm" "$ROOTFS/home/jetson-arch"
fi

# set hostname
echo "jetson-arch" | sudo tee "$ROOTFS/etc/hostname" > /dev/null

# add matching hosts
sudo sed -i \
    "s|127\.0\.1\.1.*|127.0.1.1\tjetson-arch|" \
    "$ROOTFS/etc/hosts"
if ! grep -q "127.0.1.1" "$ROOTFS/etc/hosts"; then
    echo -e "127.0.1.1\tjetson-arch" | sudo tee -a "$ROOTFS/etc/hosts" > /dev/null
fi

# ─────────────────────────────────────────────────────────────────────────────
# add jetson-arch to wheel group and enable wheel in sudoers
# user will need to authenticate with their password to use sudo
# ─────────────────────────────────────────────────────────────────────────────

# add jetson-arch to wheel group
# handle both empty wheel (wheel:x:998:) and wheel with existing members
sudo sed -i \
    's|^wheel:x:998:$|wheel:x:998:jetson-arch|; s|^wheel:x:998:\(.\+\)$|wheel:x:998:\1,jetson-arch|' \
    "$ROOTFS/etc/group"

# add explicit sudoers entry for jetson-arch
echo 'jetson-arch ALL=(ALL) ALL' | sudo tee "$ROOTFS/etc/sudoers.d/jetson-arch" > /dev/null
sudo chmod 0440 "$ROOTFS/etc/sudoers.d/jetson-arch"

# ─────────────────────────────────────────────────────────────────────────────
#  pre-set the jetson-arch password
# ─────────────────────────────────────────────────────────────────────────────
HASH=$(openssl passwd -6 "jetson-arch")
sudo sed -i "s|^jetson-arch:[^:]*:|jetson-arch:${HASH}:|" "$ROOTFS/etc/shadow"

# set the root password to match
ROOT_HASH=$(openssl passwd -6 "jetson-arch")
sudo sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" "$ROOTFS/etc/shadow"

# allow root login with password over SSH
sudo sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' "$ROOTFS/etc/ssh/sshd_config"
sudo sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' "$ROOTFS/etc/ssh/sshd_config"

# ─────────────────────────────────────────────────────────────────────────────
# fix ownership - tar without sudo sets files to the current user
# which makes systemd refuse to mount proc/sys/dev
# do this AFTER renaming home dir so it lands under the right path
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${CYAN}fixing rootfs ownership...${RESET}"
sudo chown -R root:root rootfs/
mkdir -p rootfs/home/jetson-arch
sudo chown -R 1000:1000 rootfs/home/jetson-arch

# ─────────────────────────────────────────────────────────────────────────────
# remove INITRD from extlinux.conf - the arch generic initramfs doesn't
# work with the l4t kernel and causes boot to fail
# l4t boots straight into the rootfs anyway, no initrd needed
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${CYAN}removing INITRD from extlinux.conf...${RESET}"
sudo sed -i '/INITRD/d' rootfs/boot/extlinux/extlinux.conf

cd ..

echo ""

# wait for the nano to show up in recovery mode (0955:7f21)
echo -e "${YELLOW}waiting for jetson nano in recovery mode (0955:7f21)...${RESET}"
echo -e "${WHITE}connect the nano via usb now${RESET}"

while ! lsusb | grep -q "0955:7f21"; do
    sleep 1
done

echo -e "${GREEN}device found${WHITE}, flashing...${RESET}"
cd Linux_for_Tegra && sudo ./flash.sh jetson-nano-qspi-sd mmcblk0p1
cd -

echo ""
echo -e "${GREEN}done!"
