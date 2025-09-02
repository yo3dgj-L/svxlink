#!/bin/bash

# --- GLOBAL ---
default_source_path=""
default_install_path=""
default_base_path=""

# --- MAIN FLOW (for readability only) ---
main() {
    LOG_DIR="/var/log/svxlink-install"
    sudo mkdir -p "$LOG_DIR"

    dialog --title "Installer" --infobox "🔍 Detecting installation paths..." 8 50
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
        dialog --title "SA818 Setup" --msgbox "✅ SA818 configured successfully.\nUse:\n  sa818 --help\n  sa818_menu" 12 60
    else
        dialog --title "SA818 Skipped" --msgbox "SA818 support not installed." 10 60
    fi

    install_cm108_udev_rule

    dialog --title "Done" --msgbox "All operations completed successfully." 8 50
    clear
    exit 0
}

#==========================================================================================
get_install_path() {
    dialog --title "Paths" --infobox "Looking for install_path.ini..." 8 50
    install_file=$(sudo -n find / -type f -name "install_path.ini" 2>/dev/null | head -n1)
    if [[ -z "$install_file" ]]; then
        dialog --title "Install Path" --msgbox "❌ Could not find install_path.ini" 10 50
        sleep 3; clear; return 1
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
    dialog --title "File Copy" --infobox "Searching for status_message_ip.py..." 8 50
    filepath=$(sudo -n find / -type f -name "status_message_ip.py" 2>/dev/null | grep "/svxlink/" | head -n1)
    if [[ -z "$filepath" ]]; then
        dialog --title "File Copy" --msgbox "❌ Could not find status_message_ip.py on the system." 10 50
        clear; exit 1
    fi

    dialog --title "File Found" --infobox "Copying status_message_ip.py to /usr/bin..." 8 50
    if sudo cp -f "$filepath" /usr/bin/status_message_ip.py; then
        dialog --title "Success" --msgbox "✅ File copied successfully:\n/usr/bin/status_message_ip.py" 10 60
    else
        dialog --title "Error" --msgbox "❌ Failed to copy status_message_ip.py" 10 60
        clear; exit 1
    fi
}
#==========================================================================================
update_profile() {
    dialog --title "Profile Update" --infobox "Updating /etc/profile with SvxLink paths..." 8 60
    sudo cp /etc/profile /etc/profile.bak.$(date +%Y%m%d-%H%M%S)

    sudo sed -i "s|^ PATH=.*sbin:/bin\"| PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$default_install_path/bin\"|" /etc/profile
    sudo sed -i "s|^ PATH=.*games\"| PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/games:/usr/games:$default_install_path/bin\"|" /etc/profile

    new_paths=$(grep '^ *PATH=' /etc/profile | head -n2)
    dialog --title "Update Profile" --msgbox "✅ Updated profile with:\n$default_install_path/bin\n\nNew PATH entries:\n$new_paths\n\nBackup saved in /etc/profile.bak.TIMESTAMP" 15 70
}

#==========================================================================================
update_ld_conf() {
    conf_file="/etc/ld.so.conf.d/svxlink.libs.conf"
    dialog --title "Library Path" --infobox "Configuring library search path..." 8 50

    if sudo grep -qx "$default_install_path/lib" "$conf_file" 2>/dev/null; then
        dialog --title "Library Path" --msgbox "ℹ️ No changes needed. Already contains:\n$default_install_path/lib" 12 60
    else
        echo "$default_install_path/lib" | sudo tee "$conf_file" >/dev/null
        dialog --title "Library Path" --infobox "Running ldconfig to refresh cache..." 8 50
        sudo ldconfig -v
        dialog --title "Library Path" --msgbox "✅ Added to ld.so.conf:\n$default_install_path/lib" 10 60
    fi
}
#==========================================================================================
create_svxlink_service() {
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
    sudo systemctl enable svxlink   # <--- enable autostart
    sudo systemctl start svxlink    # <--- optional: start immediately
    dialog --title "Service Enabled" -
#==========================================================================================
create_log_dir() {
    dialog --title "Log Setup" --infobox "Creating log directory..." 8 50
    log_dir="$default_install_path/var/log"
    log_file="$log_dir/svxlink.log"

    sudo mkdir -p "$log_dir"
    sudo touch "$log_file"
    sudo chown "$USER":"$USER" "$log_file"

    dialog --title "Log Setup" --msgbox "✅ Log directory and file created:\n$log_dir\n$log_file" 12 60
}
#==========================================================================================
create_svxlink_conf() {
    USERNAME=$(logname 2>/dev/null || echo "$USER")
    conf_file="$default_install_path/svxlink/svxlink.conf"

    # Ask for callsign
    CALLSIGN=$(dialog --title "SvxLink Setup" --inputbox "Enter your callsign:" 8 40 2>&1 >/dev/tty)
    if [[ -z "$CALLSIGN" ]]; then
        dialog --title "SvxLink Setup" --msgbox "⚠️ No callsign entered, aborting config." 8 50
        return 1
    fi

    # Backup if config exists
    if [[ -f "$conf_file" ]]; then
        sudo cp "$conf_file" "$conf_file.bak.$(date +%Y%m%d-%H%M%S)"
    fi

    CALLSIGN=${CALLSIGN^^}   # always uppercase

    # --- Auto-detect CM108 USB soundcard ---
    CARD_NUM=$(arecord -l | awk '/USB Audio/ {print $2}' | tr -d ':')
    if [[ -z "$CARD_NUM" ]]; then
        CARD_NUM=2   # fallback if detection fails
    fi
    RX_DEV="alsa:plughw:${CARD_NUM},0"
    TX_DEV="alsa:plughw:${CARD_NUM},0"

    # Generate fresh config
    sudo tee "$conf_file" >/dev/null <<EOF
###############################################################################
#
# Configuration file for the SvxLink server
#
###############################################################################

[GLOBAL]
MODULE_PATH=$default_install_path/lib/svxlink
LOGIC_CORE_PATH=$default_install_path/lib/svxlink
LOGICS=SimplexLogic
CFG_DIR=$default_install_path/svxlink/svxlink.d
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
EVENT_HANDLER=$default_install_path/share/svxlink/events.tcl
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
AUDIO_DEV=${RX_DEV}
AUDIO_CHANNEL=0
LIMITER_THRESH=-6
SQL_DET=HIDRAW
HID_DEVICE=/dev/$(echo "$CALLSIGN" | tr '[:upper:]' '[:lower:]')
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
AUDIO_DEV=${TX_DEV}
AUDIO_CHANNEL=0
AUDIO_DEV_KEEP_OPEN=1
LIMITER_THRESH=-6
PTT_TYPE=Hidraw
HID_DEVICE=/dev/$(echo "$CALLSIGN" | tr '[:upper:]' '[:lower:]')
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

    dialog --title "SvxLink Config" --msgbox "✅ New config created at:\n$conf_file

Using callsign: $CALLSIGN
HID_DEVICE=/dev/$USERNAME
Base path: $default_install_path" 15 70
}

#==========================================================================================
create_module_echolink_conf() {
    echolink_conf_dir="$default_install_path/svxlink/svxlink.d"
    echolink_conf_file="$echolink_conf_dir/ModuleEchoLink.conf"

    # Ask for callsign (prefill if we already have one)
    default_cs="${CALLSIGN:-}"
    CALLSIGN=$(dialog --title "EchoLink Setup" --inputbox "Enter your callsign (e.g. YO3XXX):" 8 50 "$default_cs" 2>&1 >/dev/tty) || return 1
    CALLSIGN=${CALLSIGN^^}   # uppercase it

    # Derive EchoLink callsign with -L (add if not present)
    EL_CALLSIGN="$CALLSIGN"
    [[ "$EL_CALLSIGN" != *-L ]] && EL_CALLSIGN="${EL_CALLSIGN}-L"

    # Ask for the rest
    PASSWORD=$(dialog --title "EchoLink Setup" --inputbox "Enter your EchoLink password:" 8 50 2>&1 >/dev/tty) || return 1
    SYSOPNAME=$(dialog --title "EchoLink Setup" --inputbox "Enter your Sysop name:" 8 50 2>&1 >/dev/tty) || return 1
    LOCATION=$(dialog --title "EchoLink Setup" --inputbox "Enter your location/QTH:" 8 50 2>&1 >/dev/tty) || return 1

    # Persist CALLSIGN globally
    export CALLSIGN
    sudo mkdir -p "$echolink_conf_dir"

    # Backup if exists
    if [[ -f "$echolink_conf_file" ]]; then
        sudo cp "$echolink_conf_file" "$echolink_conf_file.bak.$(date +%Y%m%d-%H%M%S)"
    fi

    # Generate config
    sudo tee "$echolink_conf_file" >/dev/null <<EOF
[ModuleEchoLink]
NAME=EchoLink
ID=2
MUTE_LOGIC_LINKING=0
ALLOW_IP=192.168.0.0/24
SERVERS=servers.echolink.org
CALLSIGN=${EL_CALLSIGN}
PASSWORD=${PASSWORD}
SYSOPNAME=${SYSOPNAME}
LOCATION=${LOCATION}
MESSAGE_SERVER_IP=192.168.150.103
MESSAGE_SERVER_PORT=9000
MAX_QSOS=10
MAX_CONNECTIONS=11
LINK_IDLE_TIMEOUT=0
DEFAULT_LANG=en_US
COMMAND_PTY=/dev/shm/echolink_ctrl
DESCRIPTION="You have connected to a SvxLink node,\n" \
"A voice services system for Linux with EchoLink\n" \
"support.\n" \
"Check out http://svxlink.sf.net/ for more info\n" \
"\n" \
"QTH: ${LOCATION}\n" \
"QRG: Simplex link on 433.650 MHz\n" \
"CTCSS: none\n" \
"Trx: CM108 based USB\n" \
"Antenna: default\n"
EOF

    dialog --title "ModuleEchoLink Config" --msgbox "✅ Created:\n$echolink_conf_file

EchoLink callsign: ${EL_CALLSIGN}
Sysop: ${SYSOPNAME}
Location: ${LOCATION}" 18 70
}

#================================================================================================================
run_sa818_menu() {
    sa818_dir="$default_base_path/src/svxlink/scripts/sa818"
    sa818_menu_file="$sa818_dir/sa818_menu.sh"

    if [[ ! -f "$sa818_menu_file" ]]; then
        dialog --title "Error" --msgbox "Could not find $sa818_menu_file" 8 60
        return 1
    fi

    # Load the script into the current shell with root privileges
    sudo bash -c "source '$sa818_menu_file'; sa818_menu"
}

#=====================================================================================================
install_sa818_wrapper() {
    sa818_py="/opt/svxlink/src/svxlink/scripts/sa818/sa818.py"
    wrapper="/usr/local/bin/sa818"

    if [[ -f "$sa818_py" ]]; then
        sudo tee "$wrapper" >/dev/null <<EOF
#!/bin/bash
exec python3 "$sa818_py" "\$@"
EOF
        sudo chmod +x "$wrapper"
    fi
}

#==========================================================================================
install_sa818_shortcut() {
    sa818_menu_file="/opt/svxlink/src/svxlink/scripts/sa818/sa818_menu.sh"
    shortcut="/usr/local/bin/sa818_menu"

    if [[ -f "$sa818_menu_file" ]]; then
        sudo tee "$shortcut" >/dev/null <<EOF
#!/bin/bash
# Load the script so the function is defined
source "$sa818_menu_file"
# Now call the function explicitly
sa818_menu "\$@"
EOF
        sudo chmod +x "$shortcut"
    fi
}

#==========================================================================================
check_sa818_module() {
    dialog --title "SA818 Check" --infobox "Testing SA818 module via /dev/serial0 @ 9600 baud..." 8 60
    sleep 2

    OUTPUT=$(sa818 --port /dev/serial0 --speed 9600 version 2>&1)
    RC=$?

    if [[ $RC -ne 0 ]]; then
        dialog --title "SA818 Check" --msgbox "⚠️ Failed to communicate with SA818.\n\nError:\n$OUTPUT" 15 70
        return 1
    fi

    dialog --title "SA818 Check" --msgbox "✅ SA818 module responded:\n\n$OUTPUT" 15 70
    return 0
}

#=====================================================================================================
check_serial0_access() {
    dialog --title "UART Check" --infobox "Verifying that /dev/serial0 is accessible..." 8 50
    sleep 1

    python3 - <<'EOF'
import serial, sys
try:
    ser = serial.Serial("/dev/serial0", 9600, timeout=1)
    print("OK: /dev/serial0 opened successfully at 9600 baud")
    ser.close()
except Exception as e:
    print("ERROR: Could not open /dev/serial0:", e)
    sys.exit(1)
EOF

    if [[ $? -ne 0 ]]; then
        dialog --title "UART Check" --msgbox "⚠️ Could not open /dev/serial0 at 9600 baud.\nCheck wiring, udev rules, or group membership." 12 60
        exit 1
    else
        dialog --title "UART Check" --msgbox "✅ /dev/serial0 is accessible at 9600 baud.\nUART and permissions are OK." 10 60
    fi
}

#=====================================================================================================
run_with_log() {
    local func="$1"
    shift
    local logfile="$LOG_DIR/${func}.log"

    echo "=== Running $func at $(date) ===" | sudo tee "$logfile" >/dev/null
    $func "$@" >> >(sudo tee -a "$logfile") 2>&1
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        dialog --title "Error" --msgbox "⚠️ $func failed.\n\nSee log:\n$logfile" 12 60
        exit $rc
    else
        echo "=== $func completed OK at $(date) ===" | sudo tee -a "$logfile" >/dev/null
    fi
}

#==========================================================================================
install_cm108_udev_rule() {
    dialog --title "CM108 Setup" --infobox "Configuring CM108 USB soundcard...\n\nPlease wait..." 10 60
    sleep 2

    # Ensure callsign is available, force lowercase for device name
    local callsign_lc
    callsign_lc=$(echo "${CALLSIGN:-svxlink}" | tr '[:upper:]' '[:lower:]')

    # --- Detect CM108 ALSA card index ---
    local card_num
    card_num=$(aplay -l | grep -i 'USB Audio' | grep -i 'C-Media' | awk -F'[: ]+' '{print $2}' | head -n1)

    if [[ -n "$card_num" ]]; then
        RX_DEV="alsa:plughw:${card_num},0"
        TX_DEV="alsa:plughw:${card_num},0"
    else
        RX_DEV="alsa:plughw:0,0"
        TX_DEV="alsa:plughw:0,0"
    fi

    # --- Save udev rule ---
    cat <<EOF | sudo tee /etc/udev/rules.d/99-cm108.rules >/dev/null
# Block PulseAudio using CM108 USB soundcard for SvxLink
ATTRS{idVendor}=="0d8c", ATTRS{idProduct}=="0012", ENV{PULSE_IGNORE}="1"

# Stable symlink for HID GPIO device
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0d8c", ATTRS{idProduct}=="0012", SYMLINK+="${callsign_lc}", MODE="0666"
EOF

    sudo udevadm control --reload-rules
    sudo udevadm trigger

    dialog --title "CM108 Setup" --msgbox "✅ CM108 rule installed.\n\n• PulseAudio will ignore the device\n• /dev/${callsign_lc} symlink created\n• Using card: plughw:${card_num},0" 15 60
}

#==========================================================================================
# --- RUN MAIN ---
main

