#!/bin/bash
chain=$1
color_green=$2
color_red=$3
ln_git_version=$4


echo -ne '\r### Loading CoreLN data \r'

ln_running=$(systemctl is-active cln)
coreln_color="${color_green}"
if [ -z "${ln_running##*inactive*}" ]; then
  ln_running="down"
  coreln_color="${color_red}\e[7m"
else
  if [ -z "${ln_running##*failed*}" ]; then
    ln_running="down"
    coreln_color="${color_red}\e[7m"
  else
    ln_running="up"
  fi
fi
lncli="/home/cln/lightning/cli/lightning-cli"

printf "%0.s#" {1..63}
echo -ne '\r### Loading CoreLN data \r'


alias_color="${color_grey}"
ln_alias="$(${lncli} getinfo | jq -r '.alias')" 2>/dev/null

# Reduce number of calls to LND by doing once and caching
lncli_getinfo=$(${lncli} getinfo)
lncli_listfunds=$(${lncli} listfunds)

ln_walletbalance=0
#check if len(outputs) == 0 --> empty wallet
amount_of_wallet_transactions=$(echo ${lncli_listfunds} | jq -r '.outputs | length')
if [ $amount_of_wallet_transactions -gt 0 ];then
ln_walletbalance=$(echo ${lncli_listfunds} | jq -r '.outputs[0].value | tonumber')
fi

## Show channel balance
ln_channelbalance=0
#check if len(channels) == 0 --> no channels
amount_of_channels=$(echo ${lncli_listfunds} | jq -r '.channels | length')
if [ $amount_of_channels -gt 0 ];then
ln_channelbalance=$(echo ${lncli_listfunds} | jq -r '.channels[0].our_amount_msat // 0 | gsub("msat";"") | tonumber' | awk '{print $1/1000}')
fi
printf "%0.s#" {1..66}

echo -ne '\r### Loading CoreLN data \r'

ln_channels_online=$(echo ${lncli_getinfo} | jq -r '.num_active_channels | tonumber') 2>/dev/null
ln_channels_pending=$(echo ${lncli_getinfo} | jq -r '.num_pending_channels | tonumber') 2>/dev/null
ln_channels_inactive=$(echo ${lncli_getinfo} | jq -r '.num_inactive_channels | tonumber') 2>/dev/null
ln_channels_total=$((ln_channels_online + ln_channels_pending + ln_channels_inactive))
node_id=$(echo ${lncli_getinfo} | jq -r '.id') 2>/dev/null
node_address=$(echo ${lncli_getinfo} | jq -r '.address[0].address') 2>/dev/null
node_port=$(echo ${lncli_getinfo} | jq -r '.address[0].port') 2>/dev/null
ln_connect_addr="$node_id"@"$node_address":"$node_port" 2>/dev/null
ln_connect_guidance="lightning-cli connect ${ln_connect_addr}"
if [ -z "${node_addr##*onion*}" ]; then
  ln_external="Using TOR Address"
else
  ln_external="Using Clearnet"
fi

printf "%0.s#" {1..70}
# echo -ne '\r### Loading LND data \r'

# ln_pendingopen=$(echo ${lncli_pendingchannels} | jq '.pending_open_channels[].channel.local_balance|tonumber ' | awk '{sum+=$0} END{print sum}')
# if [ -z "${ln_pendingopen}" ]; then
#   ln_pendingopen=0
# fi

# ln_pendingforce=$(echo ${lncli_pendingchannels} | jq '.pending_force_closing_channels[].channel.local_balance|tonumber ' | awk '{sum+=$0} END{print sum}')
# if [ -z "${ln_pendingforce}" ]; then
#   ln_pendingforce=0
# fi

# ln_waitingclose=$(echo ${lncli_pendingchannels} | jq '.waiting_close_channels[].channel.local_balance|tonumber ' | awk '{sum+=$0} END{print sum}')
# if [ -z "${ln_waitingclose}" ]; then
#   ln_waitingclose=0
# fi

# echo -ne '\r### Loading LND data \r'

# ln_pendinglocal=$((ln_pendingopen + ln_pendingforce + ln_waitingclose))
ln_pendinglocal=0

ln_sum_balance=0
if [ -n "${ln_channelbalance}" ]; then
  ln_sum_balance=$((ln_channelbalance + ln_sum_balance ))
fi
if [ -n "${ln_walletbalance}" ]; then
  ln_sum_balance=$((ln_walletbalance + ln_sum_balance ))
fi
if [ -n "$ln_pendinglocal" ]; then
  ln_sum_balance=$((ln_sum_balance + ln_pendinglocal ))
fi


#create variable ln_version
lndpi=$($lncli getinfo |jq -r '.version')
if [ "${lndpi}" = "${ln_git_version}" ]; then
  ln_version="${lndpi}"
  ln_version_color="${color_green}"
else
  ln_version="${lndpi}"" Update!"
  ln_version_color="${color_red}"
fi

#create variables for ln_sync
ln_sync_warning_bitcoind=$(echo ${lncli_getinfo} | jq -r '.warning_bitcoind_sync') 2>/dev/null
ln_sync_warning_lightningd=$(echo ${lncli_getinfo} | jq -r '.warning_lightningd_sync') 2>/dev/null
ln_sync_note2_color="${color_red}"
ln_sync_note2=""
if [ "${ln_sync_warning_bitcoind}" = "null" ]; then
  if [ "${ln_sync_warning_lightningd}" = "null" ]; then
    ln_sync_note1_color="${color_green}"
    ln_sync_note1="chain:OK"
  else
    ln_sync_note1_color="${color_red}"
    ln_sync_note1="chain:No"
  fi
else
  ln_sync_note1_color="${color_red}"
  ln_sync_note1="chain:No"
fi

#get channel.db size
coreln_dir="/data/cln"
ln_channel_db_size=$(du -h ${coreln_dir}/bitcoin/lightningd.sqlite3 | awk '{print $1}')

# Write to JSON file
lnd_infofile="${HOME}/.raspibolt.lndata.json"
ln_color=$(echo $coreln_color | sed 's/\\/\\\\/g')
lnversion_color=$(echo $lndversion_color | sed 's/\\/\\\\/g')
alias_color=$(echo $alias_color| sed 's/\\/\\\\/g')
ln_sync_note1_color=$(echo $ln_sync_note1_color | sed 's/\\/\\\\/g')
ln_sync_note2_color=$(echo $ln_sync_note2_color | sed 's/\\/\\\\/g')
printf '{"ln_running":"%s","ln_version":"%s","ln_walletbalance":"%s","ln_channelbalance":"%s","ln_pendinglocal":"%s","ln_sum_balance":"%s","ln_channels_online":"%s","ln_channels_total":"%s","ln_channel_db_size":"%s","ln_color":"%s","ln_version_color":"%s","alias_color":"%s","ln_alias":"%s","ln_connect_guidance":"%s","ln_sync_note1":"%s","ln_sync_note1_color":"%s","ln_sync_note2":"%s","ln_sync_note2_color":"%s"}' "\
$ln_running" "$ln_version" "$ln_walletbalance" "$ln_channelbalance" "$ln_pendinglocal" "$ln_sum_balance" "$ln_channels_online" "$ln_channels_total" "$ln_channel_db_size" "$ln_color" "$lnversion_color" "$alias_color" "$ln_alias" "$ln_connect_guidance" "$ln_sync_note1" "$ln_sync_note1_color" "$ln_sync_note2" "$ln_sync_note2_color" > $lnd_infofile
