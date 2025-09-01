#!/bin/bash
clear

# --- GLOBALS ---
default_source_path="/opt/svxlink/src/build"
default_install_path="/opt/mysvxlink"

#=========================================================================================
main() {

     LOG_DIR="/var/log/svxlink-install"
     sudo mkdir -p "$LOG_DIR"

    check_dialog
    ask_paths   # moved here
    check_cmake_and_packages
    check_libssl
    ensure_svxlink_user
    prepare_build
    run_make
    run_make_doc
    run_make_install
    change_files
    
        if [[ "$SKIP_SA818" -eq 0 ]]; then
        	run_with_log install_pyserial
        	run_with_log enable_uart_serial
        	run_with_log install_serial0_udev_rule

        	dialog --title "Reboot Required" --msgbox "UART enabled, udev rule installed.\n\nSystem must reboot to apply changes." 12 60
        	sleep 2
        	clear
        	sudo reboot
    else
        	dialog --title "SA818 Skipped" --msgbox "You chose not to configure SA818 hardware.\n\nSkipping UART and serial setup." 12 60
    fi

}

#=========================================================================================
check_dialog() {
    if dpkg -s dialog 2>/dev/null | grep -q 'Status: install ok installed'; then
        echo "Dialog already installed"
        sleep 1
    else
        echo "Installing Dialog..."
        sudo apt install dialog -y
    fi
    clear
}

#=========================================================================================
check_cmake_and_packages() {
    if dpkg -s cmake 2>/dev/null | grep -q "Status: install ok installed"; then
        dialog --title "Preinstall Processing" --infobox "CMAKE already installed" 8 40
        sleep 1
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

                echo "XXX"
                echo "$percent"
                echo "Installing $pkg ($count of $total)..."
                echo "XXX"

                sudo apt-get install -y "$pkg" > /dev/null 2>&1
            done
        } | dialog --title "Installing Dependencies" --gauge "Preparing to install..." 15 70 0
    fi
    clear
}

#=========================================================================================
check_libssl() {
    if dpkg -s libssl-dev 2>/dev/null | grep -q "Status: install ok installed"; then
        dialog --title "Preinstall Processing" --infobox "libssl-dev already installed" 8 40
        sleep 1
    else
        dialog --title "Installing libssl-dev" --infobox "Please wait..." 8 40
        sudo apt-get install -y libssl-dev > /dev/null 2>&1
    fi
    clear
}

#=========================================================================================
ensure_svxlink_user() {
    if id "svxlink" &>/dev/null; then
        dialog --title "User Check" --yesno "User 'svxlink' already exists.\n\nAdd it to groups: audio, plugdev, gpio, dialout ?" 12 60
        if [ $? -eq 0 ]; then
            sudo usermod -aG audio,plugdev,gpio,dialout svxlink
            dialog --title "User Updated" --msgbox "User 'svxlink' updated." 8 50
        fi
    else
        dialog --title "User Missing" --yesno "User 'svxlink' does not exist.\n\nCreate it and add to groups: audio, plugdev, gpio, dialout ?" 12 60
        if [ $? -eq 0 ]; then
            sudo useradd -m -G audio,plugdev,gpio,dialout svxlink
            dialog --title "User Created" --msgbox "User 'svxlink' created." 8 50
        fi
    fi
    clear
}

#=========================================================================================
ask_paths() {
    while true; do
        # Ask source path
        install_path_source=$(dialog --title "SvxLink Sources" \
            --inputbox "Enter path where SvxLink sources/build are:" 10 60 "$default_source_path" \
            3>&1 1>&2 2>&3 3>&-)
        [[ $? -ne 0 ]] && exit 1

        # Ask install path
        install_path_svxlink=$(dialog --title "SvxLink Installation Path" \
            --inputbox "Enter where SvxLink must be installed:" 10 60 "$default_install_path" \
            3>&1 1>&2 2>&3 3>&-)
        [[ $? -ne 0 ]] && exit 1

        # Extract base_source_path ? only first two directories
        base_source_path=$(echo "$install_path_source" | awk -F/ '{print "/"$2"/"$3}')

        # Confirmation dialog
        dialog --title "Confirm Paths" --yesno "You have chosen:\n\nSource Path:\n$install_path_source\n\nInstall Path:\n$install_path_svxlink\n\nBase Path:\n$base_source_path\n\nAre you sure you want to continue?" 18 60

        if [[ $? -eq 0 ]]; then
            # Yes ? proceed
            sudo mkdir -p "$install_path_source"
            cd "$install_path_source"

            # Write paths to install_path.ini
            ini_file="$base_source_path/install_path.ini"
            sudo mkdir -p "$base_source_path"
            {
                echo "source_path=$install_path_source"
                echo "install_path=$install_path_svxlink"
                echo "base_path=$base_source_path"
            } | sudo tee "$ini_file" > /dev/null

            break
        fi
        # If No ? loop again
    done
}

#=========================================================================================
prepare_build() {
    dialog --title "Preinstall Processing" --infobox "Running cmake, please wait..." 10 60

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
    dialog --title "Preinstall Processing" --infobox "Running make -j4..." 10 60

    (
        sudo make -j4 2>&1 | \
        while read -r line; do
            if [[ "$line" =~ \[[[:space:]]*([0-9]+)%\] ]]; then
                percent="${BASH_REMATCH[1]}"
                echo "XXX"
                echo "$percent"
                echo "$line"
                echo "XXX"
            fi
        done | dialog --title "make -j4 in Progress" --gauge "Compiling SvxLink..." 15 70 0
    )
}

#=========================================================================================
run_make_doc() {
    dialog --title "Preinstall Processing" --infobox "Running make doc..." 10 60

    (
        sudo make doc 2>&1 | \
        while read -r line; do
            if [[ "$line" =~ \[[[:space:]]*([0-9]+)%\] ]]; then
                percent="${BASH_REMATCH[1]}"
                echo "XXX"
                echo "$percent"
                echo "$line"
                echo "XXX"
            elif [[ "$line" =~ Doxygen ]]; then
                echo "XXX"
                echo "100"
                echo "$line"
                echo "XXX"
            fi
        done | dialog --title "make doc in Progress" --gauge "Building documentation..." 15 70 0
    )
}

#=========================================================================================
run_make_install() {
    dialog --title "Preinstall Processing" --infobox "Running make install..." 10 60

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
enable_uart_serial() {
    dialog --title "UART Setup" --infobox "Configuring UART and disabling serial console...\n\nPlease wait..." 10 60
    sleep 2

    # Enable UART in config.txt
    sudo sed -i '/enable_uart=/d' /boot/firmware/config.txt
    echo "enable_uart=1" | sudo tee -a /boot/firmware/config.txt >/dev/null

    # Disable serial console login
    sudo systemctl disable serial-getty@ttyAMA0.service >/dev/null 2>&1
    sudo systemctl stop serial-getty@ttyAMA0.service >/dev/null 2>&1

    # Force serial0 to map to full UART (ttyAMA0)
    if ! grep -q "dtoverlay=disable-bt" /boot/firmware/config.txt; then
        echo "dtoverlay=disable-bt" | sudo tee -a /boot/firmware/config.txt >/dev/null
    fi

    dialog --title "Reboot Required" --msgbox "? UART has been enabled and serial console disabled.\n\nA system reboot is required to apply these changes.\n\nPress OK to reboot now." 12 60

    sudo reboot
}

#=========================================================================================
change_files() {
    dialog --title "Change Files" --infobox "make install.sh and sa818_menu executable...\n\nPlease wait..." 10 60
    sleep 1

    # Paths
    local sa818_menu_file="$base_source_path/src/svxlink/scripts/sa818/sa818_menu.sh"
    local install_file="$base_source_path/install.sh"

    # Make sa818_menu.sh executable if it exists
    if [[ -f "$sa818_menu_file" ]]; then
        sudo chmod +x "$sa818_menu_file"
    else
        dialog --title "Change Files" --msgbox "? File not found:\n$sa818_menu_file" 10 60
    fi

    # Make install.sh executable if it exists
    if [[ -f "$install_file" ]]; then
        sudo chmod +x "$install_file"
    else
        dialog --title "Change Files" --msgbox "? File not found:\n$install_file" 10 60
    fi

    dialog --title "Change Files" --msgbox "? Change Files complete.\n\nChecked files:\n$sa818_menu_file\n$install_file\n\nScripts made executable if found." 12 60
}

clear
#====================================================================================================

#!/bin/bash

#==========================================================================================
install_pyserial() {
    dialog --title "Dependencies" --infobox "Installing Python serial library..." 8 50
    sudo apt-get update -y
    sudo apt-get install -y python3-serial
}

#==========================================================================================
enable_uart_serial() {
    dialog --title "UART Setup" --infobox "Configuring UART and disabling serial console..." 10 60
    sleep 2

    # Enable UART in config.txt
    sudo sed -i '/enable_uart=/d' /boot/firmware/config.txt
    echo "enable_uart=1" | sudo tee -a /boot/firmware/config.txt >/dev/null

    # Disable serial console login
    sudo systemctl disable serial-getty@ttyAMA0.service >/dev/null 2>&1
    sudo systemctl stop serial-getty@ttyAMA0.service >/dev/null 2>&1

    # Force serial0 to map to full UART (disable Bluetooth console)
    if ! grep -q "dtoverlay=disable-bt" /boot/firmware/config.txt; then
        echo "dtoverlay=disable-bt" | sudo tee -a /boot/firmware/config.txt >/dev/null
    fi
}

#==========================================================================================
install_serial0_udev_rule() {
    dialog --title "UART Permissions" --infobox "Installing udev rule for /dev/serial0..." 8 50
    sleep 2

    cat <<EOF | sudo tee /etc/udev/rules.d/99-serial0.rules >/dev/null
# Ensure /dev/serial0 is accessible to the 'dialout' group
KERNEL=="ttyAMA0", SYMLINK+="serial0", GROUP="dialout", MODE="0660"
KERNEL=="ttyS0",   SYMLINK+="serial0", GROUP="dialout", MODE="0660"
EOF

    sudo udevadm control --reload-rules
    sudo udevadm trigger
}

#==========================================================================================

run_with_log() {
    local func="$1"
    shift
    local logfile="$LOG_DIR/${func}.log"

    echo "=== Running $func at $(date) ===" | sudo tee "$logfile" >/dev/null
    $func "$@" >> >(sudo tee -a "$logfile") 2>&1
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        dialog --title "Error" --msgbox "? $func failed.\n\nSee log:\n$logfile" 12 60
        exit $rc
    else
        echo "=== $func completed OK at $(date) ===" | sudo tee -a "$logfile" >/dev/null
    fi
}

#=====================================================================================================

ask_sa818_hardware() {
    dialog --title "SA818 Hardware" --yesno "Do you have SA818 hardware installed and want to configure it now?" 10 60
    if [[ $? -eq 0 ]]; then
        SKIP_SA818=0
    else
        SKIP_SA818=1
    fi

    # Save to ini file for install.sh
    ini_file="$base_source_path/install_path.ini"
    echo "skip_sa818=$SKIP_SA818" | sudo tee -a "$ini_file" > /dev/null
}

#==========================================================================================
# --- RUN MAIN ---
main
