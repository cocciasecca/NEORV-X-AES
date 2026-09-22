#!/bin/bash
set -xe
 
export GIT_TERMINAL_PROMPT=0

apt update
DEBIAN_FRONTEND=noninteractive apt install -y \
    curl \
    git \
    ghdl \
    iverilog \
    jq \
    python3-pip \
    universal-ctags \
    verilator \
    wget
pip3 install \
    cocotb \
    cocotb-test \
    flake8 \
    isort \
    pytest \
    yapf
 
# Verible
ARCH=$(uname -m)
if [[ $ARCH == "aarch64" ]]
then
    ARCH="arm64"
fi
DIST_ID=$(grep DISTRIB_ID /etc/lsb-release | cut -d'=' -f2)
DIST_RELEASE=$(grep RELEASE /etc/lsb-release | cut -d'=' -f2)
DIST_CODENAME=$(grep CODENAME /etc/lsb-release | cut -d'=' -f2)
VERIBLE_RELEASE=$(curl -s -X GET https://api.github.com/repos/chipsalliance/verible/releases/latest | jq -r '.tag_name')
VERIBLE_TAR=verible-$VERIBLE_RELEASE-linux-static-$ARCH.tar.gz
if [[ ! -f $VERIBLE_TAR ]]
then
    wget https://github.com/chipsalliance/verible/releases/download/$VERIBLE_RELEASE/$VERIBLE_TAR
fi
if [[ ! -f "/usr/local/bin/verible-verilog-format" ]]
then
    tar -C /usr/local --strip-components 1 -xf $VERIBLE_TAR
fi
rm $VERIBLE_TAR



if [[ ! -d neorv32-setups ]]
then
# Install neorv32 enviroment
export GIT_TERMINAL_PROMPT=0
git clone --depth 1 https://github.com/stnolting/neorv32-setups.git
cd neorv32-setups
git submodule update --init --recursive --depth 1
cd ..
fi

# adding NEORV-X-AES files
cp -af neorv32-setups_post/. neorv32-setups/
rm -rf neorv32-setups_post

if [[ -f riscv32-gnu-toolchain.tar.gz ]]
then
if [[ ! -d /opt/riscv ]]
then
mkdir /opt/riscv
fi
# extract precompiled toolchain
tar xf riscv32-gnu-toolchain.tar.gz --directory=/opt/riscv
else

# Install standard riscv-gnu-toolchain prebuilt for neorv32
mkdir -p /opt/riscv
wget https://github.com/stnolting/riscv-gcc-prebuilt/releases/download/rv32i-131023/riscv32-unknown-elf.gcc-13.2.0.tar.gz
tar -xzf riscv32-unknown-elf.gcc-13.2.0.tar.gz -C /opt/riscv
rm riscv32-unknown-elf.gcc-13.2.0.tar.gz
fi

# Change riscv-gnu-toolchain RISCV_PREFIX ?= to riscv32-unknown-elf- inside neorv32-setups/neorv32/sw/common/common.mk
sed -i 's/RISCV_PREFIX ?= .*/RISCV_PREFIX ?= riscv32-unknown-elf-/g' neorv32-setups/neorv32/sw/common/common.mk
