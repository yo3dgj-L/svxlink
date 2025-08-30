#!/bin/bash

# --- GLOBAL ---
install_path=""

# --- MAIN FLOW (for readability only) ---
main() {
    get_install_path
    dialog --title "Install Path" --msgbox "Installation path detected:\n\n$install_path" 10 60

    #copy_status_message
    #update_config_txt
    #update_profile
    #update_ld_conf
         #create_svxlink_service
         #create_log_dir
         #enable_svxlink_service
         #check_cm108_usb || exit 1
         #setup_udev_cm108
         #create_svxlink_conf
         #create_module_echolink_conf
                    run_sa818_menu


          #dialog --title "Service" --msgbox "Enable the svxlink service." 8 50
          #sudo systemctl enable svxlink.service


    dialog --title "Done" --msgbox "All operations completed successfully." 8 50
    clear
    exit 0
}
#==========================================================================================

get_install_path() {
    install_file=$(sudo -n find / -type f -name "install_path.txt" 2>/dev/null | head -n1)
    if [[ -z "$install_file" ]]; then
        dialog --title "Install Path" --infobox "Could not find install_path.txt" 10 50
        sleep 3; clear; return 1
    fi

    install_path=$(head -n1 "$install_file")
    install_path=${install_path%/}   # strip trailing slash
}
#=================================================================================================================

copy_status_message() {
# Find the file and store in variable (take first match only)
filepath=$(sudo -n find / -type f -name "status_message_ip.py" 2>/dev/null | grep "/svxlink/" | head -n1)

# Check if we found a file
if [[ -z "$filepath" ]]; then
    dialog --title "File Copy" --msgbox "Could not find status_message_ip.py on the system." 10 50
    clear
    exit 1
fi

# Show user what we found
dialog --title "File Found" --msgbox "Found file:\n$filepath\n\nCopying to /usr/bin/status_message_ip.py ..." 12 60

# Copy to /usr/bin with hardcoded filename, force overwrite
if sudo cp -f "$filepath" /usr/bin/status_message_ip.py; then
    dialog --title "Success" --msgbox "File copied successfully to /usr/bin/status_message_ip.py" 10 60
else
    dialog --title "Error" --msgbox "Failed to copy the file to /usr/bin/status_message_ip.py" 10 60
    clear
    exit 1
fi
}
#==========================================================================================================
update_profile() {
    get_install_path || return 1

    # Backup with timestamp
    sudo cp /etc/profile /etc/profile.bak.$(date +%Y%m%d-%H%M%S)

    # Normalize both PATH lines safely
    sudo sed -i "s|^  PATH=.*sbin:/bin\"|  PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$install_path/bin\"|" /etc/profile
    sudo sed -i "s|^  PATH=.*games\"|  PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/games:/usr/games:$install_path/bin\"|" /etc/profile

    # Show result
    new_paths=$(grep '^ *PATH=' /etc/profile | head -n2)
    dialog --title "Update Profile" --infobox "install_path set to: $install_path

Updated lines:
$new_paths

Backup saved as /etc/profile.bak.TIMESTAMP" 15 70
    sleep 5; clear
}
#======================================================================================================================================
update_profile() {
    install_file=$(sudo -n find / -type f -name "install_path.txt" 2>/dev/null | head -n1)
    if [[ -z "$install_file" ]]; then
        dialog --title "Update Profile" --infobox "Could not find install_path.txt" 10 50
        sleep 3; clear; return 1
    fi

    install_path=$(head -n1 "$install_file")
    install_path=${install_path%/}   # strip trailing slash

    # Backup
    sudo cp /etc/profile /etc/profile.bak.$(date +%Y%m%d-%H%M%S)

    # Normalize both PATH lines safely
    sudo sed -i "s|^  PATH=.*sbin:/bin\"|  PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$install_path/bin\"|" /etc/profile
    sudo sed -i "s|^  PATH=.*games\"|  PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/games:/usr/games:$install_path/bin\"|" /etc/profile

    # Show result
    new_paths=$(grep '^ *PATH=' /etc/profile | head -n2)
    dialog --title "Update Profile" --infobox "install_path set to: $install_path

Updated lines:
$new_paths

Backup saved as /etc/profile.bak" 15 70
    sleep 5; clear
}
#================================================================================================================

update_ld_conf() {
    get_install_path || return 1

    conf_file="/etc/ld.so.conf.d/svxlink.libs.conf"

    # If the file already contains the correct path, do nothing
    if sudo grep -qx "$install_path/lib" "$conf_file" 2>/dev/null; then
        dialog --title "Library Path" --infobox "No changes needed.

$conf_file already contains:
$install_path/lib" 12 60
        sleep 3
    else
        # Write the line (overwrite if file exists but wrong content)
        echo "$install_path/lib" | sudo tee "$conf_file" >/dev/null

        dialog --title "Library Path" --infobox "Created/updated $conf_file with:

$install_path/lib

Now running ldconfig ..." 12 60
        sleep 3

        sudo ldconfig -v
    fi
}
#================================================================================================================

create_svxlink_service() {
    get_install_path || return 1

    service_file="/lib/systemd/system/svxlink.service"

    sudo tee "$service_file" >/dev/null <<EOF
[Unit]
Description=SvxLink
After=network.target

[Service]
EnvironmentFile=$install_path/default/svxlink
PIDFile=\${PIDFILE}
ExecStartPre=-/bin/touch \${LOGFILE}
ExecStartPre=-/bin/chown \${RUNASUSER} \${LOGFILE}
ExecStart=$install_path/bin/svxlink --logfile=\${LOGFILE} --config=\${CFGFILE} --pidfile=\${PIDFILE} --runasuser=\${RUNASUSER}
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=on-failure
TimeoutStartSec=60
TimeoutStopSec=10
#WatchdogSec=
#NotifyAccess=main
LimitCORE=infinity
WorkingDirectory=$install_path/svxlink

[Install]
WantedBy=multi-user.target
EOF

    dialog --title "Service Created" --msgbox "Service file created at:\n$service_file\n\nInstall path used:\n$install_path" 12 70

    # Reload systemd to apply the new service file
    sudo systemctl daemon-reload
}
#================================================================================================================

create_log_dir() {
    get_install_path || return 1

    log_dir="$install_path/var/log"
    log_file="$log_dir/svxlink.log"

    # Create the directory (if not exists)
    sudo mkdir -p "$log_dir"

    # Create an empty log file
    sudo touch "$log_file"

    # Set proper ownership (adjust to svxlink runtime user if needed)
    sudo chown "$USER":"$USER" "$log_file"

    dialog --title "Log Setup" --msgbox "Created log directory and file:

Directory: $log_dir
File: $log_file" 12 60
}
#=================================================================================================================

enable_svxlink_service() {
    if sudo systemctl enable svxlink.service >/dev/null 2>&1; then
        dialog --title "Service Enable" --msgbox "? svxlink.service has been enabled successfully.\n\nIt will now start automatically at boot." 10 60
    else
        dialog --title "Service Enable" --msgbox "? Failed to enable svxlink.service.\n\nPlease check the service file or logs." 10 60
    fi
}
#====================================================================================================
get_install_path() {
    install_file=$(sudo -n find / -type f -name "install_path.txt" 2>/dev/null | head -n1)
    if [[ -z "$install_file" ]]; then
        dialog --title "Install Path" --infobox "Could not find install_path.txt" 10 50
        sleep 3; clear; return 1
    fi

    install_path=$(head -n1 "$install_file")
    install_path=${install_path%/}   # strip trailing slash
}

#=================================================================================================================

check_cm108_usb() {
    # Look for C-Media device with lsusb
    if lsusb | grep -qi "C-Media"; then
        device_line=$(lsusb | grep -i "C-Media")
        dialog --title "CM108 USB Check" --msgbox "? CM108 USB audio device detected:\n\n$device_line" 12 70
    else
        dialog --title "CM108 USB Check" --msgbox "? No CM108 USB audio device found.\n\nPlease check the connection and try again." 12 70
        return 1
    fi

    # Show also what ALSA sees
    alsa_cards=$(cat /proc/asound/cards 2>/dev/null || echo "No ALSA devices found")
    dialog --title "ALSA Devices" --msgbox "ALSA reported devices:\n\n$alsa_cards" 15 70
}

#=================================================================================================================

setup_udev_cm108() {
    # VendorID and ProductID for CM108
    VID="0d8c"
    PID="000c"
    udev_file="/etc/udev/rules.d/55-cm108.rules"

    # Get the current logged-in user
    USERNAME=$(logname 2>/dev/null || echo "$USER")

    # Write the rule
    sudo tee "$udev_file" >/dev/null <<EOF
# Udev rules for CM108 USB adapter
ATTRS{idVendor}=="$VID", ATTRS{idProduct}=="$PID", ENV{PULSE_IGNORE}="1"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="$VID", ATTRS{idProduct}=="$PID", SYMLINK+="$USERNAME", MODE="0666"
EOF

    # Reload rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger

    # Verify
    if [ -e "/dev/$USERNAME" ]; then
        dialog --title "udev Setup" --msgbox "? udev rule created:\n$udev_file\n\nSymlink /dev/$USERNAME is now available." 12 70
    else
        dialog --title "udev Setup" --msgbox "?? udev rule created but /dev/$USERNAME not found yet.\n\nTry replugging the CM108 device." 12 70
    fi
}
#=================================================================================================================

create_svxlink_conf() {
    get_install_path || return 1
    USERNAME=$(logname 2>/dev/null || echo "$USER")

    conf_file="$install_path/svxlink/svxlink.conf"

    # Ask for callsign
    CALLSIGN=$(dialog --title "SvxLink Setup" --inputbox "Enter your callsign:" 8 40 2>&1 >/dev/tty)
    if [[ -z "$CALLSIGN" ]]; then
        dialog --title "SvxLink Setup" --msgbox "? No callsign entered, aborting config." 8 50
        return 1
    fi

    # Backup if config exists
    if [[ -f "$conf_file" ]]; then
        sudo cp "$conf_file" "$conf_file.bak.$(date +%Y%m%d-%H%M%S)"
    fi

    # Generate fresh config
    sudo tee "$conf_file" >/dev/null <<EOF
###############################################################################
#                                                                             #
#                Configuration file for the SvxLink server                    #
#                                                                             #
###############################################################################

[GLOBAL]
MODULE_PATH=$install_path/lib/svxlink
LOGIC_CORE_PATH=$install_path/lib/svxlink
LOGICS=SimplexLogic
CFG_DIR=$install_path/svxlink/svxlink.d
TIMESTAMP_FORMAT="%Y-%m-%d %H:%M:%S"
CARD_SAMPLE_RATE=48000
CARD_CHANNELS=1
LOCATION_INFO=LocationInfo

[SimplexLogic]
TYPE=Simplex
RX=Rx1
TX=Tx1
MODULES=ModuleHelp,ModuleParrot,ModuleEchoLink
CALLSIGN=$CALLSIGN
SHORT_IDENT_INTERVAL=15
LONG_IDENT_INTERVAL=60
EVENT_HANDLER=$install_path/share/svxlink/events.tcl
DEFAULT_LANG=en_US
RGR_SOUND_DELAY=0
MACROS=Macros
FX_GAIN_NORMAL=0
FX_GAIN_LOW=-12
DTMF_PTY=/tmp/svxlink_dtmf
DTMF_CTRL_PTY=/tmp/svxlink_dtmf

[Macros]
1=EchoLink:766633#
2=EchoLink:359422#
8=EchoLink:54452#
9=EchoLink:9999#

[Rx1]
TYPE=Local
AUDIO_DEV=alsa:plughw:0,0
AUDIO_CHANNEL=0
LIMITER_THRESH=-6
SQL_DET=HIDRAW
HID_DEVICE=/dev/$USERNAME
HID_SQL_PIN=VOL_DN
SIGLEV_SLOPE=1
SIGLEV_OFFSET=0
SQL_SIGLEV_OPEN_THRESH=30
SQL_SIGLEV_CLOSE_THRESH=10
DEEMPHASIS=0
PEAK_METER=0
DTMF_DEC_TYPE=INTERNAL
DTMF_DETECTION=1
DTMF_MUTING=1
DTMF_HANGTIME=40

[Tx1]
TYPE=Local
TX_ID=T
AUDIO_DEV=alsa:plughw:0,0
AUDIO_CHANNEL=0
AUDIO_DEV_KEEP_OPEN=1
LIMITER_THRESH=-6
PTT_TYPE=Hidraw
HID_DEVICE=/dev/$USERNAME
HID_PTT_PIN=GPIO3
TX_DELAY=1000
DTMF_TONE_LENGTH=100
DTMF_TONE_SPACING=50
DTMF_DIGIT_PWR=-15
MASTER_GAIN=0
PEAK_METER=1
PREEMPHASIS=0

[LocationInfo]
APRS_SERVER_LIST=euro.aprs2.net:14580
STATUS_SERVER_LIST=aprs.echolink.org:5199
LON_POSITION=26.09.27E
LAT_POSITION=44.26.40N
CALLSIGN=EL-$CALLSIGN
LOGIN_CALLSIGN=$CALLSIGN
FREQUENCY=433.650
TX_POWER=8
ANTENNA_GAIN=6
ANTENNA_HEIGHT=20m
ANTENNA_DIR=-1
PATH=WIDE1-1
BEACON_INTERVAL=10
SYMBOL="/-"
COMMENT=SvxLink Node - $CALLSIGN
EOF

    dialog --title "SvxLink Config" --msgbox "? New config created at:\n$conf_file\n\nUsing callsign: $CALLSIGN\nHID_DEVICE=/dev/$USERNAME\nBase path: $install_path" 15 70
}
#=================================================================================================================

create_module_echolink_conf() {
    get_install_path || return 1

    echolink_conf_dir="$install_path/svxlink/svxlink.d"
    echolink_conf_file="$echolink_conf_dir/ModuleEchoLink.conf"

    # Ask for callsign (prefill if we already have one)
    default_cs="${CALLSIGN:-}"
    CALLSIGN=$(dialog --title "EchoLink Setup" --inputbox "Enter your callsign (e.g. YO3XXX):" 8 50 "$default_cs" 2>&1 >/dev/tty) || return 1
    CALLSIGN=${CALLSIGN^^}          # uppercase it

    # Derive EchoLink callsign with -L (add if not present)
    EL_CALLSIGN="$CALLSIGN"
    [[ "$EL_CALLSIGN" != *-L ]] && EL_CALLSIGN="${EL_CALLSIGN}-L"

    # Ask for the rest
    PASSWORD=$(dialog --title "EchoLink Setup" --inputbox "Enter your EchoLink password:" 8 50 2>&1 >/dev/tty) || return 1
    SYSOPNAME=$(dialog --title "EchoLink Setup" --inputbox "Enter your Sysop name:" 8 50 2>&1 >/dev/tty) || return 1
    LOCATION=$(dialog --title "EchoLink Setup" --inputbox "Enter your location/QTH:" 8 50 2>&1 >/dev/tty) || return 1

    # Persist CALLSIGN globally for later steps
    export CALLSIGN

    sudo mkdir -p "$echolink_conf_dir"
    if [[ -f "$echolink_conf_file" ]]; then
        sudo cp "$echolink_conf_file" "$echolink_conf_file.bak.$(date +%Y%m%d-%H%M%S)"
    fi

    sudo tee "$echolink_conf_file" >/dev/null <<EOF
[ModuleEchoLink]
NAME=EchoLink
ID=2
#TIMEOUT=60
MUTE_LOGIC_LINKING=0
ALLOW_IP=192.168.0.0/24
#DROP_ALL_INCOMING=0
#DROP_INCOMING=^()$
#REJECT_INCOMING=^()$
#ACCEPT_INCOMING=^(.*)$
#REJECT_OUTGOING=^()$
#ACCEPT_OUTGOING=^(.*)$
#REJECT_CONF=0
#CHECK_NR_CONNECTS=2,300,120
SERVERS=servers.echolink.org
CALLSIGN=${EL_CALLSIGN}
PASSWORD=${PASSWORD}
SYSOPNAME=${SYSOPNAME}
LOCATION=${LOCATION}

MESSAGE_SERVER_IP=192.168.150.103
MESSAGE_SERVER_PORT=9000

#PROXY_SERVER=137.226.114.148
#PROXY_PORT=8100
#PROXY_PASSWORD=PUBLIC

#BIND_ADDR=192.168.1.100
MAX_QSOS=10
MAX_CONNECTIONS=11
LINK_IDLE_TIMEOUT=0
#AUTOCON_ECHOLINK_ID=9999
#AUTOCON_TIME=1200
#USE_GSM_ONLY=1
DEFAULT_LANG=en_US
COMMAND_PTY=/dev/shm/echolink_ctrl
#LOCAL_RGR_SOUND=1
#REMOTE_RGR_SOUND=0
DESCRIPTION="You have connected to a SvxLink node,\n"
            "a voice services system for Linux with EchoLink\n"
            "support.\n"
            "Check out http://svxlink.sf.net/ for more info\n"
            "\n"
            "QTH:     ${LOCATION}\n"
            "QRG:     Simplex link on 433.650 MHz\n"
            "CTCSS:   none\n"
            "Trx:     CM108 based USB\n"
            "Antenna: default\n"
EOF

    dialog --title "ModuleEchoLink Config" --msgbox "? Created:\n$echolink_conf_file

EchoLink callsign: ${EL_CALLSIGN}
Sysop: ${SYSOPNAME}
Location: ${LOCATION}" 18 70
}
#===============================================================================================================================

run_sa818_menu() {
    get_install_path || return 1

    sa818_dir="$install_path/share/svxlink/SA818"
    sa818_menu_file="$sa818_dir/sa818_menu.sh"

    if [[ ! -f "$sa818_menu_file" ]]; then
        dialog --title "SA818 Menu" --msgbox "sa818_menu.sh not found at:\n$sa818_menu_file" 10 60
        return 1
    fi

    # Source it so the sa818_menu() function becomes available
    source "$sa818_menu_file"

    # Call the function
    sa818_menu

    dialog --title "SA818 Menu" --msgbox "Returned from SA818 configuration menu." 8 50
}


#=================================================================================================================
# --- RUN MAIN ---
main
