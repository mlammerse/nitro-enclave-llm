#!/usr/bin/env bash
# Run ON the EC2 parent (via SSM shell). Installs the Nitro Enclaves toolchain,
# Docker, and configures the enclave resource allocator.
set -euo pipefail

# Resource reservation for the enclave (parent keeps the rest).
ENCLAVE_CPUS="${ENCLAVE_CPUS:-4}"
ENCLAVE_MEM_MIB="${ENCLAVE_MEM_MIB:-8192}"

echo "==> Installing nitro-cli, devel, docker..."
sudo dnf install -y aws-nitro-enclaves-cli aws-nitro-enclaves-cli-devel docker git python3-pip

echo "==> Adding $USER to ne + docker groups..."
sudo usermod -aG ne "$USER"
sudo usermod -aG docker "$USER"

echo "==> Configuring enclave allocator: ${ENCLAVE_CPUS} vCPU / ${ENCLAVE_MEM_MIB} MiB"
sudo sed -i "s/^memory_mib:.*/memory_mib: ${ENCLAVE_MEM_MIB}/" /etc/nitro_enclaves/allocator.yaml
sudo sed -i "s/^cpu_count:.*/cpu_count: ${ENCLAVE_CPUS}/"   /etc/nitro_enclaves/allocator.yaml

echo "==> Enabling services..."
sudo systemctl enable --now docker
sudo systemctl enable --now nitro-enclaves-allocator.service

echo
echo "Setup done. Group membership (ne/docker) needs a fresh login to take effect."
echo "Re-connect via SSM (./01-connect.sh) or run:  newgrp ne"
nitro-cli --version || true
