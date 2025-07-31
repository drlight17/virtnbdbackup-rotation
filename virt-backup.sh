#!/bin/bash

# === VM Backup Script with Rotation, Email, Custom Sender, Force and Disk Exclude ===
# Usage: ./virt-backup.sh <base_path> <vm_name> <keep_months> <recipient_email> <sender_email> [force] [exclude_disk]
# Example: ./virt-backup.sh /backups web01 3 admin@company.com backup@company.com force sda

# === Validate arguments (5 required, 6th and 7th optional) ===
if [ $# -lt 5 ]; then
    echo "Error: Not enough arguments."
    echo "Usage: $0 <base_path> <vm_name> <keep_months> <recipient_email> <sender_email> [force] [exclude_disk]"
    echo "Example: $0 /backups web01 3 admin@company.com backup@company.com force sda"
    exit 1
fi

BASE_PATH="$1"
VM_NAME="$2"
KEEP_MONTHS="$3"
RECIPIENT_EMAIL="$4"
SENDER_EMAIL="$5"
FORCE="${6:-}"
EXCLUDE_DISK="${7:-}"

# === Validate keep_months ===
if ! [[ "$KEEP_MONTHS" =~ ^[0-9]+$ ]] || [ "$KEEP_MONTHS" -lt 1 ]; then
    echo "Error: 'keep_months' must be a positive integer."
    exit 1
fi

# === Validate emails ===
validate_email() {
    if ! [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "Error: Invalid email address: $1"
        exit 1
    fi
}

validate_email "$RECIPIENT_EMAIL"
validate_email "$SENDER_EMAIL"

# === Generate current month directory (mmyyyy) ===
CURRENT_MONTH=$(date +"%m%Y")
TARGET_DIR="$BASE_PATH/$VM_NAME/$CURRENT_MONTH"
PARENT_DIR="$BASE_PATH/$VM_NAME"

# === Initialize log buffer ===
LOG=""
log() {
    local msg="$1"
    echo "$msg"
    LOG="$LOG$msg
"
}

log "=== VM Backup Script Started ==="
log "Timestamp: $(date)"
log "VM: $VM_NAME"
log "Target: $TARGET_DIR"
log "Keep last $KEEP_MONTHS month(s)"
log "Notification recipient: $RECIPIENT_EMAIL"
log "Sender address: $SENDER_EMAIL"
if [ -n "$FORCE" ]; then
    log "Force mode: enabled (will remove .partial files if found)"
else
    log "Force mode: disabled (will abort if .partial file exists)"
fi
if [ -n "$EXCLUDE_DISK" ]; then
    log "Exclude disk: $EXCLUDE_DISK"
else
    log "Exclude disk: not set"
fi

# === Create parent directory ===
mkdir -p "$PARENT_DIR"
if [ $? -ne 0 ]; then
    log "ERROR: Failed to create directory: $PARENT_DIR"
    echo "$LOG" | mail -r "$SENDER_EMAIL" -s "Backup Failed: $VM_NAME" "$RECIPIENT_EMAIL"
    exit 1
fi

# === Check for .partial files ===
shopt -s nullglob
partial_files=("$TARGET_DIR"/*.partial)

if [ ${#partial_files[@]} -gt 0 ]; then
    log "WARNING: Found .partial file(s):"
    for file in "${partial_files[@]}"; do
        log "  - $(basename "$file")"
    done

    if [ -n "$FORCE" ] && [[ "$FORCE" =~ ^(force|yes|true|1)$ ]]; then
        log "Force mode: removing .partial files..."
        rm -f "${partial_files[@]}"
        if [ $? -eq 0 ]; then
            log "Successfully removed .partial files."
        else
            log "ERROR: Failed to remove .partial files."
            echo "$LOG" | mail -r "$SENDER_EMAIL" -s "Backup Failed: $VM_NAME" "$RECIPIENT_EMAIL"
            exit 1
        fi
    else
        log "Aborting to prevent conflict. Use 'force' to override."
        echo "$LOG" | mail -r "$SENDER_EMAIL" -s "Backup Skipped: $VM_NAME" "$RECIPIENT_EMAIL"
        exit 0
    fi
else
    log "No .partial files found. Proceeding..."
fi

# === Create target directory ===
mkdir -p "$TARGET_DIR"
if [ $? -ne 0 ]; then
    log "ERROR: Failed to create target directory: $TARGET_DIR"
    echo "$LOG" | mail -r "$SENDER_EMAIL" -s "Backup Failed: $VM_NAME" "$RECIPIENT_EMAIL"
    exit 1
fi
log "Target directory created: $TARGET_DIR"

# === Rotation: keep only N most recent mmyyyy directories ===
if [ ! -d "$PARENT_DIR" ]; then
    log "ERROR: Parent directory does not exist: $PARENT_DIR"
    echo "$LOG" | mail -r "$SENDER_EMAIL" -s "Backup Failed: $VM_NAME" "$RECIPIENT_EMAIL"
    exit 1
fi

mapfile -t dirs < <(find "$PARENT_DIR" -maxdepth 1 -type d -name '[0-9][0-9][0-9][0-9][0-9][0-9]' -exec basename {} \; | sort)
count=${#dirs[@]}
log "Found $count existing backup directories."

if [ $count -le $KEEP_MONTHS ]; then
    log "No rotation needed. Keeping all $count directory(ies)."
else
    to_remove=$((count - KEEP_MONTHS))
    log "Rotation: removing $to_remove oldest directory(s)..."

    for ((i = 0; i < to_remove; i++)); do
        oldest="${dirs[i]}"
        oldest_path="$PARENT_DIR/$oldest"
        if [ -d "$oldest_path" ]; then
            log "Removing old backup: $oldest_path"
            rm -rf "$oldest_path"
            if [ $? -eq 0 ]; then
                log "Successfully removed: $oldest_path"
            else
                log "ERROR: Failed to remove: $oldest_path"
            fi
        fi
    done
    log "Rotation completed."
fi

# === Run backup ===
log "Starting backup for VM: $VM_NAME"

DOCKER_CMD=(
    docker run --rm
    -v /run:/run
    -v /var/tmp:/var/tmp
    -v /etc/libvirt/qemu/nvram:/etc/libvirt/qemu/nvram
    -v /usr/share/OVMF:/usr/share/OVMF
    -v /var/lib/libvirt/images:/var/lib/libvirt/images:ro
    -v "$BASE_PATH:/backups"
    ghcr.io/abbbi/virtnbdbackup:master
    virtnbdbackup --compress=16 -d "$VM_NAME" -l auto -o "/backups/$VM_NAME/$CURRENT_MONTH" -S
)

if [ -n "$EXCLUDE_DISK" ]; then
    DOCKER_CMD+=(-x "$EXCLUDE_DISK")
    log "Adding exclude disk: $EXCLUDE_DISK"
fi

log "Running docker command..."

eval "${DOCKER_CMD[*]}"

DOCKER_EXIT_CODE=$?

if [ $DOCKER_EXIT_CODE -eq 0 ]; then
    log "SUCCESS: Backup completed for $VM_NAME"
    SUBJECT="Backup Success: $VM_NAME"
else
    log "ERROR: Backup failed with exit code: $DOCKER_EXIT_CODE"
    SUBJECT="Backup Failed: $VM_NAME"
fi

# === Send log report ===
echo "$LOG" | mail -r "$SENDER_EMAIL" -s "$SUBJECT" "$RECIPIENT_EMAIL"

# === Exit ===
exit $DOCKER_EXIT_CODE
