#!/bin/bash

####################################################################################################
#       Ethon Shield
#       2024
####################################################################################################
#
#       Copyright (C) 2024 Ethon Shield S.L.
#
#	      ETHON SHIELD owns all rights (including copyrights, intellectual, industrial, 
#	      commercial or other exploitation rights) of the following code. Disclosure 
#	      or distribution to third party companies or subsidiaries is prohibited.
#
#       Contact information:
#       ethon@ethonshield.com
#       pedro.cabrera@ethonshield.com
#       miguel.gallego@ethonshield.com
#
####################################################################################################

SUFFIX="BASE"
GNB_CONF_FILE="gnb_rf_b200_tdd_n78_20mhz.yml"
DOCKER_COMPOSE_FILE="basic_nrf_config.yaml"

function help {
	echo "$0 -g <gnb_ip_address> -c <mcc> -n <mnc> -t <tac> -a <nrarfcn>"
  echo ""
  echo "Mandatory arguments:"
  echo "-g <gnb_ip_address>       gNB IP address of your machine"
  echo "-c <mcc>                  Mobile country code of deployed network (3 digits)"
  echo "-n <mnc>                  Mobile network code of deployed network (2 or 3 digits)"
  echo "-t <tac>                  TAC"
  echo "-a <nrarfcn>              DL NRARFCN"
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
gnb_ip_address=""
MCC=""
MNC=""
TAC=""
ARFCN=""

while getopts "g:c:n:t:a:h" opt; do
  case $opt in
    g)
      gnb_ip_address="${OPTARG}"
      if ! valid_ip ${gnb_ip_address}; then
        echo "ERROR: Invalid gNB IP address ${ip_address}"
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
    t)
      TAC="${OPTARG}"
      ;;
    a) ARFCN="${OPTARG}" ;;
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
if [[ -z "${gnb_ip_address}" || -z "${MCC}" || -z "${MNC}" || -z "${TAC}" ]]; then
  echo "ERROR: missing mandatory arguments"
  help
  exit 1
fi

# Value subsitution
sed -e "s/__ARFCN__/${ARFCN}/g" -e "s/__GNB_IP_ADDRESS__/${gnb_ip_address}/g" -e "s/__MCC__/${MCC}/g" -e "s/__MNC__/${MNC}/g" -e "s/__TAC__/${TAC}/g" ./BASE/${GNB_CONF_FILE}.BASE > ./${GNB_CONF_FILE} 
sed -e "s/__MCC__/${MCC}/g" -e "s/__MNC__/${MNC}/g" -e "s/__TAC__/${TAC}/g" ./BASE/${DOCKER_COMPOSE_FILE}.BASE > ./${DOCKER_COMPOSE_FILE} 
cp ./BASE/docker-compose-basic-nrf.yaml.BASE ./docker-compose-basic-nrf.yaml

echo "NOTICE: Remember to copy the files to their corresponding directory"

