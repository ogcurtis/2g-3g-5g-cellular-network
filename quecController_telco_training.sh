#!/bin/bash
######################################################################
#       Ethon Shield
#       Dec 2023
#       
#######################################################################
#
#   Copyright (C) 2023 Ethon Shield S.L.
#
#    Contact Info:
#    ethon@ethonshield.com
#	   pedro.cabrera@ethonshield.com
#	   miguel.gallego@ethonshield.com
#
#######################################################################
#TODO: Check before starting if the qmicli command is working

# Mandatory arguments
QUECTEL_MODEL="" # <modem>

# Optional arguments
USERPIN="" # <PIN>
USERAPN="" # <APN>
PREFERRED="AUTO" # <RAT>
CDCDEV="/dev/cdc-wdm0" # <cdc-wdm>

# Other variables
cfgdevname="quecController"

function help {
  echo "sudo $0 -m <modem> -p <PIN> -r <RAT> -c <cdc-wdm>"
  echo "IMPORTANT: execute with sudo if you are not root"
  echo ""
  echo "Mandatory arguments:"
  echo "-m <modem>            Options are: EC20, EC21, EG21, EC25, EG25, RM500Q and RM520N"
  echo ""
  echo "Optional arguments:"
  echo "-h                    print this help message"
  echo "-p <PIN>              SIM card PIN number (only applies if SIM PIN is active)"
  echo "-a <APN>              User APN in case data is needed (DEFAULT not used)."
  echo "-r <RAT>              Options:"
  echo "                        - For modems ECXX, EGXX: lte, umts, gsm, gsm_900, gsm_1800, auto (DEFAULT=auto)"
  echo "                        - For modems RM5XXX: nr5g, 5g4g, lte, umts, auto (DEFAULT=auto)"
  echo "-c <cdc-wdm>          cdc port (DEFAULT=/dev/cdc-wdm0)"
}

function logging {

  date="$(date '+%Y-%m-%d %H:%M:%S:%N')"

  themsg="${1}"
  severity="${2}"

  echo "${date}	${severity}	${themsg}." > /dev/tty
}


function unbind_bind {
  usbdevice="${1}"  

  echo -n "${usbdevice}" > /sys/bus/usb/drivers/usb/unbind
  sleep 2
  echo -n "${usbdevice}" > /sys/bus/usb/drivers/usb/bind
  sleep 1

}

function find_quec_usbdevice {
  # Resolve the USB bus device for the Quectel modem.
  # Prefer classic syslog; fall back to journalctl on journald-only hosts (24.04+).
  local product_line=""
  if [[ -r /var/log/syslog ]]; then
    product_line=$(grep "Product: ${QUECTEL_MODEL}" /var/log/syslog | sort | tail -1)
  fi
  if [[ -z "${product_line}" ]] && command -v journalctl >/dev/null 2>&1; then
    product_line=$(journalctl -k -b --no-pager 2>/dev/null | grep "Product: ${QUECTEL_MODEL}" | sort | tail -1)
  fi
  if [[ -z "${product_line}" ]]; then
    echo ""
    return 1
  fi
  echo "${product_line}" | cut -d "]" -f2 | cut -d":" -f1 | cut -d" " -f3 | uniq | tail -1
}

function check_usbdevice {


  local device="$1"
  logging "[${FUNCNAME[0]}] Waiting for ${device} connection..." "DEBUG"
  local usbdevice
  usbdevice=$(find_quec_usbdevice)

  # First check if the usb device is a file
  check_anomaly=$(ls -l /dev/tty* | grep "${device}" | grep -c "\-rw-r--r--")
  if [[ ${check_anomaly} -ge 1 ]]; then
    logging "[${FUNCNAME[0]}] ${device} is a file, removing it" "WARNING"
    rm ${device}
    logging "[${FUNCNAME[0]}] unbinding and binding usb device" "DEBUG"
    if [[ -n "${usbdevice}" ]]; then
      unbind_bind ${usbdevice}
    fi
    sleep 5
  fi

  # Second check if the devices is active
  counter=0
  check_device=$(ls -l /dev/tty* | grep "${device}" | wc -l)
  until [[ ${check_device} -ge 1 ]]; do
    logging "[${FUNCNAME[0]}] Waiting for ${device} connection..." "DEBUG"
    check_device=$(ls -l /dev/tty* | grep "${device}" | wc -l)

    if [[ ${counter} -ge 50 ]]; then
      logging "[${FUNCNAME[0]}] ${device} not detected, please ensure the modem is connected, and that the usb devices to access is ttyUSB2" "ERROR"
      exit 1
    fi

    ((counter+=1))

    sleep 2

  done

}

function check_bin {

  which qmicli > /dev/null
  if [[ $? -eq 1 ]]; then
    logging "[${FUNCNAME[0]}] qmicli not found. Please install \"libqmi-utils\" package" "INFO" 
    exit 0
  fi

}

function check_cdc_status {

  maxloopcdc=0
  shortname=$(echo "${CDCDEV}" | cut -d"/" -f3)
  checkcdcstate=$(ls -l /dev/ | grep -c "${shortname}")

  until [ ${checkcdcstate} -eq 1 ] ; do

    sleep 1

    checkcdcstate=$(ls -l /dev/ | grep -c "${shortname}")

    maxloopcdc=$(echo "${maxloopcdc} + 1" |bc)

    if [ ${maxloopcdc} -ge 5 ] ; then
      logging "[${FUNCNAME[0]}] Problem with the modem ${CDCDEV}, waiting...${maxloopcdc}" "ERR" 
      break
    fi

  done
}

function handle_at_cmd {

  # Input arguments
  command="${1}"
  port=${2}
  timeout=${3}
  outpath=${4}

  # Output of function 
  #  0 - ERROR	
  #  1 - OK
  #  2 - TIMEOUT	

  logging "[${FUNCNAME[0]}] AT_CMD: ${command},${port},${outpath}" "DEBUG" 

  #stty -F ${port} 9600 cs8 -ignpar -cstopb -icrnl -inlcr -ocrnl -onlcr -echo  -crtscts
  stty -F ${port} > /tmp/USB.check
  checkconfigusb=$(grep -c -e "-icrnl" -e "-onlcr" -e "-echo" /tmp/USB.check)
  if [ ${checkconfigusb} -ne 3 ] ; then
    stty -F ${port} 9600 cs8 -ignpar -cstopb -icrnl -inlcr -ocrnl -onlcr -echo
    logging "[${FUNCNAME[0]}] Configurado ${port}: 9600 cs8 -ignpar -cstopb -icrnl -inlcr -ocrnl -onlcr -echo" "DEBUG" 
  fi
  rm /tmp/USB.check

  # Posible funcion de envio de comando AT ###################
  cat ${port} > ${outpath}.tmp 2>&1 &
  catPID=$(echo $!)
  echo -e "${command}" > ${port}
  sleep 1

  checkatcmd=$(grep -c "OK" ${outpath}.tmp)

  atresult=1
  maxloop=0
  until [ ${checkatcmd} -eq 1 ] ; do

    sleep 1

    checkatcmd=$(grep -c "OK" ${outpath}.tmp)

    checkerror=$(grep -c -i error ${outpath}.tmp)
    errorcode=$(grep -i error ${outpath}.tmp | tail -f |cut -d":" -f2 | sed 's/ //'| cut -d"'" -f2|cut -d"\\" -f1)

    if [ ${checkerror} -eq 1 ] ; then
      if [ "${errorcode}" != "516" ] ; then
        logging "[${FUNCNAME[0]}] AT_CMD generated an error: $(grep -i error ${outpath})" "ERR" 
        cp ${outpath}.tmp ${outpath}_err_$(date '+%Y_%m_%d-%H%M%S%N')
      fi
      atresult=0
      break
    fi

    if [ ${maxloop} -ge ${timeout} ] ; then

      logging "[${FUNCNAME[0]}] AT_CMD reached maximum waiting time." "DEBUG" 
      cp ${outpath}.tmp ${outpath}_timeout_$(date '+%Y_%m_%d-%H%M%S%N')
      atresult=2
      break
    fi

    maxloop=$(echo "${maxloop} + 1" | bc)

  done

  disown ${catPID}
  sleep 1
  lastcheck=$(ps -ef| grep -v "grep" | grep ${catPID} |wc -l)
  if [ ${lastcheck} -eq 1 ] ; then
    #logging "[${FUNCNAME[0]}] AT_CMD proceso CAT no ha salido tras disown ${catPID}, salida forzada con kill." "DEBUG" 
    kill ${catPID} > /dev/null 2>&1
    sleep 2

    samuraicheck=$(ps -ef| grep -v "grep" | grep ${catPID} |wc -l)
    if [ ${samuraicheck} -eq 1 ] ; then
      #logging "[${FUNCNAME[0]}] AT_CMD proceso CAT no ha salido tras kill soft, kill -9 en curso." "DEBUG" 
      kill -9 ${catPID} > /dev/null 2>&1
    fi
  fi

  cat ${outpath}.tmp | sed 's/[^[:print:]]//g' > ${outpath}

  if [ ${atresult} -eq 1 ] ; then
    logging "[${FUNCNAME[0]}] AT_CMD successfull outcome" "DEBUG" 
  fi

  echo ${atresult}

}

function setup_band_ECXX {

  # Check if band is already configured
  checkband_at_result=$(handle_at_cmd "AT+QCFG=\"band\"\r\n" /dev/ttyUSB2 3 /tmp/checkband)
  sleep 1

  changeband=0
  istherebandconfig=$(grep -c "+QCFG: \"band\"" /tmp/checkband)
  if [ ${istherebandconfig} -eq 1 ]; then 
    currentband=$(grep "+QCFG: \"band\"" /tmp/checkband | sed 's/\r//' | cut -d"," -f2,3)

    if [ "${currentband}" == "0x4,0x800d5" ]; then 
      currentbandconfiguration="LTE"
    elif [ "${currentband}" == "0x250,0x10" ]; then 
      currentbandconfiguration="WCDMA"
    elif [ "${currentband}" == "0x3,0x10" ]; then 
      currentbandconfiguration="GSM"
    elif [ "${currentband}" == "0x1,0x10" ]; then 
      currentbandconfiguration="GSM_900"
    elif [ "${currentband}" == "0x2,0x10" ]; then 
      currentbandconfiguration="GSM_1800"
    elif [ "${currentband}" == "0xbff,0x1e00b0e18df" ]; then 
      currentbandconfiguration="AUTO"
    fi  

    logging "[${FUNCNAME[0]}] Current status of modem bands: ${currentbandconfiguration}" "DEBUG" 

    if [ "${currentbandconfiguration}" != "${PREFERRED}" ]; then 
      logging "[${FUNCNAME[0]}] Current status of modem bands (${currentbandconfiguration}) does not match the configuration (${PREFERRED})" "DEBUG" 
      changeband=1
    else
      logging "[${FUNCNAME[0]}] Current status of modem bands (${currentbandconfiguration}) matches the configuration (${PREFERRED})" "DEBUG" 
    fi
  fi 

  if [ ${changeband} -eq 1 ]; then 
    case "${PREFERRED}" in
      "LTE")bandcmd_at_result=$(handle_at_cmd "AT+QCFG=\"band\",4,800d5,0,1\r\n" /dev/ttyUSB2 3 /tmp/bandcmd);;
      "WCDMA")
        if [[ "${QUECTEL_MODEL}" == "EC25" ]]; then
          bandcmd_at_result=$(handle_at_cmd "AT+QCFG=\"band\",90,10,0,1\r\n" /dev/ttyUSB2 3 /tmp/bandcmd)
        else
          bandcmd_at_result=$(handle_at_cmd "AT+QCFG=\"band\",250,10,0,1\r\n" /dev/ttyUSB2 3 /tmp/bandcmd)
        fi
        ;;
      "GSM")bandcmd_at_result=$(handle_at_cmd "AT+QCFG=\"band\",3,10,0,1\r\n" /dev/ttyUSB2 3 /tmp/bandcmd);;
      "GSM_900")bandcmd_at_result=$(handle_at_cmd "AT+QCFG=\"band\",1,10,0,1\r\n" /dev/ttyUSB2 3 /tmp/bandcmd);;
      "GSM_1800")bandcmd_at_result=$(handle_at_cmd "AT+QCFG=\"band\",2,10,0,1\r\n" /dev/ttyUSB2 3 /tmp/bandcmd);;
      "AUTO")bandcmd_at_result=$(handle_at_cmd "AT+QCFG=\"band\",bff,1e00b0e18df,0,1\r\n" /dev/ttyUSB2 3 /tmp/bandcmd);;
    esac
    logging "[${FUNCNAME[0]}] Band successfully reestablished ${PREFERRED}." "INFO"

    logging "[${FUNCNAME[0]}] Restarting modem..." "DEBUG"

    # Restart modem
    bandcmd_at_result=$(handle_at_cmd "AT+CFUN=0\r\n" /dev/ttyUSB2 3 /tmp/bandcmd)			
    sleep 2
    bandcmd_at_result=$(handle_at_cmd "AT+CFUN=1\r\n" /dev/ttyUSB2 3 /tmp/bandcmd)			
    sleep 2
    check_cdc_status

    logging "[${FUNCNAME[0]}] Modem started successfully." "INFO"

  fi  
}

function setup_band_RM5XX {

  # Check if band is already configured
  checkband_at_result=$(handle_at_cmd "AT+QNWPREFCFG=\"mode_pref\"\r\n" /dev/ttyUSB2 3 /tmp/checkband)
  #rm /tmp/checkband	

  changeband=0
  istherebandconfig=$(grep -c "+QNWPREFCFG:" /tmp/checkband)
  if [ ${istherebandconfig} -eq 1 ]; then 

    currentband=$(grep "+QNWPREFCFG: \"mode_pref\"" /tmp/checkband | sed 's/\r//' | cut -d"," -f2,3)
    if [ "${currentband}" != "${PREFERRED}" ]; then 
      logging "[${FUNCNAME[0]}] Current status of modem bands (${currentband}) does not match the configuration (${PREFERRED})" "DEBUG" 
      changeband=1
    else
      logging "[${FUNCNAME[0]}] Current status of modem bands (${currentband}) matches the configuration (${PREFERRED})" "DEBUG" 
    fi

  else
    logging "[${FUNCNAME[0]}] Current status of the bands on the modem not received (possible timeout)" "DEBUG" 
  fi 

  if [ ${changeband} -eq 1 ]; then 
    bandcmd_at_result=$(handle_at_cmd "AT+QNWPREFCFG=\"mode_pref\",${PREFERRED}\r\n" /dev/ttyUSB2 3 /tmp/bandcmd)
    bandcmd_at_result=$(handle_at_cmd "AT+QNWPREFCFG=\"nr5g_band\",78\r\n" /dev/ttyUSB2 3 /tmp/bandcmd2)
    logging "[${FUNCNAME[0]}] Band forced successfully ${PREFERRED}" "INFO" 
    logging "[${FUNCNAME[0]}] Restarting modem..." "INFO" 

      # Restart modem
      bandcmd_at_result=$(handle_at_cmd "AT+CFUN=0\r\n" /dev/ttyUSB2 3 /tmp/bandcmd)			
      sleep 2
      bandcmd_at_result=$(handle_at_cmd "AT+CFUN=1\r\n" /dev/ttyUSB2 3 /tmp/bandcmd)			
      sleep 2
      check_cdc_status

      logging "[${FUNCNAME[0]}] Modem started successfully" "INFO" 

  fi	

}

function initpin {

  is_sim_card_inserted=$(qmicli --device="${CDCDEV}" --device-open-proxy --uim-get-card-status | grep -c "Card state: 'present'")
  local count=0
  until [[ ${is_sim_card_inserted} -ge 1 ]]; do
    logging "[${FUNCNAME[0]}]  SIM not detected, restarting slot" "DEBUG" 

    # Reiniciar slots de las tarjetas SIm
    qmicli --device="${CDCDEV}" --device-open-proxy --uim-sim-power-on=1

    sleep 5

    is_sim_card_inserted=$(qmicli --device="${CDCDEV}" --device-open-proxy --uim-get-card-status | grep -c "Card state: 'present'")
    ((count += 1))
    if [[ ${count} -ge 12 ]]; then
      logging "[${FUNCNAME[0]}]  SIM not detected, exiting" "ERR" 
      exit 1
    fi


  done

  qmicli --device="${CDCDEV}" --device-open-proxy --uim-get-card-status | awk "/Application type:  'usim/,/PIN1 state:/" | grep "PIN1 state" | cut -d":" -f2 | sed "s/'//g" > /tmp/simcmd1

  sleep 2

  status=$(grep -c "enabled-not-verified" /tmp/simcmd1)

  rm /tmp/simcmd1

  if [ ${status} -ge 1 ] ; then

    logging "[${FUNCNAME[0]}]  SIM requires PIN" "INFO" 

    if [ "A${USERPIN}" != "A" ] ; then
      SIMPIN="${USERPIN}"

      qmicli --device="${CDCDEV}" --device-open-proxy --uim-verify-pin=PIN1,${SIMPIN} > /tmp/simcmd2

      sleep 5
    fi

    status=$(grep -c "PIN verified successfully" /tmp/simcmd2)

    rm /tmp/simcmd2

    if [ ${status} -eq 1 ] ; then
      logging "[${FUNCNAME[0]}]  PIN of SIM card is correct" "INFO" 
    else
      logging "[${FUNCNAME[0]}]  PIN of SIM card is not correct" "ERR" 
      exit 1
    fi
  else
    logging "[${FUNCNAME[0]}]  SIM does not require PIN" "INFO" 
  fi

}

function initreg {

  logging "[${FUNCNAME[0]}]  SIM starts registration on mobile network..." "INFO" 

  qmicli --device="${CDCDEV}" --device-open-proxy  --nas-get-serving-system > /tmp/simcmd3 2>&1
  sleep 5

  regstatus=$(cat /tmp/simcmd3 | grep "Registration state:" | cut -d":" -f2 | sed "s/'//g" | sed 's/ //g')

  waitforregistration=1

  until [ "${regstatus}" == "registered" ] ; do

    qmicli --device="${CDCDEV}" --device-open-proxy  --nas-get-serving-system > /tmp/simcmd3 2>&1
    sleep 2
    logging "[${FUNCNAME[0]}]  SIM trying to register: ${waitforregistration}/12" "INFO" 

    regstatus=$(cat /tmp/simcmd3 | grep "Registration state:" | cut -d":" -f2 | sed "s/'//g" | sed 's/ //g')
    checkexhausted=$(grep -c ClientIdsExhausted /tmp/simcmd3)

    if [ ${checkexhausted} -ge 1 ] ; then
      logging "[${FUNCNAME[0]}]  Problem checking the registration status in the mobile network: ClientIdsExhausted" "ERR" 
      regstatus="ClientIdsExhausted"
      break
    fi

    waitforregistration=$(echo "${waitforregistration} + 1" | bc)

    if [ ${waitforregistration} -gt 12 ] ; then
      logging "[${FUNCNAME[0]}]  SIM has exceeded the maximum waiting time for registration" "INFO" 
      break;
    fi

    sleep 5

  done

  rm /tmp/simcmd3

  if [ "${regstatus}" == "not-registered-searching" ] || [ "${regstatus}" == "not-registered" ] ; then

    qmicli --device="${CDCDEV}" --device-open-proxy --uim-get-card-status | grep "PIN1 state"| cut -d":" -f2 | sed "s/'//g" > /tmp/simcmd1
    sleep 2

    status=$(grep -c "enabled-not-verified" /tmp/simcmd1)

    if [ ${status} -eq 0 ] ; then

      qmicli --device="${CDCDEV}" --device-open-proxy --nas-force-network-search > /tmp/simcmd4 2>&1
      sleep 5
      logging "[${FUNCNAME[0]}]  SIM forces automatic network search..." "INFO" 


      qmicli --device="${CDCDEV}" --device-open-proxy  --nas-get-serving-system > /tmp/simcmd3 2>&1
      sleep 2

      regstatus=$(cat /tmp/simcmd3 | grep "Registration state:" | cut -d":" -f2 | sed "s/'//g" | sed 's/ //g')

      waitforregistration=1

      until [ "${regstatus}" == "registered" ] ; do

        qmicli --device="${CDCDEV}" --device-open-proxy  --nas-get-serving-system > /tmp/simcmd3 2>&1
        sleep 5

        logging "[${FUNCNAME[0]}]  SIM attempting network registration: ${waitforregistration}/12" "INFO" 

        regstatus=$(cat /tmp/simcmd3 | grep "Registration state:" | cut -d":" -f2 | sed "s/'//g" | sed 's/ //g')
        checkexhausted=$(grep -c ClientIdsExhausted /tmp/simcmd3)

        if [ ${checkexhausted} -ge 1 ] ; then
          logging "[${FUNCNAME[0]}]  Problem checking the registration status in the mobile network: ClientIdsExhausted" "ERR" 
          regstatus="ClientIdsExhausted"
          break
        fi

        waitforregistration=$(echo "${waitforregistration} + 1" | bc)

        if [ ${waitforregistration} -gt 12 ] ; then
          logging "[${FUNCNAME[0]}]  SIM has exceeded the maximum waiting time for registration" "INFO" 
          break;
        fi

      done
    else
      logging "[${FUNCNAME[0]}]  SIM restarted after entering the PIN, it will not register on the network" "ERR" 
    fi

    if [ "${regstatus}" != "registered" ] ; then

      logging "[${FUNCNAME[0]}]  SIM could not register in the mobile network: ${regstatus}" "ERR" 
    else
      logging "[${FUNCNAME[0]}]  SIM registered in mobile network" "INFO" 
    fi

  elif [ "${regstatus}" == "registered" ] ; then

    logging "[${FUNCNAME[0]}]  SIM registered in mobile network" "INFO" 

  else

    logging "[${FUNCNAME[0]}]  Network registration anomaly: ${regstatus}" "ERR" 

  fi
}

function connect_quectel {

  QUECTELDEV=$(qmicli -d ${CDCDEV} --device-open-proxy --get-wwan-iface)

  logging "[${FUNCNAME[0]}] Connecting data interface ${QUECTELDEV}" "INFO" 

  # Compruebo estado: AT+QCFG="usbnet"
  atcmdresult=$(handle_at_cmd "AT+QCFG=\"usbnet\"\r\n" /dev/ttyUSB2 3 /tmp/usbcmd)
  usbnetstatus=$(grep "^+QCFG: \"usbnet\"" /tmp/usbcmd | cut -d"," -f2)

  if [ "A" != "A${usbnetstatus}" ] ; then
    logging "[${FUNCNAME[0]}]  usbnet is: ${usbnetstatus}" "DEBUG" 

    if [ ${usbnetstatus} == "1" ] ; then
      atcmdresult=$(handle_at_cmd "AT+QCFG=\"usbnet\",0\r\n" /dev/ttyUSB2 3 /tmp/usbcmd)
      sleep 1
      atcmdresult=$(handle_at_cmd "AT+QCFG=\"usbnet\"\r\n" /dev/ttyUSB2 3 /tmp/usbcmd)
      sbnewnetstatus=$(grep "^+QCFG: \"usbnet\"" /tmp/usbcmd | cut -d"," -f2)
      logging "[${FUNCNAME[0]}]  usbnet new status is: ${usbnewnetstatus}" "DEBUG"
    fi
  else
    logging "[${FUNCNAME[0]}]  Problem reading usbnet status" "ERR" 
    exit 1
  fi

  chkwwanstate=$(cat /sys/class/net/${QUECTELDEV}/qmi/raw_ip)
  if [ "${chkwwanstate}" == "N" ] ; then
    #ifconfig "${QUECTELDEV}" down > /dev/null
    ip link set "${QUECTELDEV}" down
    logging "[${FUNCNAME[0]}]  setting raw-ip to /sys/class/net/${QUECTELDEV}/qmi/raw_ip" "DEBUG" 
    echo Y > /sys/class/net/${QUECTELDEV}/qmi/raw_ip
    #ifconfig "${QUECTELDEV}" up > /dev/null
    ip link set "${QUECTELDEV}" up
  fi

  currentdataformat=$(qmicli --device="${CDCDEV}" --device-open-proxy --get-expected-data-format)
  logging "[${FUNCNAME[0]}]  current data format: ${currentdataformat}" "DEBUG" 

  if [ "A" != "A${currentdataformat} " ] ; then
    if [ "${currentdataformat}" != "raw-ip" ] ; then
      logging "[${FUNCNAME[0]}]  setting data format to raw-ip with qmicli" "DEBUG" 
      qmicli --device="${CDCDEV}" --device-open-proxy --wda-set-data-format=raw-ip > /tmp/simcmd5 2>&1
      sleep 2
    fi
  fi

  logging "[${FUNCNAME[0]}] Checking network registration status..." "DEBUG" 

  qmicli --device="${CDCDEV}" --device-open-proxy  --nas-get-serving-system --client-cid=${clientcid} --client-no-release-cid > /tmp/simcmd3 2>&1

  sleep 2

  regstatus=$(cat /tmp/simcmd3 | grep "Registration state:" | cut -d":" -f2 | sed "s/'//g" | sed 's/ //g')

  until [ "${regstatus}" != "" ] ; do

    # OJO
    # QMI protocol error (5): 'ClientIdsExhausted'
    qmicli --device="${CDCDEV}" --device-open-proxy  --nas-get-serving-system --client-cid=${clientcid} --client-no-release-cid > /tmp/simcmd3 2>&1

    sleep 2

    regstatus=$(cat /tmp/simcmd3 | grep "Registration state:" | cut -d":" -f2 | sed "s/'//g" | sed 's/ //g')
    checkexhausted=$(grep -c ClientIdsExhausted /tmp/simcmd3)

    if [ ${checkexhausted} -ge 1 ] ; then
      logging "[${FUNCNAME[0]}] Problem checking network registration status: ClientIdsExhausted" "ERR" 
      break
    fi

  done

  logging "[${FUNCNAME[0]}]  SIM registered in mobile network: ${regstatus}" "DBUG" 

  operatingmode=$(qmicli --device="${CDCDEV}" --device-open-proxy --dms-get-operating-mode |grep Mode)
  logging "[${FUNCNAME[0]}]  Operating mode: ${operatingmode}" "DEBUG"

  checknetwork=""
  loop=0

  until [ "${checknetwork}" == "Network started" ] ; do
    qmicli --device="${CDCDEV}" --device-open-net="net-raw-ip|net-no-qos-header" --device-open-proxy --wds-start-network="apn='${USERAPN}',ip-type=4" --client-no-release-cid > /tmp/network 2>&1
    sleep 3

    checknetwork=$(grep "Network started" /tmp/network  | cut -d"]" -f2 | sed 's/ //')
    checkinvalid=$(grep -c "InvalidOperation" /tmp/network)
    checkendpointhangup=$(grep -c "endpoint hangup" /tmp/network)
    checktimedout=$(grep -c "Transaction timed out" /tmp/network)

    if [ ${checkinvalid} -eq 1 ] ; then
      logging "[${FUNCNAME[0]}] Unable to start data network, check APN and subscription status" "ERR" 
      exit 1
    fi

    if [ ${checkendpointhangup} -ge 1 ] || [ ${checktimedout} -ge 1 ] ; then
      logging "[${FUNCNAME[0]}]  Timeout or Hangup, waiting 5 seconds..." "DEBUG" 
      sleep 5
    fi

    if [ ${loop} -ge 7 ] ; then
      logging "[${FUNCNAME[0]}]  Maximum number of attempts reached, cancelling." "ERR"
      exit 1
    fi

    ((loop +=1 ))
  done

  logging "[${FUNCNAME[0]}] Data network has been started successfully" "INFO" 
  packet=$(grep "Packet data handle:" /tmp/network | cut -d":" -f2 | sed "s/'//g" | sed 's/ //g')
  cid=$(grep "CID:" /tmp/network | cut -d":" -f2 | sed "s/'//g" | sed 's/ //g')
  echo "${packet}:${cid}" > /tmp/packet.handle
  sleep 1
  udhcpc -q -f -i "${QUECTELDEV}" > /tmp/dhcplog 2>&1
  wwanadd=$(ifconfig ${QUECTELDEV} | grep "inet" | grep -v "inet6"| awk '{print $2}')

  if [ "A" != "A${wwanadd}" ] ; then
    logging "[${FUNCNAME[0]}]  IP address obtained successfully via DHCP: ${wwanadd}" "INFO" 
  else
    logging "[${FUNCNAME[0]}]  Failed to obtain an IP address via DHCP" "ERR" 
  fi

  rm /tmp/network
}

function disconnect_quectel {

  networkstate=$(qmicli --device="${CDCDEV}" --device-open-proxy --wds-get-packet-service-status)
  logging "[${FUNCNAME[0]}]  Network status: ${networkstate}." "DEBUG" 

  if [ -e /tmp/packet.handle ] ; then
    packethandler=$(cat /tmp/packet.handle | cut -d":" -f1)
    clientid=$(cat /tmp/packet.handle | cut -d":" -f2)

    qmicli --device="${CDCDEV}" --device-open-proxy --wds-stop-network=${packethandler} --client-cid=${clientid} > /tmp/network 2>&1
    checkstatus=$(grep -c "Network stopped" /tmp/network)
    if [ ${checkstatus} -ge 1 ] ; then
      logging "[${FUNCNAME[0]}]  Network stopped." "DEBUG" 
    else
      logging "[${FUNCNAME[0]}]  Failed to stop network." "DEBUG"
    fi
  fi

}

function allocateNASclient {
  qmicli --device="${CDCDEV}" --nas-noop --client-no-release-cid > /tmp/clientcid 2>&1
  sleep 2
  clientcid=$(grep "CID:" /tmp/clientcid | cut -d":" -f2 | cut -d"'" -f2)
  until [ "${clientcid}" != "" ] ; do
    qmicli --device="${CDCDEV}" --nas-noop --client-no-release-cid > /tmp/clientcid 2>&1
    sleep 2
    clientcid=$(grep "CID:" /tmp/clientcid | cut -d":" -f2 | cut -d"'" -f2)
  done
  logging "[${FUNCNAME[0]}]  New CID: ${clientcid}" "DEBUG" 
}

function releaseNASclient {
  qmicli --device="${CDCDEV}" --nas-noop --client-cid=${clientcid} > /tmp/releaseclientcid 2>&1
  sleep 2
  checkhangup=$(grep -c "endpoint hangup" /tmp/releaseclientcid)
  if [ ${checkhangup} -eq 1 ] ; then
    sleep 2
    qmicli --device="${CDCDEV}" --nas-noop --client-cid=${clientcid} > /tmp/newreleaseclientcid 2>&1
  fi
  logging "[${FUNCNAME[0]}]  Release CID: ${clientcid}" "DEBUG" 

}

###########################################################################################################
#	Main program
###########################################################################################################

while getopts "m:r:p:c:a:h" opt; do
  case $opt in
    m)
      if [[ "${OPTARG}" == "EC21" || "${OPTARG}" == "EG21" || "${OPTARG}" == "EC25" || "${OPTARG}" == "EG25" || "${OPTARG}" == "RM500Q" || "${OPTARG}" == "RM520N" ]]; then
        QUECTEL_MODEL="${OPTARG}"
      else
        logging "[${FUNCNAME[0]}] Bad parameter, ${OPTARG}" "DEBUG" 
        help
        exit 1
      fi
      ;;
    p)
      USERPIN="${OPTARG}"
      if [[ "${#USERPIN}" -ne 4 ]]; then
        echo "ERROR: PIN number must have 4 digits"
      fi
      ;;
    r)
      case "${OPTARG}" in
        "nr5g") PREFERRED="NR5G" ;;
        "5g4g") PREFERRED="NR5G:LTE" ;;
        "lte") PREFERRED="LTE" ;;
        "umts") PREFERRED="WCDMA" ;;
        "gsm") PREFERRED="GSM" ;;
        "gsm_900") PREFERRED="GSM_900" ;;
        "gsm_1800") PREFERRED="GSM_1800" ;;
        "auto") PREFERRED="AUTO" ;;
        *)
          echo "ERROR: <rat> ${OPTARG} not valid, must be between the options specified" 
          help
          exit 1
          ;;
      esac
      ;;
    a) USERAPN="${OPTARG}" ;;
    c) CDCDEV="${OPTARG}" ;;
    h) help; exit 1 ;;
    :) exit 1 ;;
    \?) exit 1 ;;
  esac
done

if ((OPTIND == 1)); then
  echo "ERROR: No options specified"
  help
  exit 1
fi

if [[ -z "${QUECTEL_MODEL}" ]]; then
  echo "ERROR: Please specify the mandatory arguments"
  help
  exit 1
fi

# Check bands specified for 2G73G/4G quectel modems
if [[ "${QUECTEL_MODEL}" == "EC21" || "${QUECTEL_MODEL}" == "EC25" ]]; then
  if [[ "${PREFERRED}" == "nr5g" || "${PREFERRED}" == "5g4g"  ]]; then 
    logging "[${FUNCNAME[0]}] Bad parameter, for modem option EC21 or EC25, the possible RATs are: lte, umts, gsm, gsm_900, gsm_1800, auto. ${OPTARG} is not between the options" "DEBUG" 
  fi
fi

# Checkers 
check_usbdevice "/dev/ttyUSB2"
check_bin

# Setup bands
if [[ "${QUECTEL_MODEL}" == "EC21" || "${QUECTEL_MODEL}" == "EG21" || "${QUECTEL_MODEL}" == "EC25" || "${QUECTEL_MODEL}" == "EG25" ]]; then
  setup_band_ECXX
else
  setup_band_RM5XX
fi
sleep 3

nas_initialized=0

# Initialize SIM PIN
initpin

# If there is an APN from user, allocate NAS client 
if ! [[ -z "${USERAPN}" ]]; then
  allocateNASclient
fi

# Initialize registration
initreg

# If there is an APN from user, after registering, request a connection 
if ! [[ -z "${USERAPN}" ]]; then
  connect_quectel
fi
