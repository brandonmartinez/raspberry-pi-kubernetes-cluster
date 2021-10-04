# raspberry-pi-kubernetes-cluster

A set of scripts to configure a Raspberry Pi 4 as a Kubernetes cluster.

## OS

Scripts in the `OS` folder are meant to be executed in order. Each script
requires a reboot in-between, thus the need for separate files. Scripts must be
executed with `sudo`, and assume a fresh install of Raspberry Pi OS (64-bit) on
a Raspberry Pi 4B.
