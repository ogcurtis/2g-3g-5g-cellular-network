#!/bin/bash

####################################################################################################
#   Ethon Shield
#   2024
####################################################################################################
#
#   Copyright (C) 2024 Ethon Shield S.L.
#
#	  ETHON SHIELD owns all rights (including copyrights, intellectual, industrial, 
#	  commercial or other exploitation rights) of the following code. Disclosure 
#	  or distribution to third party companies or subsidiaries is prohibited.
#
#   Contact information:
#     ethon@ethonshield.com
#     pedro.cabrera@ethonshield.com
#     miguel.gallego@ethonshield.com
#
####################################################################################################

readonly CONFIG_FILES_PATH=$(pwd)/config_files

readonly OSMO_COMMANDS=$(cat <<END
gsm osmo-trx-uhd osmo-trx-usrp_b200.cfg
gsm osmo-hlr osmo-hlr.cfg
gsm osmo-msc osmo-msc.cfg
gsm osmo-mgw osmo-mgw-for-msc.cfg 
gsm osmo-mgw osmo-mgw-for-bsc.cfg
gprs osmo-ggsn osmo-ggsn.cfg
gprs osmo-sgsn osmo-sgsn.cfg
gsm osmo-stp osmo-stp.cfg
gsm osmo-bsc osmo-bsc.cfg
gprs osmo-pcu osmo-pcu.cfg
gsm osmo-bts-trx osmo-bts-trx.cfg
END
)

function help {
  echo "sudo $0 -t <tech> -i <local_interface>"
  echo "IMPORTANT: run with sudo" 
  echo ""
  echo "Mandatory arguments:"
  echo "-t <tech>              gsm or gprs"
  echo "-i <local_interface>   network interface used (example eno1)"
  echo ""
  echo "Optional arguments:"
  echo "-h                     print this help message"
  echo "-k                     kill osmocom 2G processes"
  echo ""
  echo "Telnet access ports (telnet localhost <port>):"
  echo "  BSC - 4242"
  echo "  MGW - 4243"
  echo "  SGSN - 4245"
  echo "  MSC - 4254"
  echo "  SIP Connector - 4256"
  echo "  HLR - 4258"
  echo "  GGSN - 4260"
}

function kill_if_running {
  # Check if there are any osmcom binaries already running
  # and if so, kill them
  local is_osmocom_running=$(ps -ef | grep -v "grep" | grep -c "osmo-")
  if [[ ${is_osmocom_running} -ge 1 ]]; then
    echo "WARNING: Detected omsmocom binaries running, killing them"
    while read -r line; do 
      pid=$(echo ${line} | awk '{print $2}')
      sudo kill -9 ${pid}
    done < <(ps -ef | grep -v "grep" | grep "osmo-")
  else
    echo "No processes to kill"
  fi

}

function check_bin_execution {
  # Check if osmocom binary is running
  local binary=$1
  is_binary_running=$(ps -ef | grep -v "grep" | grep -c "${binary}")
  if [[ ${is_binary_running} -eq 0 ]]; then
    echo "WARNING: ${binary} is not running"
    kill_if_running
    exit 1
  fi
}

function check_osmocom_is_installed {
  
  # Binaries or config files
  local to_check=$1
  local are_installed="yes"

  while read -r line; do

    osmo_command_tech=$(echo "${line}" | awk '{print $1}')
    osmo_command_binary=$(echo "${line}" | awk '{print $2}')
    osmo_command_cfg=$(echo "${line}" | awk '{print $3}')

    check=1
    if [[ "${technology_chosen}" == "gsm" && "${osmo_command_tech}" == "gprs" ]]; then
      check=0
    fi

    if [[ ${check} -eq 1 ]]; then
      # Check if binaries are installed
      if [[ "${to_check}" == "binaries" ]]; then
        if ! command -v ${osmo_command_binary} &> /dev/null; then
          echo "Binary ${osmo_command_binary} is not installed, please check you have installed all necessary binaries" >&2
          are_installed="no"
        fi
      # Check if config files are installed
      elif [[ "${to_check}" == "config_files" ]]; then
        if ! [[ -f ${CONFIG_FILES_PATH}/${osmo_command_cfg} ]]; then
          echo "Config file ${osmo_command_cfg} not found in ${CONFIG_FILES_PATH} directory" >&2
          are_installed="no"
        fi
      fi
    fi

  done < <(echo "${OSMO_COMMANDS}")

  echo "${are_installed}"
}


# Arguments to read
technology_chosen=""
interface_chosen=""

while getopts "t:i:kh" opt; do
  case $opt in
    t)
      technology_chosen=${OPTARG}
      if [[ "${technology_chosen}" != "gsm" && "${technology_chosen}" != "gprs" ]]; then
        echo "ERROR: <tech> can only be gsm or gprs"
        exit 1
      fi
      ;;
    i) 
      interface_chosen="${OPTARG}"
      # Check if interface exists
      interface_exists=$(ls /sys/class/net/ | grep -c -- "${interface_chosen}")
      if [[ ${interface_exists} -eq 0 ]]; then 
        echo "The interface ${interface_chosen} does not exist. Please check which interface is being used with ifconfig or ip addr show."
        exit 1 
      fi
      ;;
    k) kill_if_running; exit 1;;
    h) help; exit 1;;
    :) exit 1 ;;
    ?) exit 1 ;;
  esac
done

if ((OPTIND == 1)); then
  echo "ERROR: No options specified"
  help
  exit 1
fi

# Check mandatory options
if [[ -z "${technology_chosen}" || -z "${interface_chosen}" ]]; then
  echo "ERROR: Please specify all mandatory arguments"
  help
  exit 1
fi

# Check for xterm binary
if ! command -v xterm &> /dev/null; then 
  echo "ERROR: Please install xterm"
  exit 1
fi

# Check osmocom binaries are installed
are_all_binaries_installed=$(check_osmocom_is_installed "binaries")
if [[ "${are_all_binaries_installed}" == "no" ]]; then
  echo "ERROR: Please install all necessary binaries"
  exit 1
fi

# Check osmocom config files are installed
are_all_config_files_installed=$(check_osmocom_is_installed "config_files")
if [[ "${are_all_config_files_installed}" == "no" ]]; then
  echo "ERROR: Please install all necessary config files"
  exit 1
fi

# Kill any osmocom process if running
kill_if_running

# Forwarding and Routing 
secondary_ip_address=$(grep "gtp bind-ip" ${CONFIG_FILES_PATH}/*.cfg | awk '{print $NF}' | sort | uniq)
ip addr add ${secondary_ip_address}/32 dev ${interface_chosen}
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -s 192.168.42.0/24 -o ${interface_chosen} -j MASQUERADE
iptables -P FORWARD ACCEPT

# Executing OSMOCOM 2G
while read -r line; do

  osmo_command_tech=$(echo "${line}" | awk '{print $1}')
  osmo_command_binary=$(echo "${line}" | awk '{print $2}')
  osmo_command_cfg=$(echo "${line}" | awk '{print $3}')

  # Variable used to know if the binary should be executed or not
  launch=1
  if [[ "${technology_chosen}" == "gsm" && "${osmo_command_tech}" == "gprs" ]]; then
    launch=0
  fi

  if [[ ${launch} -eq 1 ]]; then
    # Special case: osmo-trx-uhd config files is specified with -C not -c
    if [[ "${osmo_command_binary}" == "osmo-trx-uhd" ]]; then
      xterm -T "${osmo_command_cfg}" -e bash -c "${osmo_command_binary} -C ${CONFIG_FILES_PATH}/${osmo_command_cfg} 2>&1 | tee /tmp/run2g_${osmo_command_cfg}" &
    else
      xterm -T "${osmo_command_cfg}" -e bash -c "${osmo_command_binary} -c ${CONFIG_FILES_PATH}/${osmo_command_cfg} 2>&1 | tee /tmp/run2g_${osmo_command_cfg}" &
    fi
    echo "${osmo_command_binary} launched: $!"
    sleep 5
    check_bin_execution "${osmo_command_binary}"
  fi

done < <(echo "${OSMO_COMMANDS}")
