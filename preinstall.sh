!/bin/bash
#package=$1
clear

if [ -n "$(dpkg -s dialog 2>/dev/null | grep 'Status: install ok installed')" ]; then
    echo "Status installed."
else
    echo "Installing Dailog."
           sudo apt install dialog -y
fi


if [ -n "$(dpkg -s cmake 2>/dev/null | grep 'Status: install ok installed')" ]; then
    dialog --title "Preinstall Processing" --infobox "\
        CMAKE allready installed" 8 40	
else
    dialog --title "Preinstall Processing" --infobox "Installing CMAKE\n\nPlease wait...\nCMAKE install in progress." 8 40           
                    
    sudo apt install -y g++ cmake make libsigc++-2.0-dev libgsm1-dev libpopt-dev tcl8.6-dev libgcrypt20-dev libspeex-dev libasound2-dev libopus-dev librtlsdr-dev doxygen groff alsa-utils vorbis-tools curl libcurl4-openssl-dev git rtl-sdr libcurl4-openssl-dev cmake libjsoncpp-dev ladspa-sdk libogg0 libogg-dev libgpiod-dev > /dev/null 2>&1
           sudo apt-get install libssl-dev > /dev/null 2>&1

    dialog --title "Preinstall Processing" --infobox "Install CMAKE finisht." 8 40  
          clear
fi
dialog --title "Preinstall Processing" --infobox "Add user svxlink to the following groups\n\ audio,plugdev,gpio,dialout." 8 60   
sudo useradd -rG audio,plugdev,gpio,dialout svxlink

default_source_path="/home/$(whoami)"
default_install_path="/opt/mysvxlink"

# First question: installation path
install_path_source=$(dialog --title "Enter The Path where the SvxLink instalation files are" \
    --inputbox "Enter the path Where SvxLink Install files are:" 10 60 "$default_source_path" \ \
    3>&1 1>&2 2>&3 3>&-)

# If user pressed Cancel -> exit
[ $? -ne 0 ] && { clear; echo "Cancelled."; exit 1; }

# Second question: project name
install_path_svxlink=$(dialog --title "Enter the instalation path for SvxLink" \
    --inputbox "Enter where SvxLink must be installed:" 10 60 "$default_install_path" \
    3>&1 1>&2 2>&3 3>&-)

# If user pressed Cancel -> exit
[ $? -ne 0 ] && { clear; echo "Cancelled."; exit 1; }

# Clear dialog remnants
clear

# Show what the user entered
#echo "Installing to: $install_path_source"
#echo "Project name: $install_path_svxlink"

dialog --title "Preinstall Processing" --infobox "Installing svxlink please wait...." 10 60  

cd /$default_source_path

# Example: use both variables in cmake
sudo cmake -DUSE_QT=OFF \
    -DCMAKE_INSTALL_PREFIX="$default_install_path" \
    -DSYSCONF_INSTALL_DIR="$default_install_path" \
    -DLOCAL_STATE_DIR="$default_install_path/var" \
    -DWITH_SYSTEMD=ON \
         -DCPACK_GENERATOR=DEB ..  > /dev/null 2>&1
         
           sudo make doc > /dev/null 2>&1
           sudo make install > /dev/null 2>&1
    
          sudo dpkg -i svxlink-25.05.1-Linux.deb  > /dev/null 2>&1


dialog --title "Preinstall Processing" --infobox "Install svxlink finisht." 10 60  
         sleep 2
	  clear

