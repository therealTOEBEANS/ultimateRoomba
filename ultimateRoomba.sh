#!/bin/bash

################################################################################
#
#                               ultimateRoomba v2.2
#
#   A smart, drive-aware cleaning script for Linux Mint.
#
#   - v2.2: Refined Electron app cleaning to preserve cookies. Added [S] category
#           for system logs and a pending [H] category for home folder scans.
#   - v2.0: Implemented surgical cleaning for VSCodium and Stability Matrix
#           to preserve settings. Removed Nicotine+ category. Reorganized
#           and re-categorized the menu for clarity.
#
################################################################################

# --- Helper Functions ---

# Function to get the parent block device (e.g., /dev/nvme0n1p3 -> nvme0n1)
get_base_drive() {
    local device_path=$1
    # This will turn /dev/nvme0n1p3 into nvme0n1 or /dev/sda1 into sda
    basename "$device_path" | sed -E 's/p[0-9]+$//' | sed -E 's/[0-9]+$//'
}

# Determines if a path is on an HDD (rotational) drive.
is_on_hdd() {
    local path_to_check=$1
    local device=$(df "$path_to_check" | tail -1 | awk '{print $1}')
    if [ -z "$device" ]; then return 1; fi

    local base_drive=$(get_base_drive "$device")
    if [[ "$base_drive" == "sda" ]]; then
        return 0 # 0 means "true" in bash
    else
        return 1 # 1 means "false"
    fi
}

# Smart deletion for a single file
smart_delete_file() {
    local filepath="$1"
    if [ ! -f "$filepath" ]; then return; fi
    if is_on_hdd "$filepath"; then
        shred -n 1 -z -u "$filepath"
    else
        rm -f "$filepath"
    fi
}

# Smart deletion for a directory
smart_delete_dir() {
    local dirpath="$1"
    if [ ! -d "$dirpath" ]; then
        echo "Error: Directory not found: $dirpath"
        return 1
    fi
    rm -rf "$dirpath"
}

# --- UI Functions ---

# Master function to run a command with a spinner and a timer
run_with_spinner_and_timer() {
    local title="$1"
    local cmd="$2"
    local s1=("|" "/" "-" "\\")
    local s2=("-" "\\" "|" "/")
    local i=0
    local start_time=$(date +%s%N)

    echo -en "$title "
    eval "$cmd" &> /dev/null & # Redirect stdout and stderr of the command
    local pid=$!
    tput civis

    while ps -p $pid > /dev/null; do
        local now=$(date +%s%N)
        local elapsed_ns=$((now - start_time))
        local elapsed_s=$(echo "$elapsed_ns / 1000000000" | bc)
        local elapsed_ms=$(echo "($elapsed_ns % 1000000000) / 1000000" | bc)
        printf -v minutes_fmt "%02d" $((elapsed_s / 60))
        printf -v seconds_fmt "%02d" $((elapsed_s % 60))
        printf -v elapsed_ms_fmt "%03d" "$elapsed_ms"
        local spinner_char="${s1[i % 4]}${s2[i % 4]}${s1[i % 4]}"
        echo -en "\r$title [${spinner_char}] [${minutes_fmt}m ${seconds_fmt}s ${elapsed_ms_fmt}ms]"
        sleep 0.1
        ((i++))
    done

    tput cnorm
    wait $pid
    local exit_code=$?
    local end_time=$(date +%s%N)
    local elapsed_ns=$((end_time - start_time))
    local elapsed_s=$(echo "$elapsed_ns / 1000000000" | bc)
    local elapsed_ms=$(echo "($elapsed_ns % 1000000000) / 1000000" | bc)
    printf -v minutes_fmt "%02d" $((elapsed_s / 60))
    printf -v seconds_fmt "%02d" $((elapsed_s % 60))
    printf -v elapsed_ms_fmt "%03d" "$elapsed_ms"
    echo -e "\r$title [Done] [${minutes_fmt}m ${seconds_fmt}s ${elapsed_ms_fmt}ms]        "
    if [ $exit_code -ne 0 ]; then
        echo "  └─ Failed with exit code $exit_code. This may be normal for some cleanup tasks."
    fi
}

# --- Helper for mass cleaning ---
clean_path_list() {
    local title="$1"
    shift
    local paths=("$@")
    local cmd=""
    local found=false

    for path in "${paths[@]}"; do
        if [ -e "$path" ]; then
            found=true
            if [ -d "$path" ]; then
                cmd+="smart_delete_dir '$path' && "
            elif [ -f "$path" ]; then
                cmd+="smart_delete_file '$path' && "
            fi
        fi
    done

    if [ "$found" = false ]; then
        echo "$title... Not found, skipping."
        return
    fi

    cmd+="true" # End the command chain
    run_with_spinner_and_timer "$title..." "$cmd"
}

# --- Cleaning Functions ---

# Category: [Q] - Browsers
clean_browser_history() {
    local title="Cleaning Browser History & Bookmarks"
    # NOTE: This does not target cookie files.
    local cmd=""
    local ff_hist=$(find "$HOME/.mozilla/firefox" -name "places.sqlite" -type f)
    if [ -n "$ff_hist" ]; then
        echo "$ff_hist" | while IFS= read -r file; do cmd+="smart_delete_file '$file' && "; done
    fi
    if [ -f "$HOME/.config/chromium/Default/History" ]; then
        cmd+="smart_delete_file '$HOME/.config/chromium/Default/History' && "
    fi
    if [ -z "$cmd" ]; then echo "$title... Not found, skipping."; return; fi
    cmd+="true"
    run_with_spinner_and_timer "$title..." "$cmd"
}
clean_browser_caches() {
    clean_path_list "Cleaning Browser Caches" "$HOME/.cache/mozilla/firefox" "$HOME/.cache/chromium"
}

# Category: [W] - OS & File History
empty_trash() {
    local title="Emptying Trash"
    local paths=("$HOME/.local/share/Trash/files" "$HOME/.local/share/Trash/info")
    local cmd=""
    for path in "${paths[@]}"; do
        if [ -d "$path" ]; then
            cmd+="smart_delete_dir '$path' && mkdir -p '$path' && "
        fi
    done
    if [ -z "$cmd" ]; then echo "$title... Not found, skipping."; return; fi
    cmd+="true"
    run_with_spinner_and_timer "$title..." "$cmd"
}
clean_recently_used() {
    clean_path_list "Cleaning Recently Used Files List" "$HOME/.local/share/recently-used.xbel" "$HOME/.local/share/RecentDocuments"
}
clean_thumbnail_cache() {
    local title="Cleaning Thumbnail Cache"
    local dir="$HOME/.cache/thumbnails"
    if [ ! -d "$dir" ]; then echo "$title... Not found, skipping."; return; fi
    run_with_spinner_and_timer "$title..." "smart_delete_dir '$dir' && mkdir -p '$dir'"
}
clean_bash_history() {
    clean_path_list "Cleaning Terminal Command History" "$HOME/.bash_history"
}

# Category: [E] - Application History
clean_file_media_history() {
    local paths=(
        "$HOME/.local/share/gvfs-metadata"
        "$HOME/.local/share/vlc/ml.xspf"
        "$HOME/.config/gtk-3.0/bookmarks"
        "$HOME/.config/celluloid/watch_later"
    )
    clean_path_list "Cleaning File Access & Media History" "${paths[@]}"
}
clean_chat_logs() {
    clean_path_list "Cleaning Konversation (IRC) Logs" "$HOME/.local/share/konversation/logs"
}
clean_vscodium_history() {
    local paths=(
        "$HOME/.config/VSCodium/Backups"
        "$HOME/.config/VSCodium/logs"
        "$HOME/.config/VSCodium/User/History"
        "$HOME/.config/VSCodium/User/workspaceStorage"
    )
    clean_path_list "Cleaning VSCodium History" "${paths[@]}"
}

# Category: [R] - App Caches & Logs
clean_electron_history() {
    # Surgical cleaning of Electron app history (Crashpads, Sentry), preserving cookies.
    local paths=(
        # Balena Etcher
        "$HOME/.config/balenaEtcher/Crashpad"
        "$HOME/.config/balenaEtcher/sentry"
        # Stacher7
        "$HOME/.config/Stacher7/Crashpad"
    )
    clean_path_list "Cleaning Electron App History (Crashpads, Logs)" "${paths[@]}"
}
clean_app_logs() {
    clean_path_list "Cleaning NordVPN Cache Logs" "$HOME/.cache/nordvpn"
}

# Category: [T] - AI Application History
clean_ai_app_history() {
    local paths=(
        "$HOME/.config/LM Studio/logs"
        "$HOME/.config/LM Studio/Crashpad"
        "$HOME/.config/StabilityMatrix/Logs"
        "$HOME/.config/StabilityMatrix/Temp"
    )
    clean_path_list "Cleaning AI Application History" "${paths[@]}"
}

# Category: [H] - Hidden Home Folder Files (PENDING)
clean_home_hidden_files() {
    echo "Cleaning Hidden Home Files... PENDING."
    echo "  └─ To enable this, please provide the output of 'ls -ld ~.*'"
    # Example of what could be added here later:
    # local paths=("$HOME/.some_hidden_log_file" "$HOME/.some_other_app_history")
    # clean_path_list "Cleaning Hidden Home Folder Files" "${paths[@]}"
}

# Category: [S] - System & Security Logs (ADMIN)
clean_system_logs() {
    local title="Cleaning System & Security Logs"
    # This is a comprehensive command to safely clear major system logs.
    # It removes rotated/compressed backups and truncates active log files.
    local cmd="
        find /var/log -type f -name '*.gz' -delete;
        find /var/log -type f -name '*.log.*' -delete;
        find /var/log -type f -name '*.old' -delete;
        truncate -s 0 /var/log/alternatives.log;
        truncate -s 0 /var/log/auth.log;
        truncate -s 0 /var/log/boot.log;
        truncate -s 0 /var/log/btmp;
        truncate -s 0 /var/log/dmesg;
        truncate -s 0 /var/log/dpkg.log;
        truncate -s 0 /var/log/faillog;
        truncate -s 0 /var/log/kern.log;
        truncate -s 0 /var/log/lastlog;
        truncate -s 0 /var/log/ufw.log;
        truncate -s 0 /var/log/wtmp;
        truncate -s 0 /var/log/Xorg.0.log;
        truncate -s 0 /var/log/apt/history.log;
        true"
    run_with_spinner_and_timer "$title..." "$cmd"
}


# --- Main Execution ---
clear
echo "#########################################################"
echo "##               ultimateRoomba Cleaner v2.2           ##"
echo "#########################################################"
echo

# Check for sudo if system cleaning is requested and not already root
if [[ "$@" =~ "s" ]] && [[ $EUID -ne 0 ]]; then
  echo "System log cleaning requires administrator privileges."
  # Re-run the script with sudo, passing the original user input
  exec sudo "$0" "$@"
fi


# --- Menu Definition ---
echo "Select categories to CLEAN by entering their letters (e.g., QWES)."
echo
printf "[Q] - Browsers\n"
printf "    └─ Browser History, Bookmarks, and Caches.\n\n"
printf "[W] - OS & File History\n"
printf "    └─ Trash, Recent Files, Thumbnails, Terminal History.\n\n"
printf "[E] - Application History\n"
printf "    └─ File Access Logs (GVFS), Media Player History, VSCodium, IRC.\n\n"
printf "[R] - App Caches & Logs\n"
printf "    └─ Surgical deletion of Electron App History (Etcher, etc.), NordVPN Logs.\n\n"
printf "[T] - AI Application History\n"
printf "    └─ Surgical deletion of logs & crash reports from AI apps.\n\n"
printf "[H] - Hidden Home Files (Pending)\n"
printf "    └─ Scan for non-standard log files in your home directory.\n\n"
printf "[S] - System & Security Logs (Requires Admin)\n"
printf "    └─ Clears system-wide logs like logins, errors, and firewall.\n\n"


# --- User Input ---
# If arguments were passed from the sudo re-exec, use them. Otherwise, read input.
if [ "$#" -gt 0 ]; then
    user_input="$1"
    echo "Categories to clean: $user_input"
else
    read -p "Categories to clean: " -r user_input
fi

user_input_lower=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')
declare -a functions_to_run=()

# Process each character of the input string to build the list of functions
for (( i=0; i<${#user_input_lower}; i++ )); do
  char="${user_input_lower:$i:1}"
  case $char in
    q) functions_to_run+=("clean_browser_history" "clean_browser_caches") ;;
    w) functions_to_run+=("empty_trash" "clean_recently_used" "clean_thumbnail_cache" "clean_bash_history") ;;
    e) functions_to_run+=("clean_file_media_history" "clean_vscodium_history" "clean_chat_logs") ;;
    r) functions_to_run+=("clean_electron_history" "clean_app_logs") ;;
    t) functions_to_run+=("clean_ai_app_history") ;;
    h) functions_to_run+=("clean_home_hidden_files") ;;
    s) functions_to_run+=("clean_system_logs") ;;
    *) # Ignore invalid characters
  esac
done

# Remove duplicate function calls if a user enters a letter twice (e.g., 'qqw')
unique_functions=($(printf "%s\n" "${functions_to_run[@]}" | sort -u))

# --- Execution Loop ---
echo "---------------------------------------------------------"
if [ ${#unique_functions[@]} -eq 0 ]; then
    echo "No valid categories selected. Exiting."
else
    echo "Starting cleanup for selected categories..."
    for func in "${unique_functions[@]}"; do
        # Call the function by its name
        "$func"
    done
fi
echo "---------------------------------------------------------"
echo "ultimateRoomba has finished."
echo
