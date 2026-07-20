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
OPC="" 
DDBB_FILE="oai_db2.sql"

function help {
  echo "$0 -i <IMSI> -k <KI> -o <OPC>"
  echo ""
  echo "Mandatory arguments:"
  echo "-i <IMSI>     IMSI"
  echo "-k <KI>       KI"
  echo "-o <OPC>      OPc"
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
      OPC=${OPTARG}
      if ! [[ "${OPC}" =~ ^[0-9a-fA-F]{32}$ ]]; then
        echo "ERROR: OPc value not valid, it has to be 32 characters long (in hex)"
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
if [[ -z "${IMSI}" || -z "${KI}" || -z "${OPC}" ]]; then
  echo "ERROR: missing mandatory arguments"
  help
  exit 1
fi

# Check if imsi is in DDBB
if [[ -f ${DDBB_FILE} ]]; then
  is_imsi_in_ddbb=$(grep -c "${IMSI}" ${DDBB_FILE})
  if [ ${is_imsi_in_ddbb} -ge 1 ]; then
    echo "ERROR: IMSI - ${IMSI} is already in database ${DDBB_FILE}"
    exit 1
  fi
fi

# Add new user
insert_db="INSERT INTO \`AuthenticationSubscription\` VALUES ('__IMSI__', '5G_AKA', '__KI__', '__KI__', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', '__OPC__', NULL, NULL, NULL, NULL, '__IMSI__');"
if [[ -f ${DDBB_FILE} ]]; then
  sed -i "s/-- __NEW_USER__/${insert_db}\n-- __NEW_USER__/g" ./${DDBB_FILE}
else
  sed "s/-- __NEW_USER__/${insert_db}\n-- __NEW_USER__/g" ./BASE/${DDBB_FILE}.BASE > ./${DDBB_FILE}
fi

sed -i -e "s/__IMSI__/${IMSI}/g" -e "s/__KI__/${KI}/g" -e "s/__OPC__/${OPC}/g" ./${DDBB_FILE} 
