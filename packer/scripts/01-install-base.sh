#!/usr/bin/env bash
set -euo pipefail

sudo dnf update -y
sudo dnf install -y \
wget \
tar \
gzip \
unzip \
ca-certificates \
gnupg \
jq \
socat \
conntrack \
ipset \
iptables \
vim
