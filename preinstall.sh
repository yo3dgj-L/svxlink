anny #!/bin/bash
clear

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
    ask_sa818_hardware
    check_cmake_and_packages
    check_libssl
    ensure_svxlink_user
    prepare_build
    run_make
    run_make_doc
    run_make_install
    change_files
    create_bash_aliases

    if [[ "$SKIP_SA818" -eq 0 ]]; then
        run_with_log install_pyserial
        run_with_log enable_uart_and_serial0
        dialog --title "Reboot Required" --msgbox "✅ UART enabled and udev rule installed.\n\nSystem must reboot now." 12 60
        sleep 1
        clear
        sudo reboot
    else
        dialog --title "SA818 Skipped" --msgbox "⚠️ You chose not to configure SA818 hardware.\n\nSkipping UART and serial setup." 12 60
    fi

    install_sounds
}

#=========================================================================================
check_dialog() {
    
    if dpkg -s dialog 2>/dev/null | grep -q 'Status: install ok installed'; then
        dialog --title "Dialog" --msgbox "✅ 'dialog' is already installed." 8 40
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
        dialog --title "Dependencies" --msgbox "✅ cmake already installed." 8 50
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
                count=$((count+1))
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
        dialog --title "Dependencies" --msgbox "✅ libssl-dev already installed." 8 50
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
ensure_svxlink_user() {
    dialog --title "User Setup" --infobox "Checking if user 'svxlink' exists..." 8 50
    sleep 1
    if id "svxlink" &>/dev/null; then
        sudo usermod -aG audio,plugdev,gpio,dialout svxlink
        dialog --title "User Setup" --msgbox "✅ User 'svxlink' exists.\nGroups updated." 10 60
    else
        sudo useradd -m -G audio,plugdev,gpio,dialout svxlink
        dialog --title "User Setup" --msgbox "✅ User 'svxlink' created and added to groups." 10 60
    fi
    clear
}

#=========================================================================================
ask_paths() {
    while true; do
        install_path_source=$(dialog --title "SvxLink Sources" \
            --inputbox "Enter path where SvxLink sources/build are:\n\nUse a structure like /x1/x2/x3/x4" 12 70 "$default_source_path" \
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
    dialog --title "Reboot Required" --msgbox "✅ UART enabled, Bluetooth disabled, serial-getty masked.\n\nSystem must reboot now." 12 60
    sudo reboot
}

#=========================================================================================
change_files() {
    dialog --title "Permissions" --infobox "Making install.sh and sa818_menu.sh executable..." 8 50
    sleep 1
    local sa818_menu_file="$base_source_path/src/svxlink/scripts/sa818/sa818_menu.sh"
    local install_file="$base_source_path/install.sh"
    [[ -f "$sa818_menu_file" ]] && sudo chmod +x "$sa818_menu_file"
    [[ -f "$install_file" ]] && sudo chmod +x "$install_file"
    dialog --title "Permissions" --msgbox "✅ Executable set for:\n$sa818_menu_file\n$install_file" 12 60
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
        dialog --title "Error" --msgbox "❌ Could not change to $default_install_path/share/svxlink/sounds" 10 60
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
    dialog --title "Sound Files" --msgbox "✅ Installed at:\n$default_install_path/share/svxlink/sounds/en_US" 12 60
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
        dialog --title "Error" --msgbox "❌ $func failed.\nSee log: $logfile" 12 60
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
  • Check and install all required dependencies
  • Build and install SvxLink from source
  • Configure your system paths and services
  • Install English Heather voice prompts
  • Optionally configure SA818 hardware support

Info:
   I you don't have a addon radio board like SA818 with sound chip
   you have to configure you hardware yourself :
    
⚠️ Note: Some steps may take several minutes. Do not interrupt.

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

    dialog --title "Bash Aliases" --msgbox "✅ Aliases file created at:\n$aliases_file\n\nThe following commands are now available:\n  svxlog, svxconf, svxstart, svxstop, svxstatus, svxrestart, down, restart\n\n👉 To activate immediately, run:\n  source ~/.bashrc\n\nOr restart your shell." 18 70
}

#=========================================================================================
# --- RUN MAIN ---
main
