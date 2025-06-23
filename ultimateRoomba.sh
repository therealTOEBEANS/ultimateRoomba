#!/bin/bash

################################################################################
#
#                           ultimateRoomba v1.7
#
#   A smart, drive-aware cleaning script for Linux Mint.
#
#   - v1.7: Implemented a new category-based selection system using
#           single QWERTY letters (Q,W,E,R,T) for faster use. Reorganized
#           all cleaning tasks into these new categories.
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
    eval "$cmd" &
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
    echo -e "\r$title [Done] [${minutes_fmt}m ${seconds_fmt}s ${elapsed_ms_fmt}ms]      "
    if [ $exit_code -ne 0 ]; then
        echo "  └─ Failed with exit code $exit_code."
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
    local paths=("$HOME/.local/share/gvfs-metadata" "$HOME/.local/share/vlc/ml.xspf" "$HOME/.config/gtk-3.0/bookmarks" "$HOME/.config/celluloid/watch_later")
    clean_path_list "Cleaning File Access & Media History" "${paths[@]}"
}
clean_p2p_history() {
    clean_path_list "Cleaning Nicotine+ (P2P) History" "$HOME/.local/share/nicotine"
}
clean_chat_logs() {
    clean_path_list "Cleaning Konversation (IRC) Logs" "$HOME/.local/share/konversation/logs"
}

# Category: [R] - App Caches & Logs
clean_electron_apps() {
    local title="Cleaning Electron App Caches"
    local electron_apps=("VSCodium" "balenaEtcher" "Stacher7" "LM Studio")
    local cmd=""
    local found=false
    for app in "${electron_apps[@]}"; do
        if [ -d "$HOME/.config/$app" ]; then
            found=true
            cmd+="smart_delete_dir '$HOME/.config/$app/Cache' &> /dev/null && "
            cmd+="smart_delete_dir '$HOME/.config/$app/Code Cache' &> /dev/null && "
            cmd+="smart_delete_dir '$HOME/.config/$app/GPUCache' &> /dev/null && "
            cmd+="smart_delete_dir '$HOME/.config/$app/Session Storage' &> /dev/null && "
            cmd+="smart_delete_dir '$HOME/.config/$app/Local Storage' &> /dev/null && "
        fi
    done
    if [ "$found" = false ]; then echo "$title... Not found, skipping."; return; fi
    cmd+="true"
    run_with_spinner_and_timer "$title..." "$cmd"
}
clean_multimedia_caches() {
    clean_path_list "Cleaning Multimedia Caches" "$HOME/.cache/gstreamer-1.0" "$HOME/.cache/mpv" "$HOME/.cache/hypnotix" "$HOME/.cache/xreader"
}
clean_app_logs() {
    clean_path_list "Cleaning NordVPN Cache Logs" "$HOME/.cache/nordvpn"
}

# Category: [T] - Graphics Caches
clean_graphics_caches() {
    clean_path_list "Cleaning Graphics & Shader Caches" "$HOME/.cache/mesa_shader_cache" "$HOME/.cache/nvidia"
}

# --- Main Execution ---
clear
echo "#########################################################"
echo "##               ultimateRoomba Cleaner v1.7           ##"
echo "#########################################################"
echo
echo "Select categories to CLEAN by entering their letters (e.g., QWE)."
echo

# --- Menu Definition ---
printf "[Q] - Browsers\n"
printf "    └─ Browser History & Bookmarks (Firefox, Chromium)\n"
printf "    └─ Browser Caches (Firefox, Chromium)\n\n"

printf "[W] - OS & File History\n"
printf "    └─ Empty Trash\n"
printf "    └─ Recently Used Files List\n"
printf "    └─ General Thumbnail Cache\n"
printf "    └─ Terminal Command History\n\n"

printf "[E] - Application History\n"
printf "    └─ File Access Metadata (GVFS)\n"
printf "    └─ Media Player History (VLC, Celluloid)\n"
printf "    └─ Nicotine+ (P2P) Logs & DBs\n"
printf "    └─ Konversation (IRC) Logs\n\n"

printf "[R] - App Caches & Logs\n"
printf "    └─ Electron App Caches (VSCodium, Etcher, etc.)\n"
printf "    └─ Multimedia Caches (GStreamer, MPV, etc.)\n"
printf "    └─ NordVPN Cache Logs\n\n"

printf "[T] - Graphics Caches\n"
printf "    └─ Mesa and NVIDIA compiled shaders.\n\n"

# --- User Input ---
read -p "Categories to clean: " -r user_input
user_input_lower=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')
declare -a functions_to_run=()

# Process each character of the input string to build the list of functions
for (( i=0; i<${#user_input_lower}; i++ )); do
  char="${user_input_lower:$i:1}"
  case $char in
    q) functions_to_run+=("clean_browser_history" "clean_browser_caches") ;;
    w) functions_to_run+=("empty_trash" "clean_recently_used" "clean_thumbnail_cache" "clean_bash_history") ;;
    e) functions_to_run+=("clean_file_media_history" "clean_p2p_history" "clean_chat_logs") ;;
    r) functions_to_run+=("clean_electron_apps" "clean_multimedia_caches" "clean_app_logs") ;;
    t) functions_to_run+=("clean_graphics_caches") ;;
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
