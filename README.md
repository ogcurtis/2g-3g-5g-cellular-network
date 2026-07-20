# 2G / 3G / 5G Cellular Network Lab

Bare-metal lab for building and running open-source cellular stacks on **Ubuntu 26.04 LTS** with USRP (UHD) radios.

Clone → install deps → rebuild → run. Validated on Ubuntu 26.04 (Resolute) with Ettus B205mini.

## What you get

| RAT | Stack | Role |
|-----|--------|------|
| **2G** | Osmocom (`osmo-trx-uhd`, `osmo-bts-trx`, BSC/MSC/HLR/…) | GSM/GPRS base station |
| **3G** | UE RAT + Osmocom HNB-GW config | Modem UMTS mode (`quecController`); `osmo-hnbgw.cfg` for Iuh/HNB labs (binary not in default rebuild) |
| **4G** | srsRAN 4G (`srsenb` / `srsepc`) | LTE eNB + EPC |
| **5G SA** | srsRAN Project (`gnb`) + OAI 5GC (Docker) | NR gNB + core |
| **5G NSA** | OpenAirInterface (optional archives) | NSA lab materials under `5g_nsa/` |

RF driver: **UHD 4.6.0.0** (USRP B200/B205 family).

## Requirements

- **OS:** Ubuntu **26.04** bare metal (not a VM)
- **Hardware:** multi-core CPU, 16 GB RAM recommended, USB3 for USRP
- **Disk:** ~20 GB free after clone + build
- **Git LFS:** required (large source archives)

```bash
# macOS (to push/maintain) or Linux client
git lfs install

# On the Ubuntu 26 build machine
sudo apt-get update
sudo apt-get install -y git git-lfs
git lfs install
```

## Quick start (new Ubuntu 26 machine)

```bash
git clone https://github.com/ogcurtis/2g-3g-5g-cellular-network.git
cd 2g-3g-5g-cellular-network
git lfs pull

# Preview what will be installed/built (no changes)
./install_ubuntu_26.sh --dry-run

# Install apt deps + rebuild UHD, Osmocom 2G, srsRAN 4G, srsRAN 5G SA
sudo ./install_ubuntu_26.sh
```

Useful flags:

```bash
sudo ./install_ubuntu_26.sh --deps-only      # packages only
sudo ./install_ubuntu_26.sh --skip-docker    # skip Docker CE
sudo ./install_ubuntu_26.sh -j 8            # limit make jobs
./install_ubuntu_26.sh --help
```

After install, smoke-check:

```bash
uhd_find_devices
srsenb --version
gnb --version
osmo-trx-uhd --version
python3 -m pytest tests/ -q
python3 -m upgrade.report --target 26.04
```

## Layout

```
.
├── install_ubuntu_26.sh   # repeatable Ubuntu 26.04 installer (supports --dry-run)
├── 2g/                    # Osmocom sources (archives) + configs
├── 4g/                    # srsRAN 4G archive + LTE configs
├── 5g_sa/                 # srsRAN Project + OAI 5GC compose/configs
├── 5g_nsa/                # OAI NSA materials (optional)
├── uhd_releases/          # UHD 4.6.0.0 archive
├── sims/                  # SIM tooling archives
├── upgrade/               # LTS port checklist (pytest + report)
├── tests/                 # repo unit tests
├── commands_cheatsheet.txt
└── quecController_telco_training.sh
```

Source **archives** (`.tar` / `.tar.gz`) are in git (large ones via **Git LFS**). Extracted trees and `build/` dirs are gitignored and recreated by the installer.

## Ubuntu 26.04 build notes

The installer encodes fixes from the LTS port:

- **gcc-14 / g++-14** (default GCC 15 breaks older UHD/srsRAN)
- **Boost 1.83** CMake package for UHD
- UHD: `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`
- srsRAN 4G/5G: `-DENABLE_WERROR=OFF`
- srsRAN 5G: `-DBUILD_TESTS=OFF` (system gtest wants C++17)

## 5G core (Docker)

OAI CN5G images are **not** stored in this repo (too large). After Docker is installed:

```bash
cd 5g_sa/conf
# use the training compose file; images pull from Docker Hub
docker compose -f docker-compose-basic-nrf.yaml pull
docker compose -f docker-compose-basic-nrf.yaml up -d
```

Point `gnb` `amf.addr` / `bind_addr` at your `demo-oai` addresses (see cheatsheet).

## Tests

```bash
python3 -m pytest tests/ -q
python3 -m upgrade.report --target 26.04
```

## License / attribution

Third-party stacks (Osmocom, srsRAN, UHD, OAI) keep their upstream licenses. Lab scripts and configs are for training use.

## Security

Do **not** commit live SIM ADM/Ki/OPc values. Use `SIM_Values.example` as a template and keep real secrets local (gitignored `SIM_Values`).
