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

ENB_CONF_FILE="enb.band7.tm1.fr1.25PRB.usrpb210.conf"
GNB_CONF_FILE="gnb.band78.tm1.fr1.106PRB.usrpb210.conf"
DOCKER_COMPOSE_FILE="docker-compose.yml"
MME_CONF_FILE="mme.conf"

function help {
	echo "$0 -e <enb_ip_address> -g <gnb_ip_address> -c <mcc> -n <mnc> -t <tac> -b <eutra_band> -d <dl_freq_enb> -f <offset>"
  echo ""
  echo "Mandatory arguments:"
  echo "-e <enb_ip_address>       eNB IP address"
  echo "-g <gnb_ip_address>       gNB IP address"
  echo "-c <mcc>                  Mobile country code of deployed network (3 digits)"
  echo "-n <mnc>                  Mobile network code of deployed network (2 or 3 digits)"
  echo "-t <tac>                  TAC"
  echo "-b <eutra_band>           Frequency band of eNB "
  echo "-d <dl_freq_enb>          Downlink frequency "
  echo "-f <offset>               Offset parameter between dl frequency and ul freq "
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
enb_ip_address=""
gnb_ip_address=""
MCC=""
MNC=""
TAC=""
eutra_band=""
dl_freq_enb=""
offset=""

while getopts "e:g:c:n:t:b:d:f:h" opt; do
  case $opt in
    e)
      enb_ip_address="${OPTARG}"
      if ! valid_ip ${enb_ip_address}; then
        echo "ERROR: Invalid eNB IP address ${enb_ip_address}"
        exit 1
      fi	
      ;;
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
      TAC_HEX=$(echo "obase=16; ${TAC}" | bc)
      ;;
    b) eutra_band="${OPTARG}" ;;
    d) dl_freq_enb="${OPTARG}" ;;
    f) offset="${OPTARG}" ;;
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
if [[ -z "${enb_ip_address}" || -z "${gnb_ip_address}" || -z "${MCC}" || -z "${MNC}" || -z "${TAC}" || -z "${eutra_band}" || -z "${dl_freq_enb}" || -z "${offset}" ]]; then
  echo "ERROR: missing mandatory arguments"
  help
  exit 1
fi

# Value substitution
sed -e "s/__DL_FREQ_ENB__/${dl_freq_enb}/g" -e "s/__EUTRA_BAND__/${eutra_band}/g" -e "s/__OFFSET__/${offset}/g" -e "s/__ENB_IP_ADDRESS__/${enb_ip_address}/g" -e "s/__MCC__/${MCC}/g" -e "s/__MNC__/${MNC}/g" -e "s/__TAC__/${TAC}/g" ./BASE/${ENB_CONF_FILE}.BASE > ./${ENB_CONF_FILE} 
sed -e "s/__GNB_IP_ADDRESS__/${gnb_ip_address}/g" -e "s/__ENB_IP_ADDRESS__/${enb_ip_address}/g" -e "s/__MCC__/${MCC}/g" -e "s/__MNC__/${MNC}/g" -e "s/__TAC__/${TAC}/g" ./BASE/${GNB_CONF_FILE}.BASE > ./${GNB_CONF_FILE} 
sed -e "s/__MCC__/${MCC}/g" -e "s/__MNC__/${MNC}/g" -e "s/__TAC__/${TAC}/g" ./BASE/${DOCKER_COMPOSE_FILE}.BASE > ./${DOCKER_COMPOSE_FILE} 
sed -e "s/__MCC__/${MCC}/g" -e "s/__MNC__/${MNC}/g" -e "s/__TAC__/${TAC}/g" ./BASE/${MME_CONF_FILE}.BASE > ./${MME_CONF_FILE} 


echo "WARNING: Remember to add a user to the docker-composer.yml file with the add_user_nsa.sh script"
