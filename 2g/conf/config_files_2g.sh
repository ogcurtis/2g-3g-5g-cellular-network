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

CONF_DIR=$(pwd)/config_files
BACKUP_CONF_DIR=${CONF_DIR}/BASE

function help {
	echo "$0 -i <ip_address> -c <mcc> -n <mnc> -a <arfcn> -g <ggsn_ip_address>"
  echo ""
  echo "Mandatory arguments:"
  echo "-i <ip_address>           IP address of your machine"
  echo "-c <mcc>                  Mobile country code of deployed network (3 digits)"
  echo "-n <mnc>                  Mobile network code of deployed network (2 or 3 digits)"
  echo "-a <arfcn>                ARFCN of deployed network"
  echo "-g <ggsn_ip_address>      GGSN IP address (has to be free in the network)"
  echo ""
  echo "Optional arguments:"
  echo "-h                        print this help message"
}

function valid_ip()
{
  local  ip=$1
  local  stat=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    OIFS=$IFS
    IFS='.'
    ip=($ip)
    IFS=$OIFS
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
      && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
          stat=$?
  fi
  return $stat
}

# Mandatory arguments
ip_address=""
MCC=""
MNC=""
ARFCN=""
secondary_ip_address=""

while getopts "i:c:n:a:g:r:h" opt; do
  case $opt in
    i)
      ip_address="${OPTARG}"
      if ! valid_ip ${ip_address}; then
        echo "ERROR: Invalid IP address ${ip_address}"
        exit 1
      fi	

      ip_address_exists=$(ifconfig | grep -c -- "${ip_address}")
      if [[ ${ip_address_exists} -eq 0 ]]; then 
        echo "ERROR: IP address ${ip_address} does not exist in interfaces"
        exit 1
      fi
      ;;
    c) 
      MCC="${OPTARG}"
      if [[ ${#MCC} -ne 3 ]]; then
        echo "ERROR: MCC should be 3 digits long"
        exit 1 
      fi
      ;;
    n) 
      MNC="${OPTARG}"
      if [[ ${#MNC} -ne 2 && ${#MNC} -ne 3 ]]; then
        echo "ERROR: MNC should be 2 or 3 digits long"
        exit 1 
      fi
      ;;
    a)ARFCN="${OPTARG}";;
    g)
      secondary_ip_address="${OPTARG}"
      if ! valid_ip ${secondary_ip_address}; then
        echo "ERROR: Invalid Secondary IP Address (${secondary_ip_address}) no es valida"
        exit 1
      fi	
      ;;
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

# Check for mandatory arguments
if [[ -z "${ip_address}" || -z "${MCC}" || -z "${MNC}" || -z "${ARFCN}" || -z "${secondary_ip_address}" ]]; then
  echo "ERROR: missing mandatory arguments"
  help
  exit 1
fi

# Variable substitution
sed -e "s/@@LOCAL_IP_ADDRESS@@/${ip_address}/g" -e "s/@@SECONDARY_IP_ADDRESS@@/${secondary_ip_address}/g" ${BACKUP_CONF_DIR}/osmo-sgsn.cfg > ${CONF_DIR}/osmo-sgsn.cfg 
sed -e "s/@@LOCAL_IP_ADDRESS@@/${ip_address}/g" ${BACKUP_CONF_DIR}/osmo-bts-trx.cfg  > ${CONF_DIR}/osmo-bts-trx.cfg
sed -e "s/@@LOCAL_IP_ADDRESS@@/${ip_address}/g" ${BACKUP_CONF_DIR}/osmo-mgw-for-bsc.cfg  > ${CONF_DIR}/osmo-mgw-for-bsc.cfg
sed -e "s/@@LOCAL_IP_ADDRESS@@/${ip_address}/g" -e "s/@@MCC@@/${MCC}/g" -e "s/@@MNC@@/${MNC}/g" -e "s/@@ARFCN@@/${ARFCN}/g" ${BACKUP_CONF_DIR}/osmo-bsc.cfg > ${CONF_DIR}/osmo-bsc.cfg 
sed -e "s/@@SECONDARY_IP_ADDRESS@@/${secondary_ip_address}/g" ${BACKUP_CONF_DIR}/osmo-ggsn.cfg > ${CONF_DIR}/osmo-ggsn.cfg 
sed -e "s/@@MCC@@/${MCC}/g" -e "s/@@MNC@@/${MNC}/g" ${BACKUP_CONF_DIR}/osmo-msc.cfg > ${CONF_DIR}/osmo-msc.cfg 

all_var_subsituted=$(grep -c "@@" ${CONF_DIR}/*.cfg | awk -F ":" 'BEGIN {a=0} {a=$2;b=b+a} END {print b}')
if [[ ${all_var_subsituted} -ge 1 ]]; then
  echo "ERROR: some files weren't configured correctly"
  grep -l "@@" ${CONF_DIR}/*.cfg
else
  echo "SUCCESS: Files configured correctly"
fi
