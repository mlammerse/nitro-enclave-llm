#!/usr/bin/env bash
# Run ON the EC2 parent (via SSM Run Command as root, or `sudo bash` in a shell).
# Installs the Nitro Enclaves toolchain + Docker, configures the allocator, and
# adds swap (needed so the EIF build of a multi-GB model doesn't OOM-kill linuxkit).
set -e

# Reservation for the enclave. Must be >= the --memory you pass to run-enclave,
# which must be >= ~1.3x the EIF size. 10240 fits a 3B Q4 model with headroom.
ENCLAVE_CPUS="${ENCLAVE_CPUS:-4}"
ENCLAVE_MEM_MIB="${ENCLAVE_MEM_MIB:-10240}"

echo "==> Installing nitro-cli, devel, docker..."
dnf install -y aws-nitro-enclaves-cli aws-nitro-enclaves-cli-devel docker git python3-pip

echo "==> Groups (no-op when running as root; needed for a login user)..."
usermod -aG ne "${SUDO_USER:-$USER}" 2>/dev/null || true
usermod -aG docker "${SUDO_USER:-$USER}" 2>/dev/null || true

echo "==> Configuring enclave allocator: ${ENCLAVE_CPUS} vCPU / ${ENCLAVE_MEM_MIB} MiB"
sed -i "s/^memory_mib:.*/memory_mib: ${ENCLAVE_MEM_MIB}/" /etc/nitro_enclaves/allocator.yaml
sed -i "s/^cpu_count:.*/cpu_count: ${ENCLAVE_CPUS}/"   /etc/nitro_enclaves/allocator.yaml

echo "==> Adding 8G swap (for the EIF build)..."
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 8G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=8192
  chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "==> Enabling services..."
systemctl enable --now docker
systemctl enable --now nitro-enclaves-allocator.service

echo
echo "NOTE: raising the allocator reservation later requires a REBOOT to reserve"
echo "hugepages cleanly (runtime re-reservation fails on memory fragmentation)."
nitro-cli --version || true
free -h
