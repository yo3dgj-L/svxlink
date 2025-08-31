#!/bin/bash

# --- GLOBAL ---
default_source_path=""
default_install_path=""
default_base_path=""

# --- MAIN FLOW (for readability only) ---
main() {
    get_install_path
    dialog --title "Install Path" --msgbox "Installation path detected:\n\n$default_install_path" 10 60

    copy_status_message
    update_config_txt
    update_profile
    update_ld_conf
    create_svxlink_service
    create_log_dir
    enable_svxlink_service
    check_cm108_usb || exit 1
    setup_udev_cm108
    create_svxlink_conf
    create_module_echolink_conf
    run_sa818_menu

    dialog --title "Done" --msgbox "All operations completed successfully." 8 50
    clear
    exit 0
}

#==========================================================================================
get_install_path() {
    install_file=$(sudo -n find / -type f -name "install_path.ini" 2>/dev/null | head -n1)
    if [[ -z "$install_file" ]]; then
        dialog --title "Install Path" --infobox "Could not find install_path.ini" 10 50
        sleep 3; clear; return 1
    fi

    # Parse variables from ini file
    default_source_path=$(grep '^source_path=' "$install_file" | cut -d'=' -f2-)
    default_install_path=$(grep '^install_path=' "$install_file" | cut -d'=' -f2-)
    default_base_path=$(grep '^base_path=' "$install_file" | cut -d'=' -f2-)

    # Strip trailing slashes
    default_source_path=${default_source_path%/}
    default_install_path=${default_install_path%/}
    default_base_path=${default_base_path%/}
}
#==========================================================================================

copy_status_message() {
    filepath=$(sudo -n find / -type f -name "status_message_ip.py" 2>/dev/null | grep "/svxlink/" | head -n1)
    if [[ -z "$filepath" ]]; then
        dialog --title "File Copy" --msgbox "Could not find status_message_ip.py on the system." 10 50
        clear; exit 1
    fi

    dialog --title "File Found" --msgbox "Found file:\n$filepath\n\nCopying to /usr/bin/status_message_ip.py ..." 12 60
    if sudo cp -f "$filepath" /usr/bin/status_message_ip.py; then
        dialog --title "Success" --msgbox "File copied successfully to /usr/bin/status_message_ip.py" 10 60
    else
        dialog --title "Error" --msgbox "Failed to copy the file to /usr/bin/status_message_ip.py" 10 60
        clear; exit 1
    fi
}

#==========================================================================================
update_profile() {
    get_install_path || return 1

    sudo cp /etc/profile /etc/profile.bak.$(date +%Y%m%d-%H%M%S)

    sudo sed -i "s|^  PATH=.*sbin:/bin\"|  PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$default_install_path/bin\"|" /etc/profile
    sudo sed -i "s|^  PATH=.*games\"|  PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/games:/usr/games:$default_install_path/bin\"|" /etc/profile

    new_paths=$(grep '^ *PATH=' /etc/profile | head -n2)
    dialog --title "Update Profile" --infobox "install_path set to: $default_install_path

Updated lines:
$new_paths

Backup saved as /etc/profile.bak.TIMESTAMP" 15 70
    sleep 5; clear
}

#==========================================================================================
update_ld_conf() {
    get_install_path || return 1
    conf_file="/etc/ld.so.conf.d/svxlink.libs.conf"

    if sudo grep -qx "$default_install_path/lib" "$conf_file" 2>/dev/null; then
        dialog --title "Library Path" --infobox "No changes needed.

$conf_file already contains:
$default_install_path/lib" 12 60
        sleep 3
    else
        echo "$default_install_path/lib" | sudo tee "$conf_file" >/dev/null
        dialog --title "Library Path" --infobox "Created/updated $conf_file with:

$default_install_path/lib

Now running ldconfig ..." 12 60
        sleep 3
        sudo ldconfig -v
    fi
}

#==========================================================================================
create_svxlink_service() {
    get_install_path || return 1
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

    dialog --title "Service Created" --msgbox "Service file created at:\n$service_file\n\nInstall path used:\n$default_install_path" 12 70
    sudo systemctl daemon-reload
}

#==========================================================================================
create_log_dir() {
    get_install_path || return 1
    log_dir="$default_install_path/var/log"
    log_file="$log_dir/svxlink.log"

    sudo mkdir -p "$log_dir"
    sudo touch "$log_file"
    sudo chown "$USER":"$USER" "$log_file"

    dialog --title "Log Setup" --msgbox "Created log directory and file:

Directory: $log_dir
File: $log_file" 12 60
}

#==========================================================================================
create_svxlink_conf() {
    get_install_path || return 1
    USERNAME=$(logname 2>/dev/null || echo "$USER")

    conf_file="$default_install_path/svxlink/svxlink.conf"

    CALLSIGN=$(dialog --title "SvxLink Setup" --inputbox "Enter your callsign:" 8 40 2>&1 >/dev/tty)
    [[ -z "$CALLSIGN" ]] && { dialog --title "SvxLink Setup" --msgbox "No callsign entered, aborting config." 8 50; return 1; }

    [[ -f "$conf_file" ]] && sudo cp "$conf_file" "$conf_file.bak.$(date +%Y%m%d-%H%M%S)"

    sudo tee "$conf_file" >/dev/null <<EOF
[GLOBAL]
MODULE_PATH=$default_install_path/lib/svxlink
LOGIC_CORE_PATH=$default_install_path/lib/svxlink
CFG_DIR=$default_install_path/svxlink/svxlink.d
EVENT_HANDLER=$default_install_path/share/svxlink/events.tcl
...
EOF

    dialog --title "SvxLink Config" --msgbox "? New config created at:\n$conf_file\nUsing callsign: $CALLSIGN\nBase path: $default_install_path" 15 70
}

#==========================================================================================
create_module_echolink_conf() {
    get_install_path || return 1

    echolink_conf_dir="$default_install_path/svxlink/svxlink.d"
    echolink_conf_file="$echolink_conf_dir/ModuleEchoLink.conf"
    ...
}

#==========================================================================================
run_sa818_menu() {
    get_install_path || return 1

    sa818_dir="$default_install_path/share/svxlink/SA818"
    sa818_menu_file="$sa818_dir/sa818_menu.sh"
    ...
}

#==========================================================================================
# --- RUN MAIN ---
main
