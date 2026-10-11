#!/usr/bin/env bash
# scripts/cloud-setup.sh: setup script for Claude Code cloud environments
# (Ubuntu 24.04, runs as root, must finish in under 5 minutes). Installs a
# pinned Swift toolchain if `swift` is missing, then prints `swift --version`.
# Idempotent: a second run with swift on PATH exits right away.
#
# Network hosts it needs (allowlist them in the environment):
#   download.swift.org                              the toolchain tarball (~1.1 GB)
#   archive.ubuntu.com, security.ubuntu.com         apt packages Swift needs
#   (ports.ubuntu.com instead on aarch64)
#
# The tarball's GPG signature is not checked; it comes over HTTPS from
# swift.org. Bump SWIFT_VERSION together with the container tag in
# .github/workflows/ci.yml.
set -euo pipefail

SWIFT_VERSION="6.3.3"
PREFIX="/opt/swift-$SWIFT_VERSION"

link_toolchain() {
  # Link every toolchain binary we don't shadow, so non-login shells find swift.
  local f
  for f in "$PREFIX"/usr/bin/*; do
    [[ -e "/usr/local/bin/$(basename "$f")" ]] || ln -s "$f" /usr/local/bin/
  done
  echo "export PATH=\"$PREFIX/usr/bin:\$PATH\"" > /etc/profile.d/swift.sh
}

if [[ "$(id -u)" != 0 ]]; then
  echo "cloud-setup: run as root (cloud environments do)" >&2
  exit 1
fi

if command -v swift >/dev/null 2>&1; then
  echo "swift already installed"
  swift --version
  exit 0
fi

if [[ ! -x "$PREFIX/usr/bin/swift" ]]; then
  case "$(uname -m)" in
    x86_64)  suffix="" ;;
    aarch64) suffix="-aarch64" ;;
    *) echo "cloud-setup: unsupported arch $(uname -m)" >&2; exit 1 ;;
  esac
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q
  # Runtime deps for the Ubuntu 24.04 toolchain, per swift.org's install guide.
  apt-get install -y -q --no-install-recommends \
    binutils ca-certificates curl git gnupg2 libc6-dev libcurl4-openssl-dev \
    libedit2 libgcc-13-dev libncurses-dev libpython3-dev libsqlite3-0 \
    libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata unzip zlib1g-dev

  url="https://download.swift.org/swift-$SWIFT_VERSION-release/ubuntu2404$suffix/swift-$SWIFT_VERSION-RELEASE/swift-$SWIFT_VERSION-RELEASE-ubuntu24.04$suffix.tar.gz"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "downloading $url"
  curl -fL --retry 3 --retry-delay 2 -o "$tmp/swift.tar.gz" "$url"
  rm -rf "$PREFIX.partial"
  mkdir -p "$PREFIX.partial"
  tar -xzf "$tmp/swift.tar.gz" -C "$PREFIX.partial" --strip-components=1
  rm -rf "$PREFIX"
  mv "$PREFIX.partial" "$PREFIX"   # only a complete extract lands at PREFIX
fi

link_toolchain
export PATH="$PREFIX/usr/bin:$PATH"
swift --version
