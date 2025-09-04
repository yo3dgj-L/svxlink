#!/bin/bash

# --- GLOBAL ---
default_source_path=""
default_install_path=""
default_base_path=""

# --- MAIN FLOW (for readability only) ---
main() {
             
    	dialog --title "Installer" --infobox "Detecting installation paths..." 8 50
	get_install_path
	dialog --title "Install Path" --msgbox "Installation path detected:\n\n$default_install_path" 10 60

	copy_status_message
                  copy_proxy_sounds
	update_config_txt
	update_profile
	update_ld_conf
	create_svxlink_service
	create_svxlink_conf
	create_module_echolink_conf
	create_log_dir
	fix_sa818_menu_paths


	if [[ "$skip_sa818" -eq 0 ]]; then
        	install_sa818_wrapper
        	install_sa818_shortcut
        	check_serial0_access
        	run_sa818_menu
        	check_sa818_module || exit 1
        	dialog --title "SA818 Setup" --msgbox "SA818 configured successfully.\nUse:\n  sa818 --help\n  sa818_menu" 12 60
    	else
        	dialog --title "SA818 Skipped" --msgbox "SA818 support not installed." 10 60
    	fi

    	install_cm108_udev_rule
        turn_agc_off

    	dialog --title "Done" --msgbox "All operations completed successfully system will reboot." 8 50
    	clear
	sudo reboot
    	#exit 0
}

#==========================================================================================
get_install_path() {

    dialog --title "Paths" --infobox "Looking for install_path.ini..." 10 50
    install_file=$(sudo -n find / -type f -name "install_path.ini" 2>/dev/null | head -n1)
    if [[ -z "$install_file" ]]; then
        dialog --title "Install Path" --msgbox "Could not find install_path.ini" 10 50
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
        dialog --title "File Copy" --msgbox "Could not find status_message_ip.py on the system." 10 50
        clear; exit 1
    fi

    dialog --title "File Found" --infobox "Copying status_message_ip.py to /usr/bin..." 8 50
    if sudo cp -f "$filepath" /usr/bin/status_message_ip.py; then
        dialog --title "Success" --msgbox "File copied successfully:\n/usr/bin/status_message_ip.py" 10 60
    else
        dialog --title "Error" --msgbox "Failed to copy status_message_ip.py" 10 60
        clear; exit 1
    fi

}
#==========================================================================================
update_profile() {
  

  # Resolve target bin dir; never empty
  local base="${default_install_path:-/opt/mysvxlink}"
  base="${base%/}"
  local tbin="${base}/bin"

  dialog --title "Profile Update" --infobox "Ensuring /etc/profile PATH includes: ${tbin}" 8 70

  # Backup
  local bkp="/etc/profile.bak.$(date +%Y%m%d-%H%M%S)"
  sudo cp -a /etc/profile "$bkp" || { echo "Backup failed"; return 1; }

  # Build desired lines
  local root_line='  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:'"$tbin"'"'
  local user_line='  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/games:/usr/games:'"$tbin"'"'

  # Replace the FIRST TWO lines that start with PATH="
  # (these are the root/else PATH lines in Debian-like /etc/profile)
  if ! sudo awk -v root_line="$root_line" -v user_line="$user_line" '
      BEGIN { n=0 }
      {
        if ($0 ~ /^[[:space:]]*PATH="/) {
          if (n==0) { print root_line; n++; next }
          else if (n==1) { print user_line; n++; next }
        }
        print
      }
    ' /etc/profile | sudo tee /etc/profile.tmp >/dev/null; then
      echo "Transformation failed; leaving original in place."
      return 1
  fi

  if ! sudo mv /etc/profile.tmp /etc/profile; then
    echo "Could not move new profile into place; restoring backup."
    sudo cp -a "$bkp" /etc/profile
    return 1
  fi

  # Show the result
  local new_lines
  new_lines=$(grep -n '^[[:space:]]*PATH="' /etc/profile | head -n2)
  dialog --title "Update Profile" --msgbox "Updated PATH to include:\n${tbin}\n\nNew PATH lines:\n${new_lines}\n\nBackup saved at:\n${bkp}" 16 150

  
}

#==========================================================================================
update_ld_conf() {
    
    conf_file="/etc/ld.so.conf.d/svxlink.libs.conf"
    dialog --title "Library Path" --infobox "Configuring library search path..." 8 50

    if sudo grep -qx "$default_install_path/lib" "$conf_file" 2>/dev/null; then
        dialog --title "Library Path" --msgbox "No changes needed. Already contains:\n$default_install_path/lib" 12 60
    else
        echo "$default_install_path/lib" | sudo tee "$conf_file" >/dev/null
        dialog --title "Library Path" --infobox "Running ldconfig to refresh cache..." 8 50
        # run silently, log output to trace
        sudo ldconfig -v 
# >> /var/log/svxlink-install/install_trace.log 2>&1
        dialog --title "Library Path" --msgbox "Added to ld.so.conf:\n$default_install_path/lib" 10 60
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

 }   
#==========================================================================================
create_log_dir() {

    dialog --title "Log Setup" --infobox "Creating log directory..." 8 50
    log_dir="$default_install_path/var/log"
    log_file="$log_dir/svxlink.log"

    sudo mkdir -p "$log_dir"
    sudo touch "$log_file"
    sudo chown "$USER":"$USER" "$log_file"

    dialog --title "Log Setup" --msgbox "Log directory and file created:\n$log_dir\n$log_file" 12 60

}
#==========================================================================================
create_svxlink_conf() {

    USERNAME=$(logname 2>/dev/null || echo "$USER")
    conf_file="$default_install_path/svxlink/svxlink.conf"

    # Ask for callsign
    CALLSIGN=$(dialog --title "SvxLink Setup" --inputbox "Enter your callsign:" 8 40 2>&1 >/dev/tty)
    if [[ -z "$CALLSIGN" ]]; then
        dialog --title "SvxLink Setup" --msgbox "No callsign entered, aborting config." 8 50
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

    dialog --title "SvxLink Config" --msgbox "New config created at:\n$conf_file

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

  # Ask for the rest (mask the password)
  PASSWORD=$(dialog --title "EchoLink Setup"    --inputbox "Enter your EchoLink password:" 8 50 2>&1 >/dev/tty) || return 1
  SYSOPNAME=$(dialog --title "EchoLink Setup" --inputbox "Enter your Sysop name:" 8 50 2>&1 >/dev/tty) || return 1
  QTH_INPUT=$(dialog --title "EchoLink Setup" --inputbox "Enter your location/QTH (e.g. Bucharest):" 8 50 2>&1 >/dev/tty) || return 1

  # Persist CALLSIGN globally
  export CALLSIGN

  # Build LOCATION to match your required format
  LOCATION="[Svx] 433.650 ${QTH_INPUT}"

  sudo mkdir -p "$echolink_conf_dir"

  # Backup if exists
  if [[ -f "$echolink_conf_file" ]]; then
    sudo cp "$echolink_conf_file" "$echolink_conf_file.bak.$(date +%Y%m%d-%H%M%S)"
  fi

  # Generate config EXACTLY like your "must be" example (no backslashes in DESCRIPTION)
  sudo tee "$echolink_conf_file" >/dev/null <<EOF
[ModuleEchoLink]
NAME=EchoLink
ID=2
#TIMEOUT=60
MUTE_LOGIC_LINKING=0
ALLOW_IP=192.168.0.0/24
SERVERS=servers.echolink.org
CALLSIGN=${CALLSIGN}
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
DESCRIPTION="You have connected to a SvxLink node,\\n"
            "a voice services system for Linux with EchoLink\\n"
            "support.\\n"
            "Check out http://svxlink.sf.net/ for more info\\n"
            "\\n"
            "QTH:     My_QTH\\n"
            "QRG:     Simplex link on ???.??? MHz\\n"
            "CTCSS:   My_CTCSS_fq_if_any Hz\\n"
            "Trx:     My_transceiver_type\\n"
            "Antenna: My_antenna_brand/type/model\\n"
EOF

  dialog --title "ModuleEchoLink Config" --msgbox "Created:
$echolink_conf_file

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
        dialog --title "SA818 Check" --msgbox "Failed to communicate with SA818.\n\nError:\n$OUTPUT" 15 70
        return 1
    fi

    dialog --title "SA818 Check" --msgbox "SA818 module responded:\n\n$OUTPUT" 15 70
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
        dialog --title "UART Check" --msgbox "Could not open /dev/serial0 at 9600 baud.\nCheck wiring, udev rules, or group membership." 12 60
        exit 1
    else
        dialog --title "UART Check" --msgbox "/dev/serial0 is accessible at 9600 baud.\nUART and permissions are OK." 10 60
    fi

}

#=====================================================================================================

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

    dialog --title "CM108 Setup" --msgbox "CM108 rule installed.\n\nPulseAudio will ignore the device\    /dev/${callsign_lc} symlink created\ Using card: plughw:${card_num},0" 15 60

}

#==========================================================================================
fix_sa818_menu_paths() {

    local sa818_menu_file="$default_base_path/src/svxlink/scripts/sa818/sa818_menu.sh"

    if [[ ! -f "$sa818_menu_file" ]]; then
        dialog --title "SA818 Menu Fix" --msgbox "Could not find $sa818_menu_file" 10 70
        return 1
    fi

    dialog --title "SA818 Menu Fix" --infobox "Patching sa818_menu.sh with correct paths..." 8 60
    sleep 2

    # Replace SA818_CONF and logfile lines
    sudo sed -i "s|^SA818_CONF=.*|SA818_CONF=\"$default_base_path/src/svxlink/scripts/sa818/sa818.conf\"|" "$sa818_menu_file"
    sudo sed -i "s|^logfile=.*|logfile=$default_install_path/var/log/sa818.log|" "$sa818_menu_file"

    dialog --title "SA818 Menu Fix" --msgbox "Updated sa818_menu.sh paths:\n\nSA818_CONF $default_source_path/src/svxlink/scripts/sa818/sa818.conf\nlogfile $default_install_path/var/log/sa818.log" 15 70

}
#====================================================================================================

turn_agc_off()
{
    dialog --title "Done" --msgbox "Turn OFF amixer Mute." 8 50
    sudo amixer -c 3 cset numid=7 off
         sudo alsactl store

}
#==========================================================================================
copy_proxy_sounds() {
  src="$default_base_path/src/svxlink/scripts/sounds"
  dst="$default_install_path/share/svxlink/sounds/en_US-heather-16k/Core"

dialog --title "Copy Sounds" --infobox "copy extra sound files please wait...." 8 60

  cp -f "$src/proxy_enable.wav"      "$dst/proxy_enable.wav"
  cp -f "$src/proxy_disable.wav"  "$dst/proxy_disable.wav"
  chmod 0644 "$dst/proxy_enable.wav" "$dst/proxy_disable.wav" 2>/dev/null || true

  dialog --title "Copy extra Sounds files" --msgbox \
"Copied:
  $src/proxy_enable.wav
  $src/proxy_disable.wav
to:
  $dst" 10 70
}

#=====================================================================================================



# --- RUN MAIN ---
main

