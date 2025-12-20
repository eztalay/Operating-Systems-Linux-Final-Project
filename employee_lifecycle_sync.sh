#!/bin/bash
set -euo pipefail

#######################################
# CONFIG
#######################################

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

EMPLOYEE_CSV="$BASE_DIR/employees.csv"

OUTPUT_DIR="$BASE_DIR/output"
LOG_DIR="$OUTPUT_DIR/logs"
REPORT_DIR="$OUTPUT_DIR/reports"
ARCHIVE_DIR="$OUTPUT_DIR/archives"
LAST_CSV="$OUTPUT_DIR/last_employees.csv"

RUN_ID="$(date "+%Y%m%d_%H%M%S")"
LOG_FILE="$LOG_DIR/run_$RUN_ID.log"
REPORT_FILE="$REPORT_DIR/manager_report_$RUN_ID.txt"

MANAGER_EMAIL="elifzafer053@gmail.com"

declare -A CURRENT_STATUS
declare -A CURRENT_DEPT
declare -A CURRENT_NAME

#######################################
# HELPER
#######################################

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log() {
  echo "[$(timestamp)] $1" | tee -a "$LOG_FILE"
}

run_cmd() {
  # Artık DRY-RUN YOK: komutlar gerçekten çalışıyor
  log "[RUN] $*"
  eval "$@"
}

ensure_dirs() {
  mkdir -p "$LOG_DIR" "$REPORT_DIR" "$ARCHIVE_DIR"
  touch "$LOG_FILE"
}

#######################################
# CSV OKUMA
#######################################

load_current_csv() {
  if [[ ! -f "$EMPLOYEE_CSV" ]]; then
    log "ERROR: employees.csv not found at $EMPLOYEE_CSV"
    exit 1
  fi

  log "Loading current employees from $EMPLOYEE_CSV"

  TMP_CURRENT_USERS="$(mktemp)"
  TMP_TERMINATED_USERS="$(mktemp)"

  {
    # header
    read -r _header

    while IFS=',' read -r employee_id username name_surname department status; do
      [[ -z "${employee_id// }" ]] && continue

      username="$(echo "${username:-}" | tr '[:upper:]' '[:lower:]')"
      department="$(echo "${department:-}" | tr '[:upper:]' '[:lower:]')"
      status="$(echo "${status:-}" | tr '[:upper:]' '[:lower:]')"

      CURRENT_STATUS["$username"]="$status"
      CURRENT_DEPT["$username"]="$department"
      CURRENT_NAME["$username"]="$name_surname"

      echo "$username" >> "$TMP_CURRENT_USERS"

      if [[ "$status" == "terminated" ]]; then
        echo "$username" >> "$TMP_TERMINATED_USERS"
      fi
    done
  } < "$EMPLOYEE_CSV"

  sort -u "$TMP_CURRENT_USERS" -o "$TMP_CURRENT_USERS"
  sort -u "$TMP_TERMINATED_USERS" -o "$TMP_TERMINATED_USERS"

  CURRENT_USERS_FILE="$TMP_CURRENT_USERS"
  TERMINATED_USERS_FILE="$TMP_TERMINATED_USERS"

  log "Loaded $(wc -l < "$CURRENT_USERS_FILE") current users"
}

load_last_csv() {
  TMP_LAST_USERS="$(mktemp)"

  if [[ -f "$LAST_CSV" ]]; then
    log "Loading last snapshot from $LAST_CSV"
    tail -n +2 "$LAST_CSV" | while IFS=',' read -r employee_id username _rest; do
      username="$(echo "${username:-}" | tr '[:upper:]' '[:lower:]')"
      [[ -z "$username" ]] && continue
      echo "$username" >> "$TMP_LAST_USERS"
    done
    sort -u "$TMP_LAST_USERS" -o "$TMP_LAST_USERS"
  else
    log "No last snapshot found, assuming first run"
    : > "$TMP_LAST_USERS"
  fi

  LAST_USERS_FILE="$TMP_LAST_USERS"
}

#######################################
# DEĞİŞİKLİK TESPİTİ
#######################################

detect_changes() {
  TMP_ADDED="$(mktemp)"
  TMP_REMOVED="$(mktemp)"
  TMP_OFFBOARD="$(mktemp)"

  # Added: last'ta yok, current'ta var
  comm -13 "$LAST_USERS_FILE" "$CURRENT_USERS_FILE" > "$TMP_ADDED" || true
  # Removed: last'ta var, current'ta yok
  comm -23 "$LAST_USERS_FILE" "$CURRENT_USERS_FILE" > "$TMP_REMOVED" || true
  # Offboard: removed + status=terminated
  cat "$TMP_REMOVED" "$TERMINATED_USERS_FILE" | sort -u > "$TMP_OFFBOARD"

  ADDED_USERS_FILE="$TMP_ADDED"
  REMOVED_USERS_FILE="$TMP_REMOVED"
  OFFBOARD_USERS_FILE="$TMP_OFFBOARD"

  log "Detected $(wc -l < "$ADDED_USERS_FILE") added users"
  log "Detected $(wc -l < "$REMOVED_USERS_FILE") removed users"
  log "Detected $(wc -l < "$OFFBOARD_USERS_FILE") users to offboard"
}

#######################################
# ONBOARDING
#######################################

onboard_users() {
  local file="$1"

  while IFS= read -r username; do
    [[ -z "$username" ]] && continue

    local status="${CURRENT_STATUS[$username]:-unknown}"
    local dept="${CURRENT_DEPT[$username]:-unknown}"
    local name="${CURRENT_NAME[$username]:-}"

    if [[ "$status" != "active" ]]; then
      log "Skip onboarding for $username (status=$status)"
      continue
    fi

    log "Onboarding user=$username dept=$dept name=$name"

    if ! getent group "$dept" >/dev/null 2>&1; then
      run_cmd "groupadd \"$dept\""
    fi

    if id "$username" >/dev/null 2>&1; then
      run_cmd "usermod -aG \"$dept\" \"$username\""
    else
      run_cmd "useradd -m -s /bin/bash -g \"$dept\" \"$username\""
    fi

  done < "$file"
}

#######################################
# OFFBOARDING
#######################################

offboard_users() {
  local file="$1"

  while IFS= read -r username; do
    [[ -z "$username" ]] && continue

    log "Offboarding user=$username"

    if ! id "$username" >/dev/null 2>&1; then
      log "User $username not found on system, skipping account operations"
      continue
    fi

    local home_dir
    home_dir="$(getent passwd "$username" | cut -d: -f6)"

    if [[ -n "${home_dir:-}" && -d "$home_dir" ]]; then
      local archive_path="$ARCHIVE_DIR/${username}_$(date "+%Y%m%d_%H%M%S").tar.gz"
      run_cmd "tar -czf \"$archive_path\" \"$home_dir\""
      log "Archived home for $username to $archive_path"
    else
      log "Home directory for $username not found, skipping archive"
    fi

    run_cmd "usermod -L \"$username\""
    log "Locked account for $username"
  done < "$file"
}

#######################################
# RAPOR
#######################################

write_report() {
  log "Writing manager report to $REPORT_FILE"

  {
    echo "Manager Update Report"
    echo "Run ID: $RUN_ID"
    echo "Date: $(timestamp)"
    echo
    echo "Added users           : $(wc -l < "$ADDED_USERS_FILE")"
    echo "Removed users         : $(wc -l < "$REMOVED_USERS_FILE")"
    echo "Offboarded (total)    : $(wc -l < "$OFFBOARD_USERS_FILE")"
    echo
    echo "Output directory      : $OUTPUT_DIR"
    echo "Logs directory        : $LOG_DIR"
    echo "Reports directory     : $REPORT_DIR"
    echo "Archives directory    : $ARCHIVE_DIR"
  } > "$REPORT_FILE"
}

#######################################
# RAPORU MAIL ATMA
#######################################

send_report_email() {
  if [[ -z "${MANAGER_EMAIL:-}" ]]; then
    log "Manager email not set, skipping email sending"
    return
  fi

  if ! command -v mail >/dev/null 2>&1; then
    log "'mail' command not found, skipping email sending"
    return
  fi

  local subject="Employee Lifecycle Report - $RUN_ID"
  log "Sending manager report to $MANAGER_EMAIL"
  mail -s "$subject" "$MANAGER_EMAIL" < "$REPORT_FILE"
}

#######################################
# SNAPSHOT
#######################################

update_snapshot() {
  cp "$EMPLOYEE_CSV" "$LAST_CSV"
  log "Updated last snapshot at $LAST_CSV"
}

#######################################
# MAIN
#######################################

main() {
  ensure_dirs
  log "=== Employee Lifecycle Sync started ==="

  load_current_csv
  load_last_csv
  detect_changes

  log "--- Onboarding phase ---"
  onboard_users "$ADDED_USERS_FILE"

  log "--- Offboarding phase ---"
  offboard_users "$OFFBOARD_USERS_FILE"

  write_report
  send_report_email
  update_snapshot

  log "=== Employee Lifecycle Sync finished ==="
}

main "$@"
