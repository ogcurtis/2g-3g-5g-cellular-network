#!/bin/bash

###################################################################################################
#       Ethon Shield
#       2024
####################################################################################################
#
#       Copyright (C) 2024 Ethon Shield S.L.
#
#       ETHON SHIELD owns all rights (including copyrights, intellectual, industrial, 
#       commercial or other exploitation rights) of the following code. Disclosure 
#       or distribution to third party companies or subsidiaries is prohibited.
#
#       Contact information:
#         ethon@ethonshield.com
#         pedro.cabrera@ethonshield.com
#         miguel.gallego@ethonshield.com
#
####################################################################################################

IMSI=""
KI=""
OP="" 
DDBB_FILE="docker-compose.yml"

function help {
  echo "$0 -i <IMSI> -k <KI> -o <OP>"
  echo ""
  echo "Mandatory arguments:"
  echo "-i <IMSI>     IMSI"
  echo "-k <KI>       KI"
  echo "-o <OP>       OP"
  echo ""
  echo "Optional arguments:"
  echo "-h            print this help message"
  exit 1
}

no_args="true"
while getopts ":i:k:o:h" opt; do
  case $opt in
    i)
      IMSI=${OPTARG}
      if ! [[ "${IMSI}" =~ ^[0-9]{15}$ ]]; then
        echo "ERROR: IMSI value not valid, it has to be 15 digits long"
        exit 1
      fi
      ;;
    k)
      KI=${OPTARG}
      if ! [[ "${KI}" =~ ^[0-9a-fA-F]{32}$ ]]; then
        echo "ERROR: Ki value not valid, it has to be 32 characters long (in hex)"
        exit 1
      fi
      ;;
    o)
      OP=${OPTARG}
      if ! [[ "${OP}" =~ ^[0-9a-fA-F]{32}$ ]]; then
        echo "ERROR: OP value not valid, it has to be 32 characters long (in hex)"
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
if [[ -z "${IMSI}" || -z "${KI}" || -z "${OP}" ]]; then
  echo "ERROR: missing mandatory arguments"
  help
  exit 1
fi

# Check if docker-compose.yml has already been configured
is_configured=$(grep -c -- "__MCC__" ${DDBB_FILE})
if [[ ${is_configured} -ge 1 ]]; then
  echo "ERROR: please configure ${DDBB_FILE} first with config_files_nsa.sh script"
  exit 1
fi

# Check if imsi is in DDBB
is_imsi_in_ddbb=$(grep -c "${IMSI}" ${DDBB_FILE})
if [[ ${is_imsi_in_ddbb} -ge 1 ]]; then
  echo "ERROR: IMSI - ${IMSI} is already in database ${DDBB_FILE}"
  exit 1
fi

# Add new user
if [[ -f ./${DDBB_FILE} ]]; then
  sed -i -e "s/__IMSI__/${IMSI}/g" -e "s/__KI__/${KI}/g" -e "s/__OP__/${OP}/g" ./${DDBB_FILE} 
else
  sed -i -e "s/__IMSI__/${IMSI}/g" -e "s/__KI__/${KI}/g" -e "s/__OP__/${OP}/g" ./BASE/${DDBB_FILE} 
fi
