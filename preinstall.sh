#!/bin/bash

# --- GLOBALS ---
default_source_path="/opt/svxlink/src/build"
default_install_path="/opt/mysvxlink"

#=========================================================================================
main() {
    LOG_DIR="/var/log/svxlink-install"
    sudo mkdir -p "$LOG_DIR"

    check_dialog
    welcome_text
    ask_paths
	ask_svxlink_remote
    copy_qsoimpl_if_remote
	ensure_svxlink_user
    ask_sa818_hardware
    check_cmake_and_packages
    check_libssl
    prepare_build
    run_make
    run_make_doc
    run_make_install
    change_files
    create_bash_aliases
    install_sounds
    
    if [[ "$SKIP_SA818" -eq 0 ]]; then
        install_pyserial
            enable_uart_and_serial0
        #dialog --title "Reboot Required" --msgbox "UART enabled and udev rule installed.\n\nSystem must reboot now." 12 60
                 dialog --title "Reboot Required" --msgbox "UART enabled, Bluetooth disabled, serial-getty masked.\n\nSystem must reboot now." 12 60
                clear
				sudo reboot
        
    else
        dialog --title "SA818 Skipped" --msgbox "You chose not to configure SA818 hardware.\n\nSkipping UART and serial setup." 12 60
		clear
		Sudo reboot
	
    fi

    
}

#=========================================================================================
check_dialog() {
    
    if dpkg -s dialog 2>/dev/null | grep -q 'Status: install ok installed'; then
        dialog --title "Dialog" --msgbox "dialog' is already installed." 8 40
    else
        sudo apt install dialog -y
    fi
    clear
}

#=========================================================================================
check_cmake_and_packages() {
    dialog --title "Dependencies" --infobox "Checking for cmake and required packages..." 8 50
    sleep 1

    if dpkg -s cmake 2>/dev/null | grep -q "Status: install ok installed"; then
        dialog --title "Dependencies" --msgbox "cmake already installed." 8 50
    else
        packages=(
            g++ cmake make libsigc++-2.0-dev libgsm1-dev libpopt-dev tcl8.6-dev
            libgcrypt20-dev libspeex-dev libasound2-dev libopus-dev librtlsdr-dev
            doxygen groff alsa-utils vorbis-tools curl libcurl4-openssl-dev git
            rtl-sdr libjsoncpp-dev ladspa-sdk libogg0 libogg-dev libgpiod-dev
        )
        total=${#packages[@]}
        count=0
        {
            for pkg in "${packages[@]}"; do
                count=$((count+5))
                percent=$(( count * 100 / total ))
                echo "XXX"; echo "$percent"; echo "Installing $pkg ($count of $total)"; echo "XXX"
                sudo apt-get install -y "$pkg" > /dev/null 2>&1
            done
        } | dialog --title "Installing Dependencies" --gauge "Preparing to install..." 15 70 0
    fi
    clear
}

#=========================================================================================
check_libssl() {
    dialog --title "Dependencies" --infobox "Checking for libssl-dev..." 8 40
    sleep 1
    if dpkg -s libssl-dev 2>/dev/null | grep -q "Status: install ok installed"; then
        dialog --title "Dependencies" --msgbox "libssl-dev already installed." 8 50
    else
        {
            echo "XXX"; echo "50"; echo "Installing libssl-dev..."; echo "XXX"
            sudo apt-get install -y libssl-dev > /dev/null 2>&1
            echo "XXX"; echo "100"; echo "Done."; echo "XXX"
        } | dialog --title "libssl-dev" --gauge "Installing..." 8 40 0
    fi
    clear
}

#=========================================================================================

#=========================================================================================
ensure_svxlink_user() {
    dialog --title "User Setup" --infobox "Checking if user 'svxlink' exists..." 8 50
    sleep 1

    # Determine if full setup should run (based on ask_svxlink_remote)
    local ini_file="${base_source_path:-$(echo "$default_source_path" | awk -F/ '{print "/"$2"/"$3}')}/install_path.ini"
    local USE_REMOTE=0
    if [[ -f "$ini_file" ]]; then
        # shellcheck disable=SC1090
        . "$ini_file"    # loads use_svxlink_remote=0/1
        [[ "${use_svxlink_remote:-0}" == "1" ]] && USE_REMOTE=1
    elif [[ "${USE_SVXLINK_REMOTE:-}" == "1" ]]; then
        USE_REMOTE=1
    fi

    # Always: create/update 'svxlink' user and groups
    if id "svxlink" &>/dev/null; then
        sudo usermod -aG audio,plugdev,gpio,dialout svxlink
        dialog --title "User Setup" --msgbox "User 'svxlink' exists.\nGroups updated." 10 60
    else
        sudo useradd -m -s /bin/bash -G audio,plugdev,gpio,dialout svxlink
        dialog --title "User Setup" --msgbox "User 'svxlink' created and added to groups." 10 60
    fi

    # If Remote app not selected, stop here
    if [[ $USE_REMOTE -ne 1 ]]; then
        clear
        return
    fi

    # Full flow when Remote app = YES
    dialog --title "Set Password" --yesno "Would you like to set or change the password for user 'svxlink' now?" 9 70
    if [[ $? -eq 0 ]]; then
        while true; do
            PASS1=$(dialog --insecure --passwordbox "Enter a password for 'svxlink':" 10 60 3>&1 1>&2 2>&3 3>&-)
            rc=$?
            [[ $rc -ne 0 ]] && break

            PASS2=$(dialog --insecure --passwordbox "Confirm the password:" 10 60 3>&1 1>&2 2>&3 3>&-)
            rc=$?
            [[ $rc -ne 0 ]] && break

            if [[ -z "$PASS1" ]]; then
                dialog --title "Password" --msgbox "Password cannot be empty. Please try again." 8 60
                continue
            fi
            if [[ "$PASS1" != "$PASS2" ]]; then
                dialog --title "Password" --msgbox "Passwords do not match. Please try again." 8 60
                continue
            fi

            if echo "svxlink:$PASS1" | sudo chpasswd; then
                dialog --title "Password" --msgbox "Password set for user 'svxlink'." 8 50
            else
                dialog --title "Password" --msgbox "Failed to set password for 'svxlink'." 8 60
            fi
            unset PASS1 PASS2
            break
        done
    fi

    dialog --title "Sudoers" --infobox "Adding 'svxlink' to sudoers (NOPASSWD)..." 8 60
    sleep 1

    tmpfile=$(mktemp)
    echo "svxlink ALL=(ALL) NOPASSWD:ALL" > "$tmpfile"

    if sudo visudo -cf "$tmpfile" >/dev/null 2>&1; then
        sudo install -m 440 -o root -g root "$tmpfile" /etc/sudoers.d/svxlink
        dialog --title "Sudoers" --msgbox "Installed /etc/sudoers.d/svxlink:\nsvxlink ALL=(ALL) NOPASSWD:ALL" 10 70
    else
        dialog --title "Sudoers" --msgbox "Validation failed for sudoers entry. No changes applied." 9 70
    fi
    rm -f "$tmpfile"

    clear
}
#=========================================================================================



#=========================================================================================
ask_paths() {
    while true; do
        install_path_source=$(dialog --title "SvxLink Sources" \
            --inputbox "Enter path where SvxLink sources/build are:\n\nYou can use anny path you want\n\nBut Use a structure like this /x1/x2/x3/x4" 12 70 "$default_source_path" \
            3>&1 1>&2 2>&3 3>&-)
        [[ $? -ne 0 ]] && continue

        install_path_svxlink=$(dialog --title "SvxLink Installation Path" \
            --inputbox "Enter path where SvxLink must be installed:" 10 60 "$default_install_path" \
            3>&1 1>&2 2>&3 3>&-)
        [[ $? -ne 0 ]] && continue

        base_source_path=$(echo "$install_path_source" | awk -F/ '{print "/"$2"/"$3}')

        dialog --title "Confirm Paths" --yesno "Source Path:\n$install_path_source\n\nInstall Path:\n$install_path_svxlink\n\nBase Path:\n$base_source_path\n\nContinue?" 18 60
        if [[ $? -eq 0 ]]; then
            sudo mkdir -p "$install_path_source"
            cd "$install_path_source"
            ini_file="$base_source_path/install_path.ini"
            sudo mkdir -p "$base_source_path"
            {
                echo "source_path=$install_path_source"
                echo "install_path=$install_path_svxlink"
                echo "base_path=$base_source_path"
            } | sudo tee "$ini_file" > /dev/null
            break
        fi
    done
}

#=========================================================================================
prepare_build() {
    dialog --title "Build" --infobox "Running cmake, please wait..." 8 50
    (
        sudo cmake -DUSE_QT=OFF \
            -DCMAKE_INSTALL_PREFIX="$install_path_svxlink" \
            -DSYSCONF_INSTALL_DIR="$install_path_svxlink" \
            -DLOCAL_STATE_DIR="$install_path_svxlink/var" \
            -DWITH_SYSTEMD=ON .. > /dev/null 2>&1
    ) &
    cmake_pid=$!
    {
        percent=0
        while kill -0 $cmake_pid 2>/dev/null; do
            percent=$(( (percent + 5) % 95 ))
            echo $percent
            sleep 1
        done
        echo 100
    } | dialog --title "CMake Config" --gauge "Configuring project..." 10 60 0
}

#=========================================================================================
run_make() {
    (
        sudo make -j4 2>&1 | while read -r line; do
            if [[ "$line" =~ \[[[:space:]]*([0-9]+)%\] ]]; then
                percent="${BASH_REMATCH[1]}"
                echo "XXX"; echo "$percent"; echo "$line"; echo "XXX"
            fi
        done
    ) | dialog --title "make -j4" --gauge "Compiling SvxLink..." 15 70 0
}

#=========================================================================================
run_make_doc() {
    (
        sudo make doc 2>&1 | while read -r line; do
            if [[ "$line" =~ \[[[:space:]]*([0-9]+)%\] ]]; then
                percent="${BASH_REMATCH[1]}"
                echo "XXX"; echo "$percent"; echo "$line"; echo "XXX"
            elif [[ "$line" =~ Doxygen ]]; then
                echo "XXX"; echo "100"; echo "$line"; echo "XXX"
            fi
        done
    ) | dialog --title "make doc" --gauge "Building documentation..." 15 70 0
}

#=========================================================================================
run_make_install() {
    (
        sudo make install > /dev/null 2>&1
    ) &
    cmake_pid=$!
    {
        percent=0
        while kill -0 $cmake_pid 2>/dev/null; do
            percent=$(( (percent + 5) % 95 ))
            echo $percent
            sleep 1
        done
        echo 100
    } | dialog --title "make install" --gauge "Installing SvxLink..." 10 60 0
}

#=========================================================================================
enable_uart_and_serial0() {
    dialog --title "UART Setup" --infobox "Enabling UART and disabling serial console..." 8 50
    sleep 2
    sudo sed -i '/enable_uart=/d' /boot/firmware/config.txt
    echo "enable_uart=1" | sudo tee -a /boot/firmware/config.txt >/dev/null
    grep -q "^dtoverlay=disable-bt" /boot/firmware/config.txt || echo "dtoverlay=disable-bt" | sudo tee -a /boot/firmware/config.txt >/dev/null
    grep -q "^core_freq=250" /boot/firmware/config.txt || echo "core_freq=250" | sudo tee -a /boot/firmware/config.txt >/dev/null
    for svc in serial-getty@ttyAMA0.service serial-getty@ttyS0.service; do
        sudo systemctl disable --now "$svc" >/dev/null 2>&1
        sudo systemctl mask "$svc" >/dev/null 2>&1
    done
    cat <<EOF | sudo tee /etc/udev/rules.d/99-serial0.rules >/dev/null
KERNEL=="ttyAMA0", SYMLINK+="serial0", GROUP="dialout", MODE="0660"
EOF
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    #dialog --title "Reboot Required" --msgbox "UART enabled, Bluetooth disabled, serial-getty masked.\n\nSystem must reboot now." 12 60
    #clear
    #sudo reboot
}

#=========================================================================================
change_files() {
    dialog --title "Permissions" --infobox "Making install.sh and sa818_menu.sh executable..." 8 50
    sleep 1
    local sa818_menu_file="$base_source_path/src/svxlink/scripts/sa818/sa818_menu.sh"
    local install_file="$base_source_path/install.sh"
    [[ -f "$sa818_menu_file" ]] && sudo chmod +x "$sa818_menu_file"
    [[ -f "$install_file" ]] && sudo chmod +x "$install_file"
    dialog --title "Permissions" --msgbox "Executable set for:\n$sa818_menu_file\n$install_file" 12 60
}

#=========================================================================================
install_pyserial() {
    dialog --title "Dependencies" --infobox "Installing Python pyserial..." 8 50
    sudo apt-get install -y python3-serial > /dev/null 2>&1
}

#=========================================================================================
install_sounds() {
    dialog --title "Sound Files" --infobox "Installing English Heather sound pack...\nThis may take ~1 minute." 10 60
    sleep 2
    cd "$default_install_path/share/svxlink/sounds" || {
        dialog --title "Error" --msgbox "Could not change to $default_install_path/share/svxlink/sounds" 10 60
        exit 1
    }
    {
        echo "XXX"; echo "20"; echo "Downloading sound pack..."; echo "XXX"
        sudo wget -q https://github.com/sm0svx/svxlink-sounds-en_US-heather/releases/download/14.08/svxlink-sounds-en_US-heather-16k-13.12.tar.bz2
        echo "XXX"; echo "60"; echo "Extracting..."; echo "XXX"
        sudo tar xjf svxlink-sounds-en_US-heather-16k-13.12.tar.bz2
        echo "XXX"; echo "80"; echo "Creating symlink..."; echo "XXX"
        [[ -d "en_US-heather-16k" ]] && sudo ln -sfn en_US-heather-16k en_US
        echo "XXX"; echo "100"; echo "Cleaning up..."; echo "XXX"
        sudo rm -f svxlink-sounds-en_US-heather-16k-13.12.tar.bz2
    } | dialog --title "Sound Files" --gauge "Installing sound pack..." 12 70 0
    dialog --title "Sound Files" --msgbox "Installed at:\n$default_install_path/share/svxlink/sounds/en_US" 12 60
}

#=========================================================================================
run_with_log() {
    local func="$1"
    shift
    local logfile="$LOG_DIR/${func}.log"
    echo "=== Running $func at $(date) ===" | sudo tee "$logfile" >/dev/null
    $func "$@" >> >(sudo tee -a "$logfile") 2>&1
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        dialog --title "Error" --msgbox "func failed.\nSee log: $logfile" 12 60
        exit $rc
    else
        echo "=== $func completed OK at $(date) ===" | sudo tee -a "$logfile" >/dev/null
    fi
}

#=========================================================================================
ask_sa818_hardware() {
    dialog --title "SA818 Hardware" --yesno "Do you have SA818 hardware installed?" 10 60
    if [[ $? -eq 0 ]]; then
        SKIP_SA818=0
    else
        SKIP_SA818=1
    fi
    ini_file="$base_source_path/install_path.ini"
    echo "skip_sa818=$SKIP_SA818" | sudo tee -a "$ini_file" > /dev/null
}

#==================================================================

welcome_text() {
dialog --title "Welcome to SvxLink Installer" --msgbox "\
Welcome to the SvxLink installation script!

This SvxLink version has some modification enable to work 
with the SvxLink_Remote Android App.
But can be used for all installs read the install_readme
for more information.


This script will:
  Check and install all required dependencies
  Build and install SvxLink from source
  Configure your system paths and services
  Install English Heather voice prompts
  Optionally configure SA818 hardware support

Info:
   I you don't have a addon radio board like SA818 with sound chip
   you have to configure you hardware yourself :
    
Note: Some steps may take several minutes. Do not interrupt.

Press <OK> to continue." 30 70
}

#==========================================================================================
create_bash_aliases() {
    local username
    username=$(logname 2>/dev/null || echo "$USER")
    local user_home="/home/$username"
    local aliases_file="$user_home/.bash_aliases"

    dialog --title "Bash Aliases" --infobox "Creating .bash_aliases for user: $username" 8 50
    sleep 2

    # Ensure .bash_aliases exists
    sudo touch "$aliases_file"
    sudo chown "$username":"$username" "$aliases_file"

    # Write aliases (replace path with $default_install_path)
    cat <<EOF | sudo tee "$aliases_file" >/dev/null
# aliases svxlink
alias svxlog="tail -f $default_install_path/var/log/svxlink.log"
alias svxconf="sudo nano $default_install_path/svxlink/svxlink.conf"
alias svxstart="sudo systemctl start svxlink"
alias svxstop="sudo systemctl stop svxlink"
alias svxstatus="sudo systemctl status svxlink"
alias svxrestart="sudo systemctl restart svxlink"
alias down="sudo shutdown now"
alias restart="sudo reboot now"

alias metarconf="sudo nano $default_install_path/svxlink/svxlink.d/ModuleMetarInfo.conf"
alias echolinkconf="sudo nano $default_install_path/svxlink/svxlink.d/ModuleEchoLink.conf"
alias helpconf="sudo nano $default_install_path/svxlink/svxlink.d/ModuleHelp.conf"

# udev
alias reload_udev="sudo udevadm control --reload-rules && sudo udevadm trigger"
EOF

    # Ensure .bashrc loads .bash_aliases
    if ! grep -q "if \[ -f ~/.bash_aliases \]" "$user_home/.bashrc"; then
        echo -e "\n# Load aliases\nif [ -f ~/.bash_aliases ]; then\n    . ~/.bash_aliases\nfi" | sudo tee -a "$user_home/.bashrc" >/dev/null
    fi

    dialog --title "Bash Aliases" --msgbox "Aliases file created at:\n$aliases_file\n\nThe following commands are now available:\n  svxlog, svxconf, svxstart, svxstop, svxstatus, svxrestart, down, restart\n\To activate immediately, run:\n  source ~/.bashrc\n\nOr restart your shell." 18 70
}

#=========================================================================================
ask_svxlink_remote() {
    # 1) Ask about SvxLink Remote app
    dialog --title "SvxLink Remote (Android)" \
           --yesno "Do you plan to use the SvxLink Remote Android app?" 9 65
    if [[ $? -eq 0 ]]; then
        USE_SVXLINK_REMOTE=1

        # 2) Follow-up: EchoLink connection info to phone?
        dialog --title "EchoLink Info on Phone" \
               --yesno "Do you want to receive EchoLink connection information on the phone?" 9 75
        if [[ $? -eq 0 ]]; then
            ECHOLINK_INFO_TO_PHONE=1
        else
            ECHOLINK_INFO_TO_PHONE=0
        fi
    else
        USE_SVXLINK_REMOTE=0
        ECHOLINK_INFO_TO_PHONE=0
    fi
    export USE_SVXLINK_REMOTE ECHOLINK_INFO_TO_PHONE

    # Persist into install_path.ini (created earlier by ask_paths)
    local ini_file="$base_source_path/install_path.ini"
    sudo mkdir -p "$base_source_path"
    sudo touch "$ini_file"

    # Update or append keys
    if sudo grep -Eq '^[[:space:]]*use_svxlink_remote=' "$ini_file"; then
        sudo sed -i -E "s|^[[:space:]]*use_svxlink_remote=.*|use_svxlink_remote=${USE_SVXLINK_REMOTE}|" "$ini_file"
    else
        echo "use_svxlink_remote=${USE_SVXLINK_REMOTE}" | sudo tee -a "$ini_file" >/dev/null
    fi

    if sudo grep -Eq '^[[:space:]]*echolink_info_to_phone=' "$ini_file"; then
        sudo sed -i -E "s|^[[:space:]]*echolink_info_to_phone=.*|echolink_info_to_phone=${ECHOLINK_INFO_TO_PHONE}|" "$ini_file"
    else
        echo "echolink_info_to_phone=${ECHOLINK_INFO_TO_PHONE}" | sudo tee -a "$ini_file" >/dev/null
    fi

    dialog --title "Saved" --msgbox "Saved to $ini_file:\n  use_svxlink_remote=${USE_SVXLINK_REMOTE}\n  echolink_info_to_phone=${ECHOLINK_INFO_TO_PHONE}" 10 75
    clear
}
#=========================================================================================
copy_qsoimpl_if_remote() {
    # Read choice saved by ask_svxlink_remote
    local ini_file="${base_source_path:-$(echo "$default_source_path" | awk -F/ '{print "/"$2"/"$3}')}/install_path.ini"
    local use_remote=""

    if [[ -f "$ini_file" ]]; then
        use_remote=$(grep -E '^use_svxlink_remote=' "$ini_file" | tail -n1 | cut -d= -f2)
    elif [[ -n "${USE_SVXLINK_REMOTE:-}" ]]; then
        use_remote="$USE_SVXLINK_REMOTE"
    fi

    if [[ "$use_remote" != "1" ]]; then
        dialog --title "Copy QsoImpl" --msgbox "SvxLink Remote not enabled.\nNo files will be copied." 8 60
        clear
        return
    fi

    # Resolve source root:
    # Prefer base_source_path set by ask_paths; otherwise derive from default_source_path (e.g., /opt/svxlink).
    local SRC_ROOT="${base_source_path:-$(echo "$default_source_path" | awk -F/ '{print "/"$2"/"$3}')}"
    # Build paths relative to the source root
    local src_dir="$SRC_ROOT/src/svxlink/scripts"
    local dest_dir="$SRC_ROOT/src/svxlink/modules/echolink"
    local files=("QsoImpl.h" "QsoImpl.cpp")

    # Validate sources
    local missing=()
    for f in "${files[@]}"; do
        [[ -f "$src_dir/$f" ]] || missing+=("$f")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        dialog --title "Copy QsoImpl" --msgbox "Missing source file(s): ${missing[*]}\nExpected in: $src_dir" 10 72
        clear
        return 1
    fi

    # Ensure destination exists
    sudo mkdir -p "$dest_dir"

    # Overwrite prompt if needed
    local need_overwrite=0
    for f in "${files[@]}"; do
        [[ -f "$dest_dir/$f" ]] && need_overwrite=1
    done
    if [[ $need_overwrite -eq 1 ]]; then
        dialog --title "Overwrite Files?" --yesno "Files already exist in:\n$dest_dir\n\nOverwrite them?" 10 70
        [[ $? -ne 0 ]] && { dialog --title "Copy QsoImpl" --msgbox "Copy cancelled." 7 40; clear; return; }
    fi

    # Copy with a gauge
    {
        echo "XXX"; echo "20"; echo "Copying QsoImpl.h..."; echo "XXX"
        sudo cp -f "$src_dir/QsoImpl.h" "$dest_dir/"
        echo "XXX"; echo "65"; echo "Copying QsoImpl.cpp..."; echo "XXX"
        sudo cp -f "$src_dir/QsoImpl.cpp" "$dest_dir/"
        echo "XXX"; echo "100"; echo "Done."; echo "XXX"
    } | dialog --title "Copy QsoImpl files" --gauge "Working..." 10 60 0

    dialog --title "Copy QsoImpl" --msgbox "Copied files to:\n$dest_dir\n\n- QsoImpl.h\n- QsoImpl.cpp" 11 65
    clear
}

#=========================================================================================
# --- RUN MAIN ---
main
