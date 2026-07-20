#!/bin/bash

####################################################################################################
#  Ethon Shield
#  2024
####################################################################################################
#
#  Copyright (C) 2024 Ethon Shield S.L.
#
#	 ETHON SHIELD owns all rights (including copyrights, intellectual, industrial, 
#	 commercial or other exploitation rights) of the following code. Disclosure 
#	 or distribution to third party companies or subsidiaries is prohibited.
#
#  Contact information:
#    ethon@ethonshield.com
#    pedro.cabrera@ethonshield.com
#    miguel.gallego@ethonshield.com
#
####################################################################################################

SUFFIX="BASE"
ENB_CONF_FILE="enb.conf"
EPC_CONF_FILE="epc.conf"

function help {
	echo "$0 -c <mcc> -n <mnc> -e <earfcn>"
  echo ""
  echo "Mandatory arguments:"
  echo "-c <mcc>                  Mobile country code of deployed network (3 digits)"
  echo "-n <mnc>                  Mobile network code of deployed network (2 or 3 digits)"
  echo "-e <earfcn>               DL EARFCN"
  echo ""
  echo "Optional arguments:"
  echo "-h                        print this help message"
}


# Mandatory arguments
MCC=""
MNC=""
EARFCN=""

while getopts "c:n:e:h" opt; do
  case $opt in
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
    e) EARFCN="${OPTARG}" ;;
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
if [[ -z "${MCC}" || -z "${MNC}" || -z "${EARFCN}" ]]; then
  echo "ERROR: missing mandatory arguments"
  help
  exit 1
fi

# Value subsitution
sed -e "s/__EARFCN__/${EARFCN}/g" -e "s/__MCC__/${MCC}/g" -e "s/__MNC__/${MNC}/g" ./BASE/${ENB_CONF_FILE}.BASE > ./${ENB_CONF_FILE} 
sed -e "s/__MCC__/${MCC}/g" -e "s/__MNC__/${MNC}/g" ./BASE/${EPC_CONF_FILE}.BASE > ./${EPC_CONF_FILE} 
