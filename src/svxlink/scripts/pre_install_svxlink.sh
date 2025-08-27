#!/bin/bash
set -euo pipefail

echo "[INFO] Installing required packages..."
#sudo apt update
#sudo apt install -y \
#  g++ cmake make libsigc++-2.0-dev libgsm1-dev libpopt-dev tcl8.6-dev \
#  libgcrypt20-dev libspeex-dev libasound2-dev libopus-dev librtlsdr-dev \
#  doxygen groff alsa-utils vorbis-tools curl libcurl4-openssl-dev \
#  git rtl-sdr cmake libjsoncpp-dev ladspa-sdk libogg0 libogg-dev \
#  libgpiod-dev libssl-dev

echo "[INFO] Creating system user svxlink (if not exists)..."
if ! id -u svxlink >/dev/null 2>&1; then
  sudo useradd -r -G audio,plugdev,gpio,dialout svxlink
else
  echo "[INFO] User svxlink already exists, skipping."
fi

echo "[INFO] Cloning SvxLink repository..."
cd /opt
if [ ! -d svxlink ]; then
  sudo git clone http://github.com/yo3dgj-L/svxlink.git
else
  echo "[INFO] Repository already exists, skipping."
fi

echo "[INFO] Preparing build directory..."
sudo mkdir -p /opt/svxlink/src/build
cd /opt/svxlink/src/build

echo "[INFO] Running CMake..."
sudo cmake -DUSE_QT=OFF \
  -DCMAKE_INSTALL_PREFIX=/opt/rolink \
  -DSYSCONF_INSTALL_DIR=/opt/rolink \
  -DLOCAL_STATE_DIR=/opt/rolink/var \
  -DWITH_SYSTEMD=ON ..

echo "[INFO] Building..."
sudo make -j"$(nproc)"

echo "[INFO] Building docs..."
sudo make doc

echo "[INFO] Installing..."
sudo make install

echo "[DONE] Pre-installation of SvxLink finished."
