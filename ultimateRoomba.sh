#!/bin/bash

################################################################################
#
#                           ultimateRoomba v1.5
#
#   A smart, drive-aware cleaning script for Linux Mint.
#
#   - v1.5: Reorganized menu into .cache and .config sections, sorted by
#           sensitivity. Added new cleaning targets from .config like
#           Retroarch history, VLC history, and Electron app caches.
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

# --- .cache targets ---
clean_browser_caches() {
    local paths=("$HOME/.cache/mozilla/firefox" "$HOME/.cache/chromium")
    clean_path_list "1. Cleaning Browser Caches" "${paths[@]}"
}
clean_thumbnail_cache() {
    local dir="$HOME/.cache/thumbnails"
    if [ ! -d "$dir" ]; then echo "2. Thumbnail Cache... Not found, skipping."; return; fi
    run_with_spinner_and_timer "2. Cleaning Thumbnail Cache..." "smart_delete_dir '$dir' && mkdir -p '$dir'"
}
clean_multimedia_caches() {
    local paths=("$HOME/.cache/gstreamer-1.0" "$HOME/.cache/mpv" "$HOME/.cache/hypnotix" "$HOME/.cache/xreader")
    clean_path_list "3. Cleaning Multimedia Caches" "${paths[@]}"
}
clean_graphics_caches() {
    local paths=("$HOME/.cache/mesa_shader_cache" "$HOME/.cache/nvidia")
    clean_path_list "4. Cleaning Graphics & Shader Caches" "${paths[@]}"
}
clean_app_logs() {
    local paths=("$HOME/.cache/nordvpn")
    clean_path_list "5. Cleaning Application Logs" "${paths[@]}"
}

# --- .config targets ---
clean_browser_history() {
    local cmd=""
    local ff_hist=$(find "$HOME/.mozilla/firefox" -name "places.sqlite" -type f)
    if [ -n "$ff_hist" ]; then
        echo "$ff_hist" | while IFS= read -r file; do cmd+="smart_delete_file '$file' && "; done
    fi
    if [ -f "$HOME/.config/chromium/Default/History" ]; then
        cmd+="smart_delete_file '$HOME/.config/chromium/Default/History' && "
    fi
    
    if [ -z "$cmd" ]; then echo "6. Browser History & Bookmarks... Not found, skipping."; return; fi
    cmd+="true"
    run_with_spinner_and_timer "6. Cleaning Browser History & Bookmarks..." "$cmd"
}
clean_recently_used() {
    local file="$HOME/.local/share/recently-used.xbel"
    if [ ! -f "$file" ]; then echo "7. Recently Used Files... Not found, skipping."; return; fi
    run_with_spinner_and_timer "7. Cleaning Recently Used Files..." "smart_delete_file '$file' && touch '$file'"
}
clean_bash_history() {
    clean_path_list "8. Cleaning Terminal Command History" "$HOME/.bash_history"
}
clean_retroarch_history() {
    local files=("$HOME/.config/retroarch/content_history.lpl"
                 "$HOME/.config/retroarch/content_image_history.lpl"
                 "$HOME/.config/retroarch/content_music_history.lpl"
                 "$HOME/.config/retroarch/content_video_history.lpl")
    clean_path_list "9. Cleaning Retroarch Content History" "${files[@]}"
}
clean_misc_app_history() {
    # This function resets specific app settings known to contain history.
    local cmd=""
    local found=false
    # VLC: Resetting interface config clears recent media list.
    if [ -f "$HOME/.config/vlc/vlc-qt-interface.conf" ]; then
        cmd+="smart_delete_file '$HOME/.config/vlc/vlc-qt-interface.conf' && "
        found=true
    fi
    # GTK: Clear file manager bookmarks
    if [ -f "$HOME/.config/gtk-3.0/bookmarks" ]; then
        cmd+="smart_delete_file '$HOME/.config/gtk-3.0/bookmarks' && "
        found=true
    fi
    # Celluloid: Clear watch later playlist
    if [ -d "$HOME/.config/celluloid/watch_later" ]; then
        cmd+="smart_delete_dir '$HOME/.config/celluloid/watch_later' && "
        found=true
    fi
    
    if [ "$found" = false ]; then echo "10. Misc App History... Not found, skipping."; return; fi
    cmd+="true"
    run_with_spinner_and_timer "10. Cleaning Misc App History (VLC, etc)..." "$cmd"
}
clean_electron_apps() {
    local electron_apps=("VSCodium" "balenaEtcher" "Stacher7" "LM Studio")
    local cmd=""
    local found=false
    for app in "${electron_apps[@]}"; do
        if [ -d "$HOME/.config/$app" ]; then
            found=true
            # Target common Electron cache and storage folders
            cmd+="smart_delete_dir '$HOME/.config/$app/Cache' &> /dev/null && "
            cmd+="smart_delete_dir '$HOME/.config/$app/Code Cache' &> /dev/null && "
            cmd+="smart_delete_dir '$HOME/.config/$app/GPUCache' &> /dev/null && "
            cmd+="smart_delete_dir '$HOME/.config/$app/Session Storage' &> /dev/null && "
            cmd+="smart_delete_dir '$HOME/.config/$app/Local Storage' &> /dev/null && "
        fi
    done

    if [ "$found" = false ]; then echo "11. Electron App Caches... Not found, skipping."; return; fi
    cmd+="true"
    run_with_spinner_and_timer "11. Cleaning Electron App Caches..." "$cmd"
}


# --- Main Execution ---

clear
echo "#########################################################"
echo "##               ultimateRoomba Cleaner v1.5           ##"
echo "#########################################################"
echo

# --- Menu Definition ---
echo "Select items to OMIT from the cleaning process."
echo "By default, all items will be cleaned."
echo

# .cache items
echo "--- .cache Folder (Temporary Data & Performance Files) ---"
declare -a cache_options=(
    "1. Browser Caches"
    "   └─ Firefox, Chromium temporary internet files."
    "2. General Thumbnail Cache"
    "   └─ Image/video previews from the file manager."
    "3. Multimedia Caches"
    "   └─ mpv, gstreamer, xreader, hypnotix."
    "4. Graphics & Shader Caches"
    "   └─ Mesa and NVIDIA compiled shaders."
    "5. Application Logs"
    "   └─ Log files from specific apps (NordVPN)."
)
for item in "${cache_options[@]}"; do echo "$item"; done
echo

# .config items
echo "--- .config Folder (Activity History & Settings) ---"
declare -a config_options=(
    "6. Browser History & Bookmarks"
    "   └─ WARNING: Deletes visited sites AND all bookmarks."
    "7. Recently Used Files List"
    "   └─ System-wide list of recently opened files."
    "8. Terminal Command History"
    "   └─ Erases commands typed into the terminal."
    "9. Retroarch Content History"
    "   └─ Recently played game lists for the emulator."
    "10. Misc App History (VLC, etc)"
    "    └─ VLC history, file manager bookmarks, Celluloid."
    "11. Electron App Caches"
    "    └─ Caches for VSCodium, Balena Etcher, Stacher7."
)
for item in "${config_options[@]}"; do echo "$item"; done
echo

# --- User Input ---
echo "Enter the numbers of the items you wish to SKIP, separated by spaces (e.g., 6 11)."
read -p "Omit: " -r user_choices

declare -a to_run=(1 2 3 4 5 6 7 8 9 10 11)
for choice in $user_choices; do to_run=(${to_run[@]/$choice/}); done

echo "---------------------------------------------------------"
echo "Starting cleanup..."

for i in "${to_run[@]}"; do
    case $i in
        1) clean_browser_caches ;;
        2) clean_thumbnail_cache ;;
        3) clean_multimedia_caches ;;
        4) clean_graphics_caches ;;
        5) clean_app_logs ;;
        6) clean_browser_history ;;
        7) clean_recently_used ;;
        8) clean_bash_history ;;
        9) clean_retroarch_history ;;
        10) clean_misc_app_history ;;
        11) clean_electron_apps ;;
    esac
done

echo "---------------------------------------------------------"
echo "ultimateRoomba has finished."
echo
