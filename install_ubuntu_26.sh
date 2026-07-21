#!/usr/bin/env bash
#
# install_ubuntu_26.sh — repeatable Ubuntu 26.04 (Resolute) install for the
# Ethon Shield / training teleco stack (UHD + Osmocom 2G + srsRAN 4G + srsRAN 5G SA).
#
# Designed from the Blade LTS port (22.04 → 24.04 → 26.04): gcc-14, Boost 1.83,
# CMAKE_POLICY_VERSION_MINIMUM for UHD, ENABLE_WERROR=OFF, BUILD_TESTS=OFF for 5G.
#
# Usage:
#   ./install_ubuntu_26.sh --dry-run              # print planned actions only
#   sudo ./install_ubuntu_26.sh --deps-only       # apt packages only
#   sudo ./install_ubuntu_26.sh                  # deps + rebuild + install binaries
#   sudo ./install_ubuntu_26.sh --skip-docker    # skip Docker CE / compose plugin
#
# Expects this tree under TRAINING_ROOT (default: directory containing this script):
#   uhd_releases/uhd-4.6.0.0/   (or v4.6.0.0.tar.gz)
#   2g/src/<osmocom components>
#   4g/src/srsRAN_4G/
#   5g_sa/src/srsRAN_Project/
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAINING_ROOT="${TRAINING_ROOT:-$SCRIPT_DIR}"
JOBS="$(nproc 2>/dev/null || echo 4)"
DRY_RUN=0
DEPS_ONLY=0
SKIP_DOCKER=0
SKIP_COMPOSE_PULL=0
SKIP_UHD_IMAGES=0
FORCE_EXTRACT=0

# Ubuntu 26.04 toolchain pins validated on the Blade
export CC="${CC:-gcc-14}"
export CXX="${CXX:-g++-14}"
BOOST_DIR_DEFAULT="/usr/lib/x86_64-linux-gnu/cmake/Boost-1.83.0"
BOOST_DIR="${BOOST_DIR:-$BOOST_DIR_DEFAULT}"

usage() {
  cat <<EOF
install_ubuntu_26.sh — repeatable Ubuntu 26.04 install for the training teleco stack
(UHD 4.6 + Osmocom 2G + srsRAN 4G + srsRAN 5G SA).

Usage:
  ./install_ubuntu_26.sh --dry-run              # print planned actions only
  sudo ./install_ubuntu_26.sh --deps-only       # apt packages only
  sudo ./install_ubuntu_26.sh                   # deps + rebuild + install binaries
  sudo ./install_ubuntu_26.sh --skip-docker     # skip Docker CE + OAI compose pull

Options:
  -h, --help            Show this help
  -n, --dry-run         Print commands; do not change the system
  --deps-only           Install apt dependencies only (no source rebuild)
  --skip-docker         Do not install Docker CE / compose plugin
  --skip-compose-pull   Skip docker compose pull for OAI 5GC images
  --skip-uhd-images     Skip uhd_images_downloader.py after UHD install
  --force-extract       Re-extract .tar/.tar.gz even if source dirs exist
  -j, --jobs N          Parallel make jobs (default: nproc)
  --training-root PATH  Training tree root (default: directory of this script)

Expects under TRAINING_ROOT:
  uhd_releases/uhd-4.6.0.0/ (or v4.6.0.0.tar.gz)
  2g/src/<osmocom components or *.tar>
  4g/src/srsRAN_4G/ (or srsRAN_4G.tar)
  5g_sa/src/srsRAN_Project/ (or srsRAN_Project.tar)

26.04 notes baked in: gcc-14, Boost 1.83, UHD CMAKE_POLICY_VERSION_MINIMUM=3.5,
srsRAN -DENABLE_WERROR=OFF, 5G also -DBUILD_TESTS=OFF.
EOF
}

log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '+ (dry-run) '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  "$@"
}

run_sh() {
  # Run a shell snippet (needed for cd && cmake && make chains)
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '+ (dry-run) bash -c %q\n' "$*"
    return 0
  fi
  printf '+ bash -c %q\n' "$*"
  bash -c "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

check_os() {
  if [[ ! -r /etc/os-release ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      warn "/etc/os-release missing; continuing dry-run for command preview only"
      return 0
    fi
    die "/etc/os-release missing"
  fi
  # shellcheck source=/dev/null
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "26.04" ]]; then
    local msg="This script targets Ubuntu 26.04 (found ID=${ID:-unknown} VERSION_ID=${VERSION_ID:-unknown})"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      warn "$msg — dry-run continues so you can review planned steps"
      return 0
    fi
    die "$msg"
  fi
  log "OS OK: $PRETTY_NAME (codename=${VERSION_CODENAME:-unknown})"
}

require_root_unless_dry() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run as root (sudo) for real installs, or pass --dry-run"
  fi
}

apt_install() {
  local pkgs=("$@")
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "Would apt-get install (${#pkgs[@]} packages): ${pkgs[*]}"
    return 0
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
}

ensure_source_dir() {
  # ensure_source_dir <parent> <dirname> [archive...]
  local parent="$1" dirname="$2"
  shift 2
  local dest="$parent/$dirname"
  if [[ -d "$dest" && "$FORCE_EXTRACT" -eq 0 ]]; then
    log "Using existing source: $dest"
    return 0
  fi
  local archive
  for archive in "$@"; do
    if [[ -f "$parent/$archive" ]]; then
      log "Extracting $parent/$archive"
      run mkdir -p "$parent"
      case "$archive" in
        *.tar.gz|*.tgz) run tar -xzf "$parent/$archive" -C "$parent" ;;
        *.tar.xz)       run tar -xJf "$parent/$archive" -C "$parent" ;;
        *.tar)          run tar -xf  "$parent/$archive" -C "$parent" ;;
        *) die "unsupported archive: $archive" ;;
      esac
      [[ -d "$dest" || "$DRY_RUN" -eq 1 ]] || die "after extract, missing $dest"
      return 0
    fi
  done
  if [[ -d "$dest" ]]; then
    log "Using existing source: $dest"
    return 0
  fi
  die "missing source $dest (and no archive among: $*) under $parent"
}

install_apt_deps() {
  log "=== apt update ==="
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "Would: apt-get update"
  else
    DEBIAN_FRONTEND=noninteractive apt-get update -y
  fi

  log "=== base / tooling ==="
  apt_install \
    ca-certificates curl wget gnupg lsb-release software-properties-common \
    net-tools xterm ethtool inetutils-tools \
    git pkg-config \
    build-essential autoconf automake libtool ccache cmake make \
    gcc g++ gcc-14 g++-14 \
    doxygen cpufrequtils \
    python3 python3-dev python3-pip python3-venv python3-setuptools \
    python3-mako python3-numpy python3-requests python3-scipy python3-ruamel.yaml \
    python3-pytest \
    libusb-1.0-0 libusb-1.0-0-dev \
    libncurses-dev \
    libqmi-utils udhcpc \
    wireshark-common tshark \
    pcscd pcsc-tools python3-pyscard swig libpcsclite-dev

  log "=== Boost 1.83 (UHD on 26.04) + common libs ==="
  # Do NOT install libboost-all-dev on 26.04 — it pulls Boost 1.90 and
  # conflicts with the 1.83 -dev packages UHD 4.6 needs (Boost_DIR).
  apt_install \
    libboost1.83-dev \
    libboost-system1.83-dev \
    libboost-filesystem1.83-dev \
    libboost-thread1.83-dev \
    libboost-chrono1.83-dev \
    libboost-date-time1.83-dev \
    libboost-program-options1.83-dev \
    libboost-serialization1.83-dev \
    libboost-test1.83-dev \
    libboost-regex1.83-dev \
    libboost-atomic1.83-dev \
    libfftw3-dev \
    libmbedtls-dev \
    libconfig++-dev \
    libsctp-dev \
    libyaml-cpp-dev \
    libzmq3-dev \
    libgtest-dev

  log "=== Osmocom / 2G build deps ==="
  # libgnutls28-dev still exists on 26.04; keep name used by Osmocom docs
  apt_install \
    libtalloc-dev shtool \
    libortp-dev libmnl-dev \
    libdbi-dev libdbd-sqlite3 libsqlite3-dev sqlite3 \
    libc-ares-dev libgnutls28-dev \
    dahdi-source || warn "dahdi-source install failed (optional for libosmo-abis); continuing"

  log "=== srsRAN 5G / misc ==="
  apt_install libelf-dev || true

  if [[ "$SKIP_DOCKER" -eq 0 ]]; then
    install_docker
    if [[ "$SKIP_COMPOSE_PULL" -eq 0 ]]; then
      pull_oai_compose_images
    else
      log "Skipping OAI compose image pull (--skip-compose-pull)"
    fi
  else
    log "Skipping Docker (--skip-docker)"
  fi

  log "Toolchain defaults: CC=$CC CXX=$CXX"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    need_cmd "$CC"
    need_cmd "$CXX"
    need_cmd cmake
  else
    log "Would verify $CC / $CXX / cmake exist"
  fi
}

install_docker() {
  log "=== Docker CE + compose plugin ==="
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker + compose already present: $(docker --version 2>/dev/null || true)"
    return 0
  fi

  local codename
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "Would install Docker apt repo for codename=$codename and packages: docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin"
    return 0
  fi

  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" \
    > /etc/apt/sources.list.d/docker.list
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin

  # Allow invoking user to use docker when installed via sudo
  if [[ -n "${SUDO_USER:-}" ]]; then
    usermod -aG docker "$SUDO_USER" || true
    log "Added $SUDO_USER to docker group (re-login required)"
  fi
  docker compose version || warn "docker compose not responding yet"
}

pull_oai_compose_images() {
  local compose="$TRAINING_ROOT/5g_sa/conf/docker-compose-basic-nrf.yaml"
  log "=== OAI 5GC docker compose pull ==="
  if [[ ! -f "$compose" ]]; then
    warn "compose file missing: $compose — skip image pull"
    return 0
  fi
  prepare_oai_compose_layout
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "Would: docker compose -f $compose pull"
    grep -E '^\s+image:' "$compose" 2>/dev/null | sed 's/^/  /' || true
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    warn "docker not found — skip compose pull"
    return 0
  fi
  if docker compose version >/dev/null 2>&1; then
    run docker compose -f "$compose" pull
  elif command -v docker-compose >/dev/null 2>&1; then
    run docker-compose -f "$compose" pull
  else
    warn "docker compose not available — skip OAI image pull"
    return 0
  fi
  log "OAI 5GC images pulled (mysql + oai-* + trf-gen-cn5g)"
}

# Compose file expects ./conf ./database ./healthscripts under 5g_sa/conf/.
# Flat repo layout only ships basic_nrf_config.yaml + oai_db2.sql at the conf root.
prepare_oai_compose_layout() {
  local root="$TRAINING_ROOT/5g_sa/conf"
  local f
  log "=== prepare OAI compose bind-mount layout ==="
  if [[ ! -d "$root" ]]; then
    warn "missing $root"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "Would mkdir -p $root/{conf,database,healthscripts} and link/copy config + DB + healthcheck"
    return 0
  fi

  mkdir -p "$root/conf" "$root/database" "$root/healthscripts"

  # Remove accidental directories Docker created when a missing file was bind-mounted
  for f in \
    "$root/conf/basic_nrf_config.yaml" \
    "$root/database/oai_db2.sql" \
    "$root/healthscripts/mysql-healthcheck2.sh"
  do
    if [[ -d "$f" ]]; then
      warn "removing docker-created directory masquerading as file: $f"
      rm -rf "$f"
    fi
  done

  if [[ -f "$root/basic_nrf_config.yaml" ]]; then
    cp -f "$root/basic_nrf_config.yaml" "$root/conf/basic_nrf_config.yaml"
  else
    warn "missing $root/basic_nrf_config.yaml"
  fi

  if [[ -f "$root/oai_db2.sql" ]]; then
    cp -f "$root/oai_db2.sql" "$root/database/oai_db2.sql"
  else
    warn "missing $root/oai_db2.sql"
  fi

  if [[ ! -f "$root/healthscripts/mysql-healthcheck2.sh" ]]; then
    cat > "$root/healthscripts/mysql-healthcheck2.sh" <<'HC'
#!/bin/bash
mysqladmin ping -h localhost -uroot -plinux --silent
HC
  fi
  chmod +x "$root/healthscripts/mysql-healthcheck2.sh"
  log "OAI compose layout ready under $root"
}

build_uhd() {
  local src parent
  parent="$TRAINING_ROOT/uhd_releases"
  ensure_source_dir "$parent" "uhd-4.6.0.0" "v4.6.0.0.tar.gz" "uhd-4.6.0.0.tar.gz"
  src="$parent/uhd-4.6.0.0/host"
  [[ -d "$src" || "$DRY_RUN" -eq 1 ]] || die "UHD host tree missing: $src"

  log "=== build UHD 4.6.0.0 ==="
  if [[ ! -d "$BOOST_DIR" && "$DRY_RUN" -eq 0 ]]; then
    die "Boost CMake package not found at $BOOST_DIR (install libboost-*-1.83-dev)"
  fi

  run_sh "set -euo pipefail
    cd '$src'
    rm -rf build && mkdir build && cd build
    cmake \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DBoost_DIR='$BOOST_DIR' \
      -DCMAKE_C_COMPILER='$CC' \
      -DCMAKE_CXX_COMPILER='$CXX' \
      ..
    make -j$JOBS
    make install
    ldconfig
  "

  if [[ "$SKIP_UHD_IMAGES" -eq 0 ]]; then
    log "=== UHD FPGA/firmware images ==="
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "Would run: /usr/local/lib/uhd/utils/uhd_images_downloader.py"
    else
      if [[ -x /usr/local/lib/uhd/utils/uhd_images_downloader.py ]]; then
        python3 /usr/local/lib/uhd/utils/uhd_images_downloader.py || warn "uhd_images_downloader failed"
      else
        warn "uhd_images_downloader.py not found after install"
      fi
    fi
  fi
}

build_srsran_4g() {
  local parent src
  parent="$TRAINING_ROOT/4g/src"
  ensure_source_dir "$parent" "srsRAN_4G" "srsRAN_4G.tar" "srsRAN_4G.tar.gz"
  src="$parent/srsRAN_4G"

  log "=== build srsRAN 4G ==="
  run_sh "set -euo pipefail
    cd '$src'
    rm -rf build && mkdir build && cd build
    cmake \
      -DENABLE_WERROR=OFF \
      -DCMAKE_C_COMPILER='$CC' \
      -DCMAKE_CXX_COMPILER='$CXX' \
      ..
    make -j$JOBS
    make install
    ldconfig
  "
}

build_autotools() {
  local dir="$1"
  shift
  local extra=("$@")
  local src="$TRAINING_ROOT/2g/src/$dir"
  [[ -d "$src" || "$DRY_RUN" -eq 1 ]] || die "missing $src"

  log "=== build $dir ==="
  local conf_args=""
  local a
  for a in "${extra[@]+"${extra[@]}"}"; do
    conf_args+=" $(printf '%q' "$a")"
  done

  run_sh "set -euo pipefail
    cd '$src'
    export CC='$CC' CXX='$CXX'
    if [[ -f Makefile ]]; then make distclean >/dev/null 2>&1 || true; fi
    autoreconf -fi
    ./configure $conf_args
    make -j$JOBS
    make install
    ldconfig
  "
}

build_osmocom_2g() {
  local parent="$TRAINING_ROOT/2g/src"
  [[ -d "$parent" || "$DRY_RUN" -eq 1 ]] || die "missing $parent"

  # Extract tarballs when only archives are present
  local name
  for name in libosmocore libosmo-netif libosmo-abis libosmo-sigtran libsmpp34 \
              osmo-bts osmo-trx osmo-hlr osmo-mgw osmo-msc osmo-bsc \
              osmo-ggsn osmo-sgsn osmo-pcu liburing; do
    if [[ ! -d "$parent/$name" ]]; then
      if [[ -f "$parent/${name}.tar" ]]; then
        ensure_source_dir "$parent" "$name" "${name}.tar"
      elif [[ -f "$parent/${name}.tar.gz" ]]; then
        ensure_source_dir "$parent" "$name" "${name}.tar.gz"
      fi
    fi
  done

  # liburing optional / different build system
  if [[ -d "$parent/liburing" ]]; then
    log "=== build liburing ==="
    run_sh "set -euo pipefail
      cd '$parent/liburing'
      ./configure
      make -j$JOBS
      make install
      ldconfig
    "
  fi

  build_autotools libosmocore
  build_autotools libosmo-netif
  build_autotools libosmo-abis
  build_autotools libosmo-sigtran
  build_autotools libsmpp34
  build_autotools osmo-bts --enable-trx
  build_autotools osmo-trx --with-uhd
  build_autotools osmo-hlr
  build_autotools osmo-mgw
  build_autotools osmo-msc
  build_autotools osmo-bsc

  # GPRS extras when present
  if [[ -d "$parent/osmo-ggsn" ]]; then build_autotools osmo-ggsn; fi
  if [[ -d "$parent/osmo-sgsn" ]]; then build_autotools osmo-sgsn; fi
  if [[ -d "$parent/osmo-pcu" ]]; then build_autotools osmo-pcu; fi
}

build_srsran_5g() {
  local parent src
  parent="$TRAINING_ROOT/5g_sa/src"
  ensure_source_dir "$parent" "srsRAN_Project" "srsRAN_Project.tar" "srsRAN_Project.tar.gz"
  src="$parent/srsRAN_Project"

  log "=== build srsRAN Project (5G SA) ==="
  # WERROR off: GCC 14/15 template-id-cdtor in coroutine headers
  # BUILD_TESTS off: system gtest needs C++17; project still defaults to C++14
  run_sh "set -euo pipefail
    cd '$src'
    rm -rf build && mkdir build && cd build
    cmake \
      -DENABLE_WERROR=OFF \
      -DBUILD_TESTS=OFF \
      -DCMAKE_C_COMPILER='$CC' \
      -DCMAKE_CXX_COMPILER='$CXX' \
      ..
    make -j$JOBS
    make install
    ldconfig
  "
}

verify_install() {
  log "=== verify binaries ==="
  local bins=(
    uhd_find_devices
    uhd_usrp_probe
    srsenb
    srsepc
    gnb
    osmo-bts-trx
    osmo-trx-uhd
    osmo-bsc
    osmo-msc
    osmo-hlr
  )
  local b missing=0
  for b in "${bins[@]}"; do
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "Would check: command -v $b"
      continue
    fi
    if command -v "$b" >/dev/null 2>&1; then
      log "OK  $b -> $(command -v "$b")"
    else
      warn "MISSING $b"
      missing=1
    fi
  done

  if [[ "$DRY_RUN" -eq 0 ]]; then
    log "Quick versions:"
    uhd_find_devices 2>&1 | head -2 || true
    srsenb --version 2>&1 | head -1 || true
    gnb --version 2>&1 | head -1 || true
    osmo-bts-trx --version 2>&1 | head -1 || true
    osmo-trx-uhd --version 2>&1 | head -1 || true
  fi

  if [[ "$missing" -ne 0 && "$DRY_RUN" -eq 0 ]]; then
    die "one or more expected binaries are missing"
  fi
}

run_pytest_hint() {
  log "=== post-install checks (optional) ==="
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "Would: cd $TRAINING_ROOT && python3 -m pytest tests/ -q"
    log "Would: cd $TRAINING_ROOT && python3 -m upgrade.report --target 26.04"
    return 0
  fi
  if [[ -d "$TRAINING_ROOT/tests" ]]; then
    (cd "$TRAINING_ROOT" && python3 -m pytest tests/ -q) || warn "pytest reported failures"
    (cd "$TRAINING_ROOT" && python3 -m upgrade.report --target 26.04) || warn "upgrade.report reported issues"
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -n|--dry-run) DRY_RUN=1; shift ;;
      --deps-only) DEPS_ONLY=1; shift ;;
      --skip-docker) SKIP_DOCKER=1; shift ;;
      --skip-compose-pull) SKIP_COMPOSE_PULL=1; shift ;;
      --skip-uhd-images) SKIP_UHD_IMAGES=1; shift ;;
      --force-extract) FORCE_EXTRACT=1; shift ;;
      -j|--jobs) JOBS="$2"; shift 2 ;;
      --training-root) TRAINING_ROOT="$2"; shift 2 ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
  done

  TRAINING_ROOT="$(cd "$TRAINING_ROOT" && pwd)"
  log "TRAINING_ROOT=$TRAINING_ROOT"
  log "DRY_RUN=$DRY_RUN DEPS_ONLY=$DEPS_ONLY JOBS=$JOBS CC=$CC CXX=$CXX"
  log "BOOST_DIR=$BOOST_DIR"

  check_os
  require_root_unless_dry

  install_apt_deps

  if [[ "$DEPS_ONLY" -eq 1 ]]; then
    log "Deps-only mode complete."
    exit 0
  fi

  build_uhd
  build_srsran_4g
  build_osmocom_2g
  build_srsran_5g
  verify_install
  run_pytest_hint

  log "Done. On a fresh machine, copy/rsync this training/ tree first, then re-run without --dry-run."
  if [[ "$DRY_RUN" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    log "If Docker was installed, log out/in so group docker applies for $SUDO_USER."
  fi
}

main "$@"
