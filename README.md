# raspberry-pi-kubernetes-cluster

The purpose of this project is to provision a kubernetes cluster on a set of
Raspberry Pi 4B devices. The project is divided into two parts:

- `rpi`: scripts to configure the Raspberry Pi's to be cluster-ready. These
  scripts are meant to be executed on each Raspberry Pi in the cluster, and
  generally will only be run one time at initial cluster setup. As of today,
  there is not an "upgrade" path when changes are made, so it's recommended to
  verify what's changed between releases and re-run the appropriate scripts or
  sections of scripts.
- `k8s`: Kubernetes manifests to deploy services to the cluster. These are
  updated semi-regularly, and can be applied to the cluster at any time.

Each of these parts are described in more detail in their respective subfolders
via README files.

## Prerequisites

- At least two
  [Raspberry Pi 4B](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/)'s,
  ideally 4 or 8 GB models. It's recommended to get the 8 GB model if you plan
  to run additional services beyond what's included in this repo.
- [Raspberry Pi OS - 64 Bit](https://downloads.raspberrypi.org/raspios_lite_arm64/images/)
  freshly cloned to a Micro SD Card
- Static IP Reservations for All RPi's in the Cluster (suggested to be MAC
  Address-based via your DHCP server or router)
- An [ssh key](https://www.ssh.com/academy/ssh/keygen) to simplify login to
  RPi's (this repo is assuming RSA keys with no password)
- [A userconf file on the boot partition to set default password](https://www.raspberrypi.com/news/raspberry-pi-bullseye-update-april-2022/) -
  see the "Headless Setup" section, or see below for non-Linux OS's
- [ssh file on the boot partition](https://www.raspberrypi.com/documentation/computers/configuration.html#ssh-or-ssh-txt)
  to enable remote access on first boot (e.g., `touch /Volumes/boot/ssh` on
  macOS)
- Recommended: a domain name you control (otherwise, .home.arpa will work)

> :warning: **Note:** If you don't have access to a version of `openssl` with
> the `-6` option (such as on macOS), you can use the following command to
> generate the default `pi` username with `raspberry` as the password (though,
> it's recommended to generate a proper username password pair):
>
> ```sh
> echo 'pi:$6$i9XSzPaTyjaCnnKe$fwuKZKF9CYR/vJKVLVusR.NoHQxrj2XSVPK/g7N46RzSaB/9oNmxMXIC3uLIEGV.qg8MYmuJIFAL4ymF4YLeP.' > /Volumes/boot/userconf
> ```

## Resources

- [k3s.rocks](https://k3s.rocks)
