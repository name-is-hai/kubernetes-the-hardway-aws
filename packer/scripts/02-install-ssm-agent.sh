#!/usr/bin/env bash
set -euo pipefail

if ! command -v amazon-ssm-agent >/dev/null 2>&1; then
  echo "amazon-ssm-agent is not installed on this source AMI" >&2
  exit 1
fi

sudo systemctl enable --now amazon-ssm-agent
sudo systemctl is-enabled --quiet amazon-ssm-agent
sudo systemctl is-active --quiet amazon-ssm-agent
