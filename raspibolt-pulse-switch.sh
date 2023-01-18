#!/bin/bash
# /etc/systemd/system/raspibolt-pulse.sh
set -u

# make executable and copy script to /etc/update-motd.d/
# user must be able to execute bitcoin-cli and lncli

# Script configuration
# ------------------------------------------------------------------------------

# set datadir
bitcoin_dir="/mnt/ext/bitcoin"    # Raspibolt 1.x, 2.x
if [ -d "/data/bitcoin" ]; then
  bitcoin_dir="/data/bitcoin"     # Raspibolt 3.x
fi

# determine second drive info
drivecount=$(lsblk --output MOUNTPOINT | grep / | grep -v /boot | sort | wc -l)
if [ $drivecount -gt 1 ]; then
  ext_storage2nd=$(lsblk --output MOUNTPOINT | grep / | grep -v /boot | sort | sed -n 2p)
else
  ext_storage2nd=""
fi

# set to network device name (usually "eth0" for ethernet, and "wlan0" for wifi)
network_name="eth0"
#network_name="enp0s31f6"

# set expected service and user names... common alternate values
sn_bitcoin="bitcoind"
un_bitcoin="bitcoin"
sn_lnd="lnd"
un_lnd="lnd"                            # lnd, bitcoin
sn_cln="lightningd"                     # cln, lightningd
un_cln="lightningd"                     # cln, lightningd
sn_btcrpcexplorer="btcrpcexplorer"
un_btcrpcexplorer="btcrpcexplorer"
sn_electrs="electrs"
un_electrs="electrs"
sn_fulcrum="fulcrum"
un_fulcrum="fulcrum"
sn_rtl="rtl"               # rtl, ridethelightning
un_rtl="rtl"               # rtl, ridethelightning
sn_thunderhub="thunderhub"
un_thunderhub="thunderhub"

# Helper functionality
# ------------------------------------------------------------------------------

# set colors
color_red='\033[0;31m'
color_green='\033[0;32m'
color_yellow='\033[0;33m'
color_grey='\033[0;37m'
color_orange='\033[38;5;208m'
color_magenta='\033[0;35m'

# controlled abort on Ctrl-C
trap_ctrlC() {
  echo -e "\r"
  printf "%0.s " {1..80}
  printf "\n"
  exit
}

trap trap_ctrlC SIGINT SIGTERM

# print usage information for script
usage() {
  echo "RaspiBolt Welcome: system status overview
usage: $(basename "$0") [--help] [--mock]

This script can be run on startup: make it executable and
copy the script to /etc/update-motd.d/
"
}

# check script arguments
mockmode=0
if [[ ${#} -gt 0 ]]; then
  if [[ "${1}" == "-m" ]] || [[ "${1}" == "--mock" ]]; then
    mockmode=1
  else
    usage
    exit 0
  fi
fi


# Print first welcome message
# ------------------------------------------------------------------------------
printf "
${color_yellow}RaspiBolt %s:${color_grey} Sovereign \033[1m"₿"\033[22mitcoin full node
${color_yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
" "3"

# Gather system data
# ------------------------------------------------------------------------------
printf "%0.s#" {1..40}
echo -ne '\r### Loading System data \r'

# get uptime & load
load=$(w|head -1|sed -E 's/.*load average: (.*)/\1/')
uptime=$(w|head -1|sed -E 's/.*up (.*),.*user.*/\1/'|sed -E 's/([0-9]* days).*/\1/')

# get CPU temp
cpu=$(cat /sys/class/thermal/thermal_zone0/temp)
# cpu=$(cat /sys/class/thermal/thermal_zone3/temp)

temp=$((cpu/1000))
if [ ${temp} -gt 60 ]; then
  color_temp="${color_red}\e[7m"
elif [ ${temp} -gt 50 ]; then
  color_temp="${color_yellow}"
else
  color_temp="${color_green}"
fi

# get memory
ram_avail=$(free --mebi | grep Mem | awk '{ print $7 }')

if [ "${ram_avail}" -lt 100 ]; then
  color_ram="${color_red}\e[7m"
else
  color_ram=${color_green}
fi

# get storage
storage_free_ratio=$(printf "%.0f" "$(df | grep "/$" | awk '{ print $4/$2*100 }')") 2>/dev/null
storage=$(printf "%s" "$(df -h|grep '/$'|awk '{print $4}')") 2>/dev/null

if [ "${storage_free_ratio}" -lt 10 ]; then
  color_storage="${color_red}\e[7m"
else
  color_storage=${color_green}
fi

storage2nd_free_ratio=$(printf "%.0f" "$(df  | grep ${ext_storage2nd} | awk '{ print $4/$2*100 }')") 2>/dev/null
storage2nd=$(printf "%s" "$(df -h|grep ${ext_storage2nd}|awk '{print $4}')") 2>/dev/null

if [ -z "${storage2nd}" ]; then
  storage2nd="none"
  color_storage2nd=${color_grey}
else
  storage2nd="${storage2nd} free"
  if [ "${storage2nd_free_ratio}" -lt 10 ]; then
    color_storage2nd="${color_red}\e[7m"
  else
    color_storage2nd=${color_green}
  fi
fi

# get network traffic
network_rx=$(ip -h -s link show dev ${network_name} | grep -A1 RX | tail -1 | awk '{print $1}')
network_tx=$(ip -h -s link show dev ${network_name} | grep -A1 TX | tail -1 | awk '{print $1}')

# Gather application versions
# ------------------------------------------------------------------------------
gitstatusfile="${HOME}/.raspibolt.versions.json"

save_raspibolt_versions() {
  # write to json file
  cat >${gitstatusfile} <<EOF
{
  "githubversions": {
    "bitcoin": "${btcgit}",
    "lnd": "${lndgit}",
    "cln": "${clngit}",
    "electrs": "${electrsgit}",
    "blockexplorer": "${btcrpcexplorergit}",
    "rtl": "${rtlgit}",
    "fulcrum": "${fulcrumgit}",
    "thunderhub": "${thunderhubgit}"
  }
}
EOF
}

load_raspibolt_versions() {
  btcgit=$(cat ${gitstatusfile} | jq -r '.githubversions.bitcoin')
  lndgit=$(cat ${gitstatusfile} | jq -r '.githubversions.lnd')
  clngit=$(cat ${gitstatusfile} | jq -r '.githubversions.cln')
  electrsgit=$(cat ${gitstatusfile} | jq -r '.githubversions.electrs')
  btcrpcexplorergit=$(cat ${gitstatusfile} | jq -r '.githubversions.blockexplorer')
  rtlgit=$(cat ${gitstatusfile} | jq -r '.githubversions.rtl')
  fulcrumgit=$(cat ${gitstatusfile} | jq -r '.githubversions.fulcrum')
  thunderhubgit=$(cat ${gitstatusfile} | jq -r '.githubversions.thunderhub')
}

fetch_githubversion_bitcoin() {
  btcgit=$(curl -s --connect-timeout 5 https://api.github.com/repos/bitcoin/bitcoin/releases/latest | jq -r '.tag_name | select(.!=null)')
}
fetch_githubversion_lightning() {
  ln_git_version=$(curl -s --connect-timeout 5 $ln_git_repo_url | jq -r '.tag_name | select(.!=null)')
}
fetch_githubversion_electrs() {
  electrsgit=$(curl -s --connect-timeout 5 https://api.github.com/repos/romanz/electrs/releases/latest | jq -r '.tag_name | select(.!=null)')
}
fetch_githubversion_btcrpcexplorer() {
  btcrpcexplorergit=$(curl -s --connect-timeout 5 https://api.github.com/repos/janoside/btc-rpc-explorer/releases/latest | jq -r '.tag_name | select(.!=null)')
}
fetch_githubversion_rtl() {
  rtlgit=$(curl -s --connect-timeout 5 https://api.github.com/repos/Ride-The-Lightning/RTL/releases/latest | jq -r '.tag_name | select(.!=null)')
}
fetch_githubversion_fulcrum() {
  fulcrumgit=$(curl -s --connect-timeout 5 https://api.github.com/repos/cculianu/Fulcrum/releases/latest | jq -r '.tag_name | select(.!=null)')
}
fetch_githubversion_thunderhub() {
  thunderhubgit=$(curl -s --connect-timeout 5 https://api.github.com/repos/apotdevin/thunderhub/releases/latest | jq -r '.tag_name | select(.!=null)')
}
fetch_githubversion_lnd() {
  lndgit=$(curl -s --connect-timeout 5 https://api.github.com/repos/lightningnetwork/lnd/releases/latest | jq -r '.tag_name | select(.!=null)')
}
fetch_githubversion_cln() {
  clngit=$(curl -s --connect-timeout 5 https://api.github.com/repos/ElementsProject/lightning/releases/latest | jq -r '.tag_name | select(.!=null)')
}


# Check if we should update with latest versions from github (limit to once every 6 hours)
gitupdate="0"
if [ ! -f "$gitstatusfile" ]; then
  gitupdate="1"
else
  gitupdate=$(find "${gitstatusfile}" -mmin +360 | wc -l)
fi

# Fetch or load
if [ "${gitupdate}" -eq "1" ]; then
  # Calls to github
  fetch_githubversion_bitcoin
  fetch_githubversion_lnd
  fetch_githubversion_cln
  fetch_githubversion_electrs
  fetch_githubversion_btcrpcexplorer
  fetch_githubversion_rtl
  fetch_githubversion_fulcrum
  fetch_githubversion_thunderhub
  # write to json file
  save_raspibolt_versions
else
  # load from file
  load_raspibolt_versions
fi

# Sanity check values
resaveraspibolt="0"
if [ -z "$btcgit" ]; then
  fetch_githubversion_bitcoin
  resaveraspibolt="1"
fi
if [ -z "$lndgit" ]; then
  fetch_githubversion_lnd
  resaveraspibolt="1"
fi
if [ -z "$clngit" ]; then
  fetch_githubversion_cln
  resaveraspibolt="1"
fi
if [ -z "$electrsgit" ]; then
  fetch_githubversion_electrs
  resaveraspibolt="1"
fi
if [ -z "$btcrpcexplorergit" ]; then
  fetch_githubversion_btcrpcexplorer
  resaveraspibolt="1"
fi
if [ -z "$rtlgit" ]; then
  fetch_githubversion_rtl
  resaveraspibolt="1"
fi
if [ -z "$fulcrumgit" ]; then
  fetch_githubversion_fulcrum
  resaveraspibolt="1"
fi
if [ -z "$thunderhubgit" ]; then
  fetch_githubversion_thunderhub
  resaveraspibolt="1"
fi
if [ "${resaveraspibolt}" -eq "1" ]; then
  save_raspibolt_versions
fi



# Gather Bitcoin Core data
# ------------------------------------------------------------------------------
printf "%0.s#" {1..50}
echo -ne '\r### Loading Bitcoin Core data \r'

bitcoind_running=$(systemctl is-active ${sn_bitcoin} 2>&1)
bitcoind_color="${color_green}"
if [ -z "${bitcoind_running##*inactive*}" ]; then
  bitcoind_running="down"
  bitcoind_color="${color_red}\e[7m"
else
  bitcoind_running="up"
fi
btc_path=$(command -v bitcoin-cli)
if [ -n "${btc_path}" ]; then

  # Reduce number of calls to bitcoin by doing once and caching
  bitcoincli_getblockchaininfo=$(bitcoin-cli -datadir=${bitcoin_dir} getblockchaininfo 2>&1)
  bitcoincli_getmempoolinfo=$(bitcoin-cli -datadir=${bitcoin_dir} getmempoolinfo 2>&1)
  bitcoincli_getnetworkinfo=$(bitcoin-cli -datadir=${bitcoin_dir} getnetworkinfo 2>&1)
  bitcoincli_getpeerinfo=$(bitcoin-cli -datadir=${bitcoin_dir} getpeerinfo 2>&1)

  chain="$(echo ${bitcoincli_getblockchaininfo} | jq -r '.chain')"
  btc_title="itcoin"
  btc_title="${btc_title} (${chain}net)"

  # create variable btcversion
  btcpi=$(bitcoin-cli -version |sed -n 's/^.*version //p')
  case "${btcpi}" in
    *"${btcgit}"*)
      btcversion="$btcpi"
      btcversion_color="${color_green}"
      ;;
    *)
      btcversion="$btcpi"" Update!"
      btcversion_color="${color_red}"
      ;;
  esac

  # get sync status
  block_chain="$(echo ${bitcoincli_getblockchaininfo} | jq -r '.headers')"
  block_verified="$(echo ${bitcoincli_getblockchaininfo} | jq -r '.blocks')"
  if [ -n "${block_chain}" ]; then
    block_diff=$(("${block_chain}" - "${block_verified}"))
  else
    block_diff=999999
  fi

  progress="$(echo ${bitcoincli_getblockchaininfo} | jq -r '.verificationprogress')"
  sync_percentage=$(printf "%.2f%%" "$(echo "${progress}" | awk '{print 100 * $1}')")

  if [ "${block_diff}" -eq 0 ]; then      # fully synced
    sync="OK"
    sync_color="${color_green}"
    sync_behind="[#${block_chain}]"
  elif [ "${block_diff}" -eq 1 ]; then    # fully synced
    sync="OK"
    sync_color="${color_green}"
    sync_behind="-1 block"
  elif [ "${block_diff}" -le 10 ]; then   # <= 10 blocks behind
    sync="Behind"
    sync_color="${color_red}"
    sync_behind="-${block_diff} blocks"
  else
    sync="In progress"
    sync_color="${color_red}"
    sync_behind="${sync_percentage}"
  fi

  # get mem pool transactions
  mempool=$(echo ${bitcoincli_getmempoolinfo} | jq -r '.size')

  # get connection info
  connections=$(echo ${bitcoincli_getnetworkinfo} | jq -r '.connections')
  inbound=$(echo ${bitcoincli_getpeerinfo} | jq '.[] | select(.inbound == true)' | jq -s 'length')
  outbound=$(echo ${bitcoincli_getpeerinfo} | jq '.[] | select(.inbound == false)' | jq -s 'length')
fi

# create variable btcversion
btcpi=$(bitcoin-cli -version |sed -n 's/^.*version //p')
case "${btcpi}" in
  *"${btcgit}"*)
    btcversion="$btcpi"
    btcversion_color="${color_green}"
    ;;
  *)
    btcversion="$btcpi"" Update!"
    btcversion_color="${color_red}"
    ;;
esac


# Gather LN data based on preferred implementation
# ------------------------------------------------------------------------------
printf "%0.s#" {1..60}

load_lightning_data() {
  lnd_infofile="${HOME}/.raspibolt.lndata.json"
  ln_file_content=$(cat $lnd_infofile)
  ln_color="$(echo $ln_file_content | jq -r '.ln_color')"
  ln_version_color="$(echo $ln_file_content | jq -r '.ln_version_color')"
  alias_color="$(echo $ln_file_content | jq -r '.alias_color')"
  ln_running="$(echo $ln_file_content | jq -r '.ln_running')"
  ln_version="$(echo $ln_file_content | jq -r '.ln_version')"
  ln_walletbalance="$(echo $ln_file_content | jq -r '.ln_walletbalance')"
  ln_channelbalance="$(echo $ln_file_content | jq -r '.ln_channelbalance')"
  ln_pendinglocal="$(echo $ln_file_content | jq -r '.ln_pendinglocal')"
  ln_sum_balance="$(echo $ln_file_content | jq -r '.ln_sum_balance')"
  ln_channels_online="$(echo $ln_file_content | jq -r '.ln_channels_online')"
  ln_channels_total="$(echo $ln_file_content | jq -r '.ln_channels_total')"
  ln_channel_db_size="$(echo $ln_file_content | jq -r '.ln_channel_db_size')"
  ln_connect_guidance="$(echo $ln_file_content | jq -r '.ln_connect_guidance')"
  ln_alias="$(echo $ln_file_content | jq -r '.ln_alias')"
  ln_sync_note1="$(echo $ln_file_content | jq -r '.ln_sync_note1')"
  ln_sync_note1_color="$(echo $ln_file_content | jq -r '.ln_sync_note1_color')"
  ln_sync_note2="$(echo $ln_file_content | jq -r '.ln_sync_note2')"
  ln_sync_note2_color="$(echo $ln_file_content | jq -r '.ln_sync_note2_color')"
}

# Prepare Lightning output data (name, version, data lines)
# ------------------------------------------------------------------------------
echo -ne '\r### Loading Lightning data \r'
lserver_found=0
lserver_label="No Lightning Server"
lserver_running=""
lserver_color="${color_red}\e[7m"
lserver_version=""
lserver_version_color="${color_red}"
lserver_dataline_1="${color_grey}"
lserver_dataline_2="${color_grey}"
lserver_dataline_3="${color_grey}"
lserver_dataline_4="${color_grey}"
lserver_dataline_5="${color_grey}"
lserver_dataline_6="${color_grey}"
lserver_dataline_7="${color_grey}"
ln_footer=""
lnd_status=$(systemctl is-enabled $sn_lnd 2>&1)
cln_status=$(systemctl is-enabled $sn_cln 2>&1)
# Mock specific
if [ "${mockmode}" -eq 1 ]; then
  ln_alias="MyRaspiBolt-version3"
  ln_walletbalance="100000"
  ln_channelbalance="200000"
  ln_pendinglocal="50000"
  ln_sum_balance="350000"
  ln_channels_online="34"
  ln_channels_total="36"
  ln_channel_db_size="615M"
  ln_connect_guidance="lncli connect cdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd@version3onionaddressgobbLedegookLookingL3ttersandnumbers.onion:9735"
  lserver_label="Lightning (MOCK)"
  lserver_running="up"
  lserver_color="${color_green}"
  lserver_version="v0.6.15"
  lserver_version_color="${color_green}"
  alias_color="${color_magenta}"
  ln_footer=$(printf "For others to connect to this lightning node: ${alias_color}${ln_alias}${color_grey}\n${ln_connect_guidance}")
  # data lines
  lserver_dataline_1=$(printf "${color_grey}Sync%10s" "ready")
  lserver_dataline_2=$(printf "${color_orange}"₿"${color_grey}%18s sat" "${ln_walletbalance}")
  lserver_dataline_3=$(printf "${color_grey}%3s %16s sat" "⚡" "${ln_channelbalance}")
  lserver_dataline_4=$(printf "${color_grey}%3s %16s sat" "∑" "${ln_sum_balance}")
  lserver_dataline_5=$(printf "${color_grey}%s/%s channels" "${ln_channels_online}" "${ln_channels_total}")
  lserver_dataline_6=$(printf "${color_grey}Channel.db size: ${color_green}%s" "${ln_channel_db_size}")
# LND specific
elif [ "$lnd_status" = "enabled" ]; then
  lnd_status=$(systemctl is-active $sn_lnd 2>&1)
  lserver_found=1
  lserver_label="Lightning (LND)"
  lserver_running="down"
  if [ "$lnd_status" = "active" ]; then
    lserver_running="up"
    lserver_color="${color_green}"
    # version specific stuff
    "$(dirname "$0")/get_LND_data.sh" $chain $color_green $color_red $lndgit
    load_lightning_data
    lserver_version="$(echo $ln_file_content | jq -r '.ln_version')"
    lserver_version_color="$(echo $ln_file_content | jq -r '.ln_version_color')"
    ln_footer=$(printf "For others to connect to this lightning node: ${alias_color}${ln_alias}${color_grey}\n${ln_connect_guidance}")
    # data lines
    lserver_dataline_1=$(printf "${color_grey}Sync${ln_sync_note1_color}%10s${ln_sync_note2_color}%9s" "${ln_sync_note1}" "${ln_sync_note2}")
    lserver_dataline_2=$(printf "${color_orange}"₿"${color_grey}%18s sat" "${ln_walletbalance}")
    lserver_dataline_3=$(printf "${color_grey}%3s %17s sat" "⚡" "${ln_channelbalance}")
    lserver_dataline_4=$(printf "${color_grey}%3s %17s sat" "⏳" "${ln_pendinglocal}")
    lserver_dataline_5=$(printf "${color_grey}%3s %17s sat" "∑" "${ln_sum_balance}")
    lserver_dataline_6=$(printf "${color_grey}%s/%s channels" "${ln_channels_online}" "${ln_channels_total}")
    lserver_dataline_7=$(printf "${color_grey}Channel.db size: ${color_green}%s" "${ln_channel_db_size}")
  fi
# Core Lightning specific
elif [ "$cln_status" = "enabled" ];  then
  cln_status=$(systemctl is-active $sn_cln 2>&1)
  lserver_found=1
  lserver_label="Lightning (CLN)"
  lserver_running="down"
  if [ "$cln_status" = "active" ]; then
    lserver_running="up"
    lserver_color="${color_green}"
    # version specific stuff
    "$(dirname "$0")/get_CLN_data.sh" $chain $color_green $color_red $clngit
    load_lightning_data
    lserver_version="$(echo $ln_file_content | jq -r '.ln_version')"
    lserver_version_color="$(echo $ln_file_content | jq -r '.ln_version_color')"
    ln_footer=$(printf "For others to connect to this lightning node: ${alias_color}${ln_alias}${color_grey}\n${ln_connect_guidance}")
    # data lines
    lserver_dataline_1=$(printf "${color_grey}Sync${ln_sync_note1_color}%10s${ln_sync_note2_color}%9s" "${ln_sync_note1}" "${ln_sync_note2}")
    lserver_dataline_2=$(printf "${color_orange}"₿"${color_grey}%18s sat" "${ln_walletbalance}")
    lserver_dataline_3=$(printf "${color_grey}%3s %17s sat" "⚡" "${ln_channelbalance}")
    lserver_dataline_4=$(printf "${color_grey}%3s %17s sat" "∑" "${ln_sum_balance}")
    lserver_dataline_5=$(printf "${color_grey}%s/%s channels" "${ln_channels_online}" "${ln_channels_total}")
    lserver_dataline_6=$(printf "${color_grey}Lightning DB size: ${color_green}%s" "${ln_channel_db_size}")
  fi
# ... add any future supported lightning server implementation checks here
fi
if [ "$lserver_found" -eq 0 ]; then
  lserver_color="${color_grey}"
fi



# Gather Electrs or Fulcrum data
# ------------------------------------------------------------------------------
printf "%0.s#" {1..65}
echo -ne '\r### Loading Electrum Server data \r'
eserver_found=0
eserver_label="No Electrum Server"
eserver_running=""
eserver_color="${color_red}\e[7m"
eserver_version=""
eserver_version_color="${color_red}"
electrs_status=$(systemctl is-enabled ${sn_electrs} 2>&1)
fulcrum_status=$(systemctl is-enabled ${sn_fulcrum} 2>&1)
# Electrs specific
if [ "$electrs_status" = "enabled" ]; then
  electrs_status=$(systemctl is-active ${sn_electrs} 2>&1)
  eserver_found=1
  eserver_label="Electrs"
  eserver_running="down"
  if [ "$electrs_status" = "active" ]; then
    eserver_running="up"
    eserver_color="${color_green}"
    # Request params are client_name, protocol_version. Example result being parsed: ["Electrs 0.9.10", "1.4"]
    electrspi=$(echo '{"jsonrpc": "2.0", "method": "server.version", "params": [ "raspibolt", "1.4" ], "id": 0}' | netcat 127.0.0.1 50001 -q 1 | jq -r '.result[0]' | awk '{print "v"substr($1,9)}')
    if [ "$electrspi" = "$electrsgit" ]; then
      eserver_version="$electrspi"
      eserver_version_color="${color_green}"
    else
      eserver_version="$electrspi"" Update!"
    fi
  fi
# Fulcrum specific
elif [ "$fulcrum_status" = "enabled" ];  then
  fulcrum_status=$(systemctl is-active ${sn_fulcrum} 2>&1)
  eserver_found=1
  eserver_label="Fulcrum"
  eserver_running="down"
  if [ "$fulcrum_status" = "active" ]; then
    eserver_running="up"
    eserver_color="${color_green}"
    fulcrumpi=$(Fulcrum --version | grep Fulcrum | awk '{print "v"$2}')
    if [ "$fulcrumpi" = "$fulcrumgit" ]; then
      eserver_version="$fulcrumpi"
      eserver_version_color="${color_green}"
    else
      eserver_version="$fulcrumpi"" Update!"
    fi
  fi
# ... add any future supported electrum server implementation checks here
fi
if [ "$eserver_found" -eq 0 ]; then
  eserver_color="${color_grey}"
fi



# Gather Bitcoin Explorer data
# ------------------------------------------------------------------------------
printf "%0.s#" {1..70}
echo -ne '\r### Loading Block Explorer data \r'
bserver_found=0
bserver_label="No Block Explorer"
bserver_running=""
bserver_color="${color_red}\e[7m"
bserver_version=""
bserver_version_color="${color_red}"
btcrpcexplorer_status=$(systemctl is-enabled ${sn_btcrpcexplorer} 2>&1)
# BTC RPC Explorer specific
if [ "$btcrpcexplorer_status" = "enabled" ]; then
  btcrpcexplorer_status=$(systemctl is-active ${sn_btcrpcexplorer} 2>&1)
  bserver_found=1
  bserver_label="Bitcoin Explorer"
  bserver_running="down"
  if [ "$btcrpcexplorer_status" = "active" ]; then
    bserver_running="up"
    bserver_color="${color_green}"
    btcrpcexplorerpi=v$(cd /home/${un_btcrpcexplorer}/btc-rpc-explorer; npm version | grep -oP "'btc-rpc-explorer': '\K(.*)(?=')")
    if [ "$btcrpcexplorerpi" = "$btcrpcexplorergit" ]; then
      bserver_version="$btcrpcexplorerpi"
      bserver_version_color="${color_green}"
    else
      bserver_version="$btcrpcexplorerpi"" Update!"
    fi
  fi
# ... add any future supported blockchain explorer implementation checks here
fi
if [ "$bserver_found" -eq 0 ]; then
  bserver_color="${color_grey}"
fi



# Gather Lightning Web App data
# ------------------------------------------------------------------------------
printf "%0.s#" {1..75}
echo -ne '\r### Loading Lightning Web App \r'

lwserver_found=0
lwserver_label="No Lightning Web App"
lwserver_running=""
lwserver_color="${color_red}\e[7m"
lwserver_version=""
lwserver_version_color="${color_red}"
rtl_status=$(systemctl is-enabled ${sn_rtl} 2>&1)
thunderhub_status=$(systemctl is-enabled ${sn_thunderhub} 2>&1)
# Ride the Ligthning specific
if [ "$rtl_status" = "enabled" ]; then
  rtl_status=$(systemctl is-active ${sn_rtl} 2>&1)
  lwserver_found=1
  lwserver_label="Ride the Lightning"
  lwserver_running="down"
  if [ "$rtl_status" = "active" ]; then
    lwserver_running="up"
    lwserver_color="${color_green}"
    rtlpi=v$(cd /home/${un_rtl}/RTL; npm version | grep -oP "rtl: '\K(.*)(?=-beta')")
    if [ "$rtlpi" = "$rtlgit" ]; then
      lwserver_version="$rtlpi"
      lwserver_version_color="${color_green}"
    else
      lwserver_version="$rtlpi"" Update!"
    fi
  fi
# Thunderhub specific
elif [ "$thunderhub_status" = "enabled" ]; then
  thunderhub_status=$(systemctl is-active ${sn_thunderhub} 2>&1)
  lwserver_found=1
  lwserver_label="Thunderhub"
  lwserver_running="down"
  if [ "$thunderhub_status" = "active" ]; then
    lwserver_running="up"
    lwserver_color="${color_green}"
    thunderhubpi=v$(cd /home/${un_thunderhub}/thunderhub; npm version | grep -oP "thunderhub: '\K(.*)(?=-beta')")
    if [ "$thunderhubpi" = "$thunderhubgit" ]; then
      lwserver_version="$thunderhubpi"
      lwserver_version_color="${color_green}"
    else
      lwserver_version="$thunderhubpi"" Update!"
    fi
  fi
# ... add any future supported lightning web app implementation checks here
fi
if [ "$lwserver_found" -eq 0 ]; then
  lwserver_color="${color_grey}"
fi


# Render output
# ------------------------------------------------------------------------------

echo -ne "\033[2K"
printf "${color_grey}cpu temp: ${color_temp}%-2s°C${color_grey}  tx: %-10s storage:   ${color_storage}%-11s ${color_grey}  load: %s${color_grey}
${color_grey}up: %-10s  rx: %-10s 2nd drive: ${color_storage2nd}%-11s${color_grey}   available mem: ${color_ram}%sM${color_grey}
${color_yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${color_grey}
${color_green}     .~~.   .~~.      ${color_orange}"₿"${color_yellow}%-19s${bitcoind_color}%-4s${color_grey}   ${color_yellow}%-20s${lserver_color}%-4s${color_grey}
${color_green}    '. \ ' ' / .'     ${btcversion_color}%-26s ${lserver_version_color}%-24s${color_grey}
${color_red}     .~ .~~~${color_yellow}.${color_red}.~.      ${color_grey}Sync    ${sync_color}%-18s ${lserver_dataline_1}${color_grey}
${color_red}    : .~.'${color_yellow}／/${color_red}~. :     ${color_grey}Mempool %-18s ${lserver_dataline_2}${color_grey}
${color_red}   ~ (  ${color_yellow}／ /_____${color_red}~    ${color_grey}Peers   %-22s ${lserver_dataline_3}${color_grey}
${color_red}  ( : ${color_yellow}／____   ／${color_red} )                              ${lserver_dataline_4}${color_grey}
${color_red}   ~ .~ (  ${color_yellow}/ ／${color_red}. ~    ${color_yellow}%-20s${eserver_color}%-4s${color_grey}   ${lserver_dataline_5}${color_grey}
${color_red}    (  : '${color_yellow}/／${color_red}:  )     ${eserver_version_color}%-26s ${lserver_dataline_6}${color_grey}
${color_red}     '~ .~${color_yellow}°${color_red}~. ~'                                 ${lserver_dataline_7}${color_grey}
${color_red}         '~'          ${color_yellow}%-20s${color_grey}${bserver_color}%-4s${color_grey}
${color_red}                      ${bserver_version_color}%-24s${color_grey}   ${color_yellow}%-20s${lwserver_color}%-4s${color_grey}
${color_red}                                                 ${lwserver_version_color}%-24s${color_grey}

${color_grey}%s

" \
"${temp}" "${network_tx}" "${storage} free" "${load}" \
"${uptime}" "${network_rx}" "${storage2nd}" "${ram_avail}" \
"${btc_title}" "${bitcoind_running}" "${lserver_label}" "${lserver_running}" \
"${btcversion}" "${lserver_version}" \
"${sync} ${sync_behind}" \
"${mempool} tx" \
"${connections} (📥${inbound} /📤${outbound})"  \
"${eserver_label}" "${eserver_running}" \
"${eserver_version}" \
"${bserver_label}" "${bserver_running}" \
"${bserver_version}" "${lwserver_label}" "${lwserver_running}" \
"${lwserver_version}" \
"${ln_footer}"
