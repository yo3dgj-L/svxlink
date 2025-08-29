#!/bin/bash
clear

if dpkg -s dialog 2>/dev/null | grep -q 'Status: install ok installed'; then
     echo  "Dialog already installed"
    sleep 2
else
    echo "Installing Dialog\n\nPlease wait..." 
            sudo apt install dialog -y                 
           echo "All packages installed."
fi
sleep 1
clear
#===============================================================================================================================

if dpkg -s cmake 2>/dev/null | grep -q "Status: install ok installed"; then
    dialog --title "Preinstall Processing" --infobox "CMAKE already installed" 8 40
    sleep 2
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
} | dialog --title "Package cmake Installing" --gauge "Preparing to install..." 15 70 0

clear
echo "All packages installed."
fi

#==============================================================================================================
if dpkg -s libssl-dev 2>/dev/null | grep -q "Status: install ok installed"; then
    dialog --title "Preinstall Processing" --infobox "libssl-dev already installed" 8 40
    sleep 2
else
    packages=(
    	sudo apt-get install libssl-dev 
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
} | dialog --title "Package libssl-dev Installing" --gauge "Preparing to install..." 15 70 0

clear
echo "All packages installed."
fi
#==================================================================================================


# Check if svxlink user exists
if id "svxlink" &>/dev/null; then
    dialog --title "User Check" --yesno "User 'svxlink' already exists.\n\nDo you want to add it to the groups:\n audio, plugdev, gpio, dialout ?" 12 60
    response=$?
    if [ $response -eq 0 ]; then   # Yes
        sudo usermod -aG audio,plugdev,gpio,dialout svxlink
        dialog --title "User Updated" --msgbox "User 'svxlink' has been added to the groups." 8 50
    else   # No
        dialog --title "User Not Changed" --msgbox "No changes made to user 'svxlink'." 8 50
    fi
else
    dialog --title "User Missing" --yesno "User 'svxlink' does not exist.\n\nDo you want to create it and add it to the groups:\n audio, plugdev, gpio, dialout ?" 12 60
    response=$?
    if [ $response -eq 0 ]; then   # Yes
        sudo useradd -m -G audio,plugdev,gpio,dialout svxlink
        dialog --title "User Created" --msgbox "User 'svxlink' has been created and added to the groups." 8 50
    else   # No
        dialog --title "User Not Created" --msgbox "User 'svxlink' was not created." 8 50
        fi
fi
#======================================================================================================================
default_source_path="/opt/svxlink/src/build"
default_install_path="/opt/mysvxlink"

# First question: source path
install_path_source=$(dialog --title "Enter the path where SvxLink sources are" \
    --inputbox "Enter the path where SvxLink source/build files are:" 10 60 "$default_source_path" \
    3>&1 1>&2 2>&3 3>&-)

# If user pressed Cancel -> exit
if [ $? -ne 0 ]; then
    clear
    echo "Cancelled."
    exit 1
fi

# Second question: install path
install_path_svxlink=$(dialog --title "Enter the installation path for SvxLink" \
    --inputbox "Enter where SvxLink must be installed:" 10 60 "$default_install_path" \
    3>&1 1>&2 2>&3 3>&-)

# If user pressed Cancel -> exit
if [ $? -ne 0 ]; then
    clear
    echo "Cancelled."
    exit 1
fi
#=======================================================================================================================
# Show what the user entered
#echo "Installing to: $install_path_source"
#echo "Project name: $install_path_svxlink"

sudo mkdir -p "$default_source_path"
cd "$default_source_path"
#=============================================================================================================
dialog --title "Preinstall Processing" --infobox "Prepare svxlink Installation please wait...." 10 60  

# Run cmake in background
(
    sudo cmake -DUSE_QT=OFF \
        -DCMAKE_INSTALL_PREFIX="$default_install_path" \
        -DSYSCONF_INSTALL_DIR="$default_install_path" \
        -DLOCAL_STATE_DIR="$default_install_path/var" \
        -DWITH_SYSTEMD=ON .. > /dev/null 2>&1
) &

cmake_pid=$!

# Fake progress bar while svxlink runs
{
    percent=0
    while kill -0 $cmake_pid 2>/dev/null; do
        percent=$(( (percent + 5) % 95 ))   # cycle between 0-95%
        echo $percent
        sleep 1
    done
    echo 100
} | dialog --title "Prepare svxlink instalation" --gauge "Configuring project, please wait..." 10 60 0

#==================================================================================================
dialog --title "Preinstall Processing" --infobox "Running make -j4 please wait...." 10 60  

# Run cmake in background
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
  done | dialog --title "make -j4 in Progress" --gauge "Compiling SvxLink, please wait..." 15 70 0
)

clear
echo "Build complete!"
#===================================================================================================


dialog --title "Preinstall processing" --infobox "Running make doc please wait...." 10 60  

# Run cmake in background
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
done | dialog --title "make doc in Progress" --gauge "Building documentation, please wait..." 15 70 0
)

clear
echo "Build complete!"
#==================================================================================================

dialog --title "Preinstall Processing" --infobox "Running make install please wait...." 10 60  

# Run cmake in background
(
 	 sudo make install > /dev/null 2>&1
 
) &

cmake_pid=$!

# Fake progress bar while cmake runs
{
    percent=0
    while kill -0 $cmake_pid 2>/dev/null; do
        percent=$(( (percent + 5) % 95 ))   # cycle between 0-95%
        echo $percent
        sleep 1
    done
    echo 100
} | dialog --title "Running make install " --gauge "Configuring project, please wait..." 10 60 0









