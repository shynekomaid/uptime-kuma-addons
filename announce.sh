#!/bin/bash
# Uptime Kuma monitor statuses parser
# Author: shyneko
# This script is must runned in 00:00:01 UTC time every day
# To add this script to cron, run command: crontab -e (without sudo)
# Add this line to crontab: 1 0 * * * /home/shyneko/scr/svitloharci.sh
# This script send in telegram message about yesterday status of monitors
# Requirements:
# jq, sqlite3 (3.32.0 or higher), uptime-kuma (1.19.4 or higher recommended)
# For 18.04 LTS: sudo add-apt-repository ppa:fbirlik/sqlite3 -y && sudo apt update && sudo apt install sqlite3 -y
# This script is tested on Mint 21.1, Ubuntu 18.04.1 LTS
# This script is tested on Uptime Kuma 1.19.4

declare -gA settings=(
  [db_file]="/home/shyneko/uptime-kuma/data/kuma.db"
  [notification_id]=4
  # [db_file]="/home/shyneko/Desktop/kuma.db"
  # [notification_id]=1
  [sqlite_path]="/usr/bin/sqlite3"
  # [sqlite_path]="/usr/bin/sqlite3"
  [jq_path]="/usr/bin/jq"
  [timezone]="Europe/Kiev"
)

declare -gA lang_current=(
  [no_statuses]="Немає статусів для монітора [%monitor_name] за минулу добу"
  [yesterday_statuses]="Статуси монітора [%monitor_name] за минулу добу:"
  [no_data_for_monitor]="Немає даних для монітора [%monitor_name]"
  [status1]="🟩"
  [status0]="🟥"
  [status_empty]="⬜️"
  [total_time]="Загальний час cвітлохарчування"
  [relative_time]="Відсоток часу світлохарчування"
  [last_time]="D: "
  [alpha_time]="початок відліку"
  [omega_time]="кінець відліку"
  [h]="год"
  [m]="хв"
  [s]="сек"
)

export TZ="${settings[timezone]}"

seconds_in_day=86400
yesterday_start_time=$(date -d "yesterday 00:00:00" +%s)
yesterday_end_time=$(date -d "yesterday 23:59:59" +%s)

function parseStatuses() {
  local monitor_name="$1"
  local statuses="$2"
  local monitor_created="$3"
  local message=""
  local seconds_between=0
  local total_seconds=0
  local last_status
  monitor_created=$(date -d "${monitor_created}" +%s)
  if [[ -z "${statuses}" ]]; then
    message="${lang_current[no_statuses]}"
    message="${message//%monitor_name/${monitor_name}}"
    echo "$message"
    return 0
  fi
  statuses="${statuses// /'_'}"
  statuses=(${statuses//$'\n'/ })
  message="${lang_current[yesterday_statuses]}"
  message="${message//%monitor_name/${monitor_name}}"
  message+=$'\n'
  message+=$'\n'
  last_time="$yesterday_start_time"
  # Get the monitor creation time. If it > last_time, then set point_time = monitor creation time else set point_time = last_time
  local point_time
  local sum_diff=0 # all difference between monitor creation time and last_time
  if [[ "$monitor_created" -gt "$last_time" ]]; then
    point_time="$monitor_created"
    sum_diff=$((monitor_created - last_time))
  else
    point_time="$last_time"
  fi
  # zero_time = parse unixtime of point_time
  zero_time=$(date -d "@${point_time}" +%H:%M:%S)
  message+="${lang_current[status_empty]} ${zero_time} [%alpha_time]"
  message="${message//%alpha_time/${lang_current[alpha_time]}}"
  message+=$'\n'
  for status in "${statuses[@]}"; do
    time=$(echo "$status" | cut -d'|' -f1)
    time="${time//_/ }"
    unixtime=$(echo "$status" | cut -d'|' -f2)
    time=$(date -d "${time}" +%H:%M:%S)
    status=$(echo "$status" | cut -d'|' -f3)
    seconds_between=$((unixtime - point_time))
    if [[ "$status" == "1" ]]; then
      message+=${lang_current[status1]}
    else
      message+=${lang_current[status0]}
      total_seconds=$((total_seconds + seconds_between))
    fi
    h_between=$((seconds_between / 3600))
    m_between=$((seconds_between % 3600 / 60))
    s_between=$((seconds_between % 60))
    message+=" ${time} [%last_time ${h_between}%h ${m_between}%m ${s_between}%s]"
    message="${message//%last_time/${lang_current[last_time]}}"
    message="${message//%h/${lang_current[h]}}"
    message="${message//%m/${lang_current[m]}}"
    message="${message//%s/${lang_current[s]}}"
    message+=$'\n'
    point_time="$unixtime"
  done
  # remove last \n from message
  message=${message%$'\n'}
  last_status=$(echo "${statuses[-1]}" | cut -d'|' -f3)
  seconds_between=$((yesterday_end_time - point_time))
  if [[ "$last_status" == "1" ]]; then
    total_seconds=$((total_seconds + seconds_between))
  fi
  total_seconds=$((total_seconds - sum_diff)) # remove difference between monitor creation time and last_time
  full_time="$yesterday_end_time"
  # full_time = parse unixtile of yesterday_end_time
  message+=$'\n'
  h_between=$((seconds_between / 3600))
  m_between=$((seconds_between % 3600 / 60))
  s_between=$((seconds_between % 60))
  full_time=$(date -d "@${full_time}" +%H:%M:%S)
  message+="${lang_current[status_empty]} ${full_time}"
  message+=" [%last_time ${h_between}%h ${m_between}%m ${s_between}%s] [%omega_time]"
  message="${message//%last_time/${lang_current[last_time]}}"
  message="${message//%omega_time/${lang_current[omega_time]}}"
  message+=$'\n'
  hours=$((total_seconds / 3600))
  minutes=$((total_seconds % 3600 / 60))
  seconds=$((total_seconds % 60))
  message+=$'\n'
  message+="%total_time: ${hours}%h ${minutes}%m ${seconds}%s [${total_seconds}%s]"
  message="${message//%total_time/${lang_current[total_time]}}"
  message="${message//%h/${lang_current[h]}}"
  message="${message//%m/${lang_current[m]}}"
  message="${message//%s/${lang_current[s]}}"
  message+=$'\n'
  relative_time=$((total_seconds * 10000 / seconds_in_day))
  presition=2
  if [[ "$relative_time" -lt 1000 ]]; then
    presition=3
  fi
  if [[ "$relative_time" -gt 10000 ]]; then
    presition=0
  fi
  relative_time=$(echo "scale=$presition; $relative_time / 100" | bc)
  message+="%relative_time: ${relative_time}%"
  message="${message//%relative_time/${lang_current[relative_time]}}"
  echo "$message"
  return 0
}

function sendTelegramMessage() {
  local message="$1"
  local chat_id="$2"
  local token="$3"
  local thread_id="$4"
  message=$(echo "$message" | jq -s -R -r @uri)
  local url="https://api.telegram.org/bot${token}/sendMessage"
  local data="chat_id=${chat_id}&text=${message}"
  if [[ -n "$thread_id" ]]; then
    data+="&message_thread_id=${thread_id}"
  fi
  curl -s -X POST "$url" -d "$data"
  return 0
}

if ! command -v "${settings[sqlite_path]}" &>/dev/null; then
  echo "sqlite3 could not be found"
  echo "Install it with: sudo apt install sqlite3"
  exit
fi

sqlite_version=$("${settings[sqlite_path]}" --version | cut -d' ' -f1 | cut -d'.' -f1,2)
if [[ "$(echo "$sqlite_version < 3.32" | bc)" -eq 1 ]]; then
  echo "sqlite3 version is too old (3.32+ required)"
  echo "Download latest version from: https://sqlite.org/download.html"
  exit
fi

if ! command -v "${settings[jq_path]}" &>/dev/null; then
  echo "jq could not be found"
  echo "Install it with: sudo apt install jq"
  exit
fi

if ! [[ -f "${settings[db_file]}" ]]; then
  echo "db file could not be found"
  exit
fi

if ! [[ -r "${settings[db_file]}" ]]; then
  echo "db file is not readable"
  exit
fi

# Get the notification object
declare notifications_data_req="SELECT active, config, name FROM notification WHERE id = ${settings[notification_id]};"

notifications_data="$("${settings[sqlite_path]}" -batch "${settings[db_file]}" "${notifications_data_req}")"

unset notifications_data_req

# Check if the query returned anything
if [[ -z "${notifications_data}" ]]; then
  echo "Cannot find notification object with id ${settings[notification_id]}"
  exit
fi

# If active is 0, then the notification is disabled
if [[ "$(echo "${notifications_data}" | cut -d'|' -f1)" == "0" ]]; then
  echo "Notification is disabled"
  exit
fi

# Get the config
config="$(echo "${notifications_data}" | cut -d'|' -f2)"
config="$(echo "${config}" | "${settings[jq_path]}" -r '.')"

if [[ -z "${config}" ]]; then
  echo "Cannot parse config"
  exit
fi

if [[ "$(echo "${config}" | "${settings[jq_path]}" -r '.type')" != "telegram" ]]; then
  echo "Notification type is not telegram"
  exit
fi

# Get monitor ids
declare monitor_list_req="SELECT DISTINCT monitor_id FROM monitor_notification WHERE notification_id=${settings[notification_id]}"

monitor_list="$("${settings[sqlite_path]}" -batch "${settings[db_file]}" "${monitor_list_req}")"

unset monitor_list_req

if [[ -z "${monitor_list}" ]]; then
  echo "Cannot find any monitors for notification id ${settings[notification_id]}"
  exit
fi

monitor_list_str="$(echo "${monitor_list}" | tr '\n' ',' | sed 's/,$//')"

echo "Monitor full list: ${monitor_list_str//,/, }"

yesterday_date=$(date -d "yesterday" +%Y-%m-%d)

status_get_req="WITH cte AS (SELECT id, status, time, status = LAG(status, 1, 1) OVER ( ORDER BY id) AS is_same FROM heartbeat WHERE monitor_id = %monitor AND important = 1) SELECT datetime(time, 'localtime') AS time, CAST(strftime('%s', time) AS INT) AS unixtime, status FROM cte WHERE is_same = 0 AND date(time, 'localtime') = '${yesterday_date}' AND time(time, 'localtime') BETWEEN '00:00:00' AND '23:59:59' AND status BETWEEN '0' AND '1'"

active_moniors_list_req="SELECT id FROM monitor WHERE id IN (${monitor_list_str}) AND active = 1"

active_monitors_list="$("${settings[sqlite_path]}" -batch "${settings[db_file]}" "${active_moniors_list_req}")"

unset active_moniors_list_req

if [[ -z "${active_monitors_list}" ]]; then
  echo "Cannot find any active monitors for notification id ${settings[notification_id]}"
  exit
fi

active_monitors_list_str="$(echo "${active_monitors_list}" | tr '\n' ',' | sed 's/,$//')"

echo "Active monitors list: ${active_monitors_list_str//,/, }"

for monitor_id in ${monitor_list}; do
  if ! [[ "${active_monitors_list_str}" =~ ${monitor_id} ]]; then
    continue
  fi
  echo ""
  active_monior_get_req="SELECT name, created_date FROM monitor WHERE id = ${monitor_id}"
  active_monior_get_data="$("${settings[sqlite_path]}" -batch "${settings[db_file]}" "${active_monior_get_req}")"
  active_monior_name="$(echo "${active_monior_get_data}" | cut -d'|' -f1)"
  active_monior_created_date="$(echo "${active_monior_get_data}" | cut -d'|' -f2)"
  unset active_monior_get_req
  result="$("${settings[sqlite_path]}" -batch "${settings[db_file]}" "${status_get_req//%monitor/${monitor_id}}")"
  if [[ -z "${result}" ]]; then
    echo "Cannot find any status for monitor id ${monitor_id}"
    # TODO: Send message to telegram that monitor is not have any status
    message="${lang_current[no_data_for_monitor]}"
    message="${message//%monitor_name/${monitor_name}}"
    sendTelegramMessage "${message}" "$(echo "${config}" | "${settings[jq_path]}" -r '.telegramChatID')" "$(echo "${config}" | "${settings[jq_path]}" -r '.telegramBotToken')" "$(echo "${config}" | "${settings[jq_path]}" -r '.telegramChatThread')"
    sleep 1 # prevent telegram flood limit
    continue
  fi
  telegram_send_message=$(parseStatuses "$active_monior_name" "$result" "$active_monior_created_date")
  sendTelegramMessage "${telegram_send_message}" "$(echo "${config}" | "${settings[jq_path]}" -r '.telegramChatID')" "$(echo "${config}" | "${settings[jq_path]}" -r '.telegramBotToken')" "$(echo "${config}" | "${settings[jq_path]}" -r '.telegramChatThread')"
  sleep 1 # prevent telegram flood limit
done
