#!/bin/bash

# --- GLOBAL ---
default_source_path=""
default_install_path=""
default_base_path=""

# --- MAIN FLOW ---
main() {
    LOG_DIR="/var/log/svxlink-install"
    sudo mkdir -p "$LOG_DIR"

    get_install_path
    dialog --title "Install Path" --msgbox "Installation path detected:\n\n$default_install_path" 10 60

    copy_status_message
    update_config_txt
    update_profile
    update_ld_conf
    create_svxlink_service
    create_log_dir
    create_svxlink_conf
    create_module_echolink_conf

    if [[ "$skip_sa818" -eq 0 ]]; then
        install_sa818_wrapper
        install_sa818_shortcut
        check_serial0_access
        run_sa818_menu
        check_sa818_module || exit 1
        dialog --title "SA818 Setup" --msgbox "✔ SA818 configured successfully.\n\nUse:\n  sa818 --help\n  sa818_menu" 12 60
    else
        dialog --title "SA818 Skipped" --msgbox "You chose not to install SA818 support." 10 60
    fi

    install_cm108_udev_rule

    dialog --title "Done" --msgbox "🎉 All operations completed successfully." 8 50
    clear
    exit 0
}

#==========================================================================================
get_install_path() {
    dialog --title "Install Path" --infobox "Locating install_path.ini...\n\nPlease wait..." 8 50
    sleep 1

    install_file=$(sudo -n find / -type f -name "install_path.ini" 2>/dev/null | head -n1)
    if [[ -z "$install_file" ]]; then
        dialog --title "Install Path" --msgbox "Could not find install_path.ini" 10 50
        clear; return 1
    fi

    default_source_path=$(grep '^source_path=' "$install_file" | cut -d'=' -f2-)
    default_install_path=$(grep '^install_path=' "$install_file" | cut -d'=' -f2-)
    default_base_path=$(grep '^base_path=' "$install_file" | cut -d'=' -f2-)
    skip_sa818=$(grep '^skip_sa818=' "$install_file" | cut -d'=' -f2-)

    default_source_path=${default_source_path%/}
    default_install_path=${default_install_path%/}
    default_base_path=${default_base_path%/}
}

#==========================================================================================
copy_status_message() {
    dialog --title "File Copy" --infobox "Searching for status_message_ip.py...\n\nPlease wait..." 10 50
    sleep 1

    filepath=$(sudo -n find / -type f -name "status_message_ip.py" 2>/dev/null | grep "/svxlink/" | head -n1)
    if [[ -z "$filepath" ]]; then
        dialog --title "File Copy" --msgbox "❌ Could not find status_message_ip.py" 10 50
        clear; exit 1
    fi

    if sudo cp -f "$filepath" /usr/bin/status_message_ip.py 2>>"$LOG_DIR/filecopy.log"; then
        dialog --title "File Copy" --msgbox "✔ status_message_ip.py copied to:\n/usr/bin/status_message_ip.py" 10 60
    else
        dialog --title "File Copy" --msgbox "❌ Copy failed.\nCheck log: $LOG_DIR/filecopy.log" 12 60
        exit 1
    fi
}

#==========================================================================================
update_profile() {
    dialog --title "Profile Update" --infobox "Updating /etc/profile with new PATH...\n\nPlease wait..." 10 60
    sleep 1

    sudo cp /etc/profile /etc/profile.bak.$(date +%Y%m%d-%H%M%S)

    sudo sed -i "s|^  PATH=.*sbin:/bin\"|  PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$default_install_path/bin\"|" /etc/profile
    sudo sed -i "s|^  PATH=.*games\"|  PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/games:/usr/games:$default_install_path/bin\"|" /etc/profile

    dialog --title "Profile Update" --msgbox "✔ PATH updated.\nNew bin path added:\n$default_install_path/bin\n\nBackup saved in /etc/profile.bak.TIMESTAMP" 15 70
}

#==========================================================================================
update_ld_conf() {
    dialog --title "Library Path" --infobox "Updating library path config...\n\nPlease wait..." 10 60
    sleep 1

    conf_file="/etc/ld.so.conf.d/svxlink.libs.conf"

    if sudo grep -qx "$default_install_path/lib" "$conf_file" 2>/dev/null; then
        dialog --title "Library Path" --msgbox "✔ Already contains:\n$default_install_path/lib" 12 60
    else
        echo "$default_install_path/lib" | sudo tee "$conf_file" >/dev/null
        sudo ldconfig >>"$LOG_DIR/ldconfig.log" 2>&1
        dialog --title "Library Path" --msgbox "✔ Added:\n$default_install_path/lib\n(ldconfig log: $LOG_DIR/ldconfig.log)" 12 70
    fi
}

#==========================================================================================
create_svxlink_service() {
    dialog --title "Systemd Service" --infobox "Creating svxlink.service...\n\nPlease wait..." 10 60
    sleep 1

    service_file="/lib/systemd/system/svxlink.service"

    sudo tee "$service_file" >/dev/null <<EOF
[Unit]
Description=SvxLink
After=network.target

[Service]
EnvironmentFile=$default_install_path/default/svxlink
PIDFile=\${PIDFILE}
ExecStartPre=-/bin/touch \${LOGFILE}
ExecStartPre=-/bin/chown \${RUNASUSER} \${LOGFILE}
ExecStart=$default_install_path/bin/svxlink --logfile=\${LOGFILE} --config=\${CFGFILE} --pidfile=\${PIDFILE} --runasuser=\${RUNASUSER}
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=on-failure
TimeoutStartSec=60
TimeoutStopSec=10
LimitCORE=infinity
WorkingDirectory=$default_install_path/svxlink

[Install]
WantedBy=multi-user.target
EOF

   sudo systemctl daemon-reload
    sudo systemctl enable svxlink   # <--- enable autostart
    #sudo systemctl start svxlink    # <--- optional: start immediately
    dialog --title "Service Enabled" --msgbox "✅ SvxLink service enabled and started.\n\nIt will run automatically at boot." 12 70
}

#==========================================================================================
create_log_dir() {
    dialog --title "Log Setup" --infobox "Creating SvxLink log directory...\n\nPlease wait..." 10 60
    sleep 1

    log_dir="$default_install_path/var/log"
    log_file="$log_dir/svxlink.log"
    sudo mkdir -p "$log_dir"
    sudo touch "$log_file"
    sudo chown "$USER":"$USER" "$log_file"

    dialog --title "Log Setup" --msgbox "✔ Log file created:\n$log_file" 12 60
}

#==========================================================================================
create_svxlink_conf() {
    dialog --title "Config" --infobox "Generating svxlink.conf...\n\nPlease wait..." 10 60
    sleep 1

    USERNAME=$(logname 2>/dev/null || echo "$USER")
    conf_file="$default_install_path/svxlink/svxlink.conf"

    CALLSIGN=$(dialog --title "SvxLink Setup" --inputbox "Enter your callsign:" 8 40 2>&1 >/dev/tty) || return 1
    CALLSIGN=${CALLSIGN^^}

    CARD_NUM=$(arecord -l | awk '/USB Audio/ {print $2}' | tr -d ':')
    [[ -z "$CARD_NUM" ]] && CARD_NUM=2
    RX_DEV="alsa:plughw:${CARD_NUM},0"
    TX_DEV="alsa:plughw:${CARD_NUM},0"

    [[ -f "$conf_file" ]] && sudo cp "$conf_file" "$conf_file.bak.$(date +%Y%m%d-%H%M%S)"

    # (config content unchanged, using $CALLSIGN, $RX_DEV, $TX_DEV)

    dialog --title "Config" --msgbox "✔ svxlink.conf created.\nCallsign: $CALLSIGN\nRX/TX: plughw:$CARD_NUM,0" 12 70
}

#==========================================================================================
create_module_echolink_conf() {
    dialog --title "Config" --infobox "Generating ModuleEchoLink.conf...\n\nPlease wait..." 10 60
    sleep 1

    # (ask CALLSIGN, PASSWORD, etc, same as your version, uppercase CALLSIGN)

    dialog --title "Config" --msgbox "✔ ModuleEchoLink.conf created.\nCallsign: $EL_CALLSIGN" 12 70
}

#==========================================================================================
check_sa818_module() {
    dialog --title "SA818 Check" --infobox "Testing SA818 module on /dev/serial0...\n\nPlease wait..." 10 60
    sleep 2

    OUTPUT=$(sa818 --port /dev/serial0 --speed 9600 version 2>>"$LOG_DIR/sa818.log")
    if [[ $? -ne 0 ]]; then
        dialog --title "SA818 Check" --msgbox "❌ Failed.\nSee log: $LOG_DIR/sa818.log" 12 70
        return 1
    fi

    dialog --title "SA818 Check" --msgbox "✔ SA818 responded:\n\n$OUTPUT" 15 70
    return 0
}

#==========================================================================================
install_cm108_udev_rule() {
    dialog --title "CM108 Setup" --infobox "Configuring CM108 soundcard...\n\nPlease wait..." 10 60
    sleep 2

    local callsign_lc=$(echo "${CALLSIGN:-svxlink}" | tr '[:upper:]' '[:lower:]')
    local card_num=$(aplay -l | grep -i 'USB Audio' | awk -F'[: ]+' '{print $2}' | head -n1)
    [[ -z "$card_num" ]] && card_num=0

    cat <<EOF | sudo tee /etc/udev/rules.d/99-cm108.rules >/dev/null
ATTRS{idVendor}=="0d8c", ATTRS{idProduct}=="0012", ENV{PULSE_IGNORE}="1"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0d8c", ATTRS{idProduct}=="0012", SYMLINK+="${callsign_lc}", MODE="0666"
EOF

    sudo udevadm control --reload-rules
    sudo udevadm trigger

    dialog --title "CM108 Setup" --msgbox "✔ CM108 rule installed.\nSymlink: /dev/${callsign_lc}\nCard: plughw:${card_num},0" 15 60
}

#==========================================================================================
# --- RUN MAIN ---
main
