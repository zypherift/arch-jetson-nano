# Flash script for Arch Linux for the Jetson Nano

Flashes a Jetson Nano (4GB or 2GB) with Arch Linux ARM instead of the stock Ubuntu image.

## What it does

1. Downloads the L4T R32.7.6 BSP from NVIDIA and a an archived Arch ARM rootfs *(see below why)
2. Patches NVIDIA scripts to work with Arch's filesystem layout
3. Repackages NVIDIA GPU/tegra blobs into the rootfs
4. Creates a systemd service for Tegra hardware init
6. Flashes everything to the Nano over USB

* The original script that I forked this from always downloads the latest Arch Arm image.
  There's a huge problem with this, since Systemd dropped kernel support for < 5.10, so on startup, it fails to mount /proc, sys, and dev.
  So, I grabbed an [older Arch Arm image]("https://web.archive.org/web/20240301120000/http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz") from the internet archive, which containes a    supported version of Systemd.
  I'm planning on moving the Tegra kernel to the latest mainline version, but this will take time, for this time here's a quick fix.
  
## Requirements

- Linux host (x86_64)
- `lbzip2`, `rsync`, `wget` 
- Nano connected in **recovery mode** via micro-USB

```bash
# Arch
sudo pacman -S lbzip2 rsync wget

# Ubuntu/Debian
sudo apt install lbzip2 rsync wget
```

## Default credentials

| | |
|---|---|
| Username | `jetson-arch` |
| Password | `jetson-arch` |
| Root password | `jetson-arch` |
| Hostname | `jetson-arch` |

## How to run

1. Put the Nano into recovery mode:
   - You can do this by finding identifying the board revision you have, and shorting out the following two pins:
   ![Recovery Mode Pin Location](https://imgur.com/ZYjVGYM.png)

2. Plug the micro-USB into your host machine

3. Verify the device is detected:
   ```bash
   lsusb | grep NVIDIA
   # Should show: 0955:7f21 NVIDIA Corp. APX
   ```

4. Clone this repo, and run the script:
   ```bash
   git clone https://github.com/zypherift/arch-jetson-nano
   cd arch-jetson-nano
   chmod +x flash-jetson-arch.sh
   ./flash-jetson-arch.sh
   ```

## After boot

Find the IP from your router's DHCP leases, then:

```bash
ssh alarm@<ip-address>
```

And you're basically done here!
