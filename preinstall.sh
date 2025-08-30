#!/bin/bash
clear

# --- GLOBALS ---
default_source_path="/opt/svxlink/src/build"
default_install_path="/opt/mysvxlink"

#=========================================================================================
main() {
    #check_dialog
    #check_cmake_and_packages
    #check_libssl
    #ensure_svxlink_user
    ask_paths
    #prepare_build
    #run_make
    #run_make_doc
    #run_make_install
         setup_sa818_files	
    #enable_uart_serial

    dialog --title "Preinstall Complete" --msgbox "? Preinstall complete!\n\nNow run:\n$default_install_path/install.sh" 10 60
    clear
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

    sudo mkdir -p "$install_path_source"
    cd "$install_path_source"
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
#========================================================================================

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
setup_sa818_files() {
    dialog --title "SA818 Setup" --infobox "Setting up SA818 support files...\n\nPlease wait..." 10 60
    sleep 1

    # Source base path (strip off /build from default_source_path)
    local source_base="${default_source_path%/build}"

    local source_dir="$source_base/svxlink/scripts/sa818"
    local dest_dir="$default_install_path/share/svxlink/sa818"

    # Create destination folder
    sudo mkdir -p "$dest_dir"

    # Copy files if source exists
    if [[ -d "$source_dir" ]]; then
        sudo cp -r "$source_dir/"* "$dest_dir/"
    else
        dialog --title "SA818 Setup" --msgbox "? Source folder not found:\n$source_dir" 10 60
        return 1
    fi

    # Make sa818_menu.sh executable
    if [[ -f "$dest_dir/sa818_menu.sh" ]]; then
        sudo chmod +x "$dest_dir/sa818_menu.sh"
    fi

    # Make install.sh executable
    if [[ -f "$default_install_path/install.sh" ]]; then
        sudo chmod +x "$default_install_path/install.sh"
    fi

    dialog --title "SA818 Setup" --msgbox "? SA818 files have been installed:\n\nSource: $source_dir\nDestination: $dest_dir\n\nScripts made executable." 12 60
}


#=========================================================================================
# --- RUN MAIN ---
main
