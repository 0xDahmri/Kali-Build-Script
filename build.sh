#!/bin/bash

# Note: Run from home directory. Do not use sudo to execute this script.
# If you use sudo the permissions for all the created folders will be wrong!  You've been warned!

#████████╗███████╗██████╗ ███╗   ███╗██╗███╗   ██╗ █████╗ ██╗             ██╗    ██╗      ██████╗  ██████╗  ██████╗ ██╗███╗   ██╗ ██████╗ 
#╚══██╔══╝██╔════╝██╔══██╗████╗ ████║██║████╗  ██║██╔══██╗██║            ██╔╝    ██║     ██╔═══██╗██╔════╝ ██╔════╝ ██║████╗  ██║██╔════╝ 
#   ██║   █████╗  ██████╔╝██╔████╔██║██║██╔██╗ ██║███████║██║           ██╔╝     ██║     ██║   ██║██║  ███╗██║  ███╗██║██╔██╗ ██║██║  ███╗
#   ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║██║██║╚██╗██║██╔══██║██║          ██╔╝      ██║     ██║   ██║██║   ██║██║   ██║██║██║╚██╗██║██║   ██║
#   ██║   ███████╗██║  ██║██║ ╚═╝ ██║██║██║ ╚████║██║  ██║███████╗    ██╔╝       ███████╗╚██████╔╝╚██████╔╝╚██████╔╝██║██║ ╚████║╚██████╔╝
#   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝    ╚═╝        ╚══════╝ ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝ 
#                                                                                                                                         

# === Colors for Log Output ===
ERROR="\e[1;31m"
SUCCESS="\e[1;32m"
ENDCOLOR="\e[0m"

# === Log File Setup ===
# The goal here is to have a full set of logs for attribution and/or troubleshooting purposes.  A relic from being on a DoD red team, but a good mindset to have.
LOG_FILE="$HOME/build_log.txt"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[*] Build started at $(date)"

# === Locale & Font Fix ===
# Do not change.  Resolves an issue I've had with Kali 2024.1+
# Removing this CAN cause your fonts to get deleted.
function fix_locales_and_fonts {
    echo "[*] Setting UTF-8 locale and installing fallback fonts..."
    sudo apt install -y locales fontconfig fonts-dejavu-core fonts-liberation fonts-noto-color-emoji >/dev/null 2>&1
    sudo sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    sudo locale-gen >/dev/null 2>&1
    sudo update-locale LANG=en_US.UTF-8
    echo "[+] Locale and fonts configured."
}

# === Fix Kali GPG Key with modern trusted keyring method ===
# Do not change.  Resolves an issue I've had with Kali 2024.1+
function fix_kali_gpg_key {
    echo "[*] Setting up Kali GPG key via trusted.gpg.d..."
    curl -fsSL https://archive.kali.org/archive-key.asc | gpg --dearmor | sudo tee /usr/share/keyrings/kali-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/kali-archive-keyring.gpg] http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware" | sudo tee /etc/apt/sources.list
    echo -e "${SUCCESS}[+]${ENDCOLOR} Kali GPG key set up using modern method"
}

# === OS Update ===
function update_os {
    echo "[*] Updating OS..."
    if sudo apt update -y >/dev/null 2>&1 && \
       sudo apt full-upgrade -y >/dev/null 2>&1 && \
       sudo apt autoremove -y >/dev/null 2>&1; then
        echo "[+] OS updated successfully."
    else
        echo "[!] OS update failed."
    fi
}

#██████╗ ███████╗██████╗ ███████╗███╗   ██╗██████╗ ███████╗███╗   ██╗ ██████╗██╗███████╗███████╗        ██╗    ██╗      █████╗ ███╗   ██╗ ██████╗ ██╗   ██╗ █████╗  ██████╗ ███████╗███████╗
#██╔══██╗██╔════╝██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝████╗  ██║██╔════╝██║██╔════╝██╔════╝       ██╔╝    ██║     ██╔══██╗████╗  ██║██╔════╝ ██║   ██║██╔══██╗██╔════╝ ██╔════╝██╔════╝
#██║  ██║█████╗  ██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██╔██╗ ██║██║     ██║█████╗  ███████╗      ██╔╝     ██║     ███████║██╔██╗ ██║██║  ███╗██║   ██║███████║██║  ███╗█████╗  ███████╗
#██║  ██║██╔══╝  ██╔═══╝ ██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██║╚██╗██║██║     ██║██╔══╝  ╚════██║     ██╔╝      ██║     ██╔══██║██║╚██╗██║██║   ██║██║   ██║██╔══██║██║   ██║██╔══╝  ╚════██║
#██████╔╝███████╗██║     ███████╗██║ ╚████║██████╔╝███████╗██║ ╚████║╚██████╗██║███████╗███████║    ██╔╝       ███████╗██║  ██║██║ ╚████║╚██████╔╝╚██████╔╝██║  ██║╚██████╔╝███████╗███████║
#╚═════╝ ╚══════╝╚═╝     ╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚═╝╚══════╝╚══════╝    ╚═╝        ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝
#
                                                                                                                                                                                           
# === Wordlists ===
# Note: I think Seclists comes standard now.  May flag for removal.
function update_wordlists {
    echo "[*] Cloning SecLists..."
    (sudo git clone https://github.com/danielmiessler/SecLists.git /usr/share/seclists &&
     sudo ln -s /usr/share/seclists /usr/share/wordlists/seclists &&
     echo -e "${SUCCESS}[+]${ENDCOLOR} Wordlists installed") || echo -e "${ERROR}[-]${ENDCOLOR} Wordlist installation failed"
}

# === Golang ===
function install_golang {
    echo "[*] Installing Golang..."
    (sudo DEBIAN_FRONTEND=noninteractive apt install golang-go -y &&
     echo -e "${SUCCESS}[+]${ENDCOLOR} Golang installed") || echo -e "${ERROR}[-]${ENDCOLOR} Golang installation failed"
}

# === Firefox Setup with FoxyProxy ===
function configure_firefox {
    echo "[*] Installing Firefox + FoxyProxy Standard..."
    if sudo apt install -y firefox-esr >/dev/null 2>&1; then
        firefox --headless & sleep 5 && killall firefox
        profile=$(find ~/.mozilla/firefox -name "*.default-esr" | head -n 1)
        if [[ -n "$profile" ]]; then
            mkdir -p "$profile"/extensions
            wget -q -O "$profile"/extensions/foxyproxy@eric.h.jung.xpi \
                https://addons.mozilla.org/firefox/downloads/latest/foxyproxy-standard/addon-2464-latest.xpi
            echo "[+] FoxyProxy Standard installed into Firefox."
        else
            echo "[!] Firefox profile not found."
        fi
    else
        echo "[!] Failed to install Firefox."
    fi
}

#████████╗ ██████╗  ██████╗ ██╗     ███████╗
#╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝
#   ██║   ██║   ██║██║   ██║██║     ███████╗
#   ██║   ██║   ██║██║   ██║██║     ╚════██║
#   ██║   ╚██████╔╝╚██████╔╝███████╗███████║
#   ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝
#                                           

# === Ncat ===
function install_ncat {
    echo "[*] Installing Ncat via Nmap..."
    (sudo DEBIAN_FRONTEND=noninteractive apt install nmap -y &&
     echo -e "${SUCCESS}[+]${ENDCOLOR} Ncat installed") || echo -e "${ERROR}[-]${ENDCOLOR} Ncat installation failed"
}

# === ProjectDiscovery Tools ===
function install_projectdiscovery_tools {
    echo "[*] Installing ProjectDiscovery pdtm..."
    mkdir -p ~/Tools/projectdiscovery && cd ~/Tools/projectdiscovery || return
    if curl -s https://api.github.com/repos/projectdiscovery/pdtm/releases/latest \
        | grep browser_download_url | grep linux_amd64.zip | cut -d '"' -f 4 \
        | wget -qi - -O pdtm.zip >/dev/null 2>&1 && \
       unzip -o pdtm.zip >/dev/null 2>&1 && \
       chmod +x pdtm && sudo mv pdtm /usr/local/bin/pdtm && \
       pdtm -install-all >/dev/null 2>&1; then
        echo "[+] ProjectDiscovery tools installed."
    else
        echo "[!] Failed to install ProjectDiscovery tools."
    fi
}

# === GoWitness Screenshot Tool ===
function install_gowitness {
    echo "[*] Installing GoWitness..."
    mkdir -p ~/Tools/gowitness && cd ~/Tools/gowitness || return
    if curl -s https://api.github.com/repos/sensepost/gowitness/releases/latest \
        | grep browser_download_url | grep linux-amd64 | cut -d '"' -f 4 \
        | wget -qi - -O gowitness >/dev/null 2>&1 && \
       chmod +x gowitness && sudo mv gowitness /usr/local/bin/gowitness; then
        echo "[+] GoWitness installed."
    else
        echo "[!] Failed to install GoWitness."
    fi
}

# === Install massdns ===
function install_massdns {
    echo "[*] Installing massdns..."
    mkdir -p ~/Tools && cd ~/Tools || return
    rm -rf massdns
    if git clone https://github.com/blechschmidt/massdns.git >/dev/null 2>&1 && \
       cd massdns && make >/dev/null 2>&1; then
        echo "[+] massdns installed."
    else
        echo "[!] Failed to install massdns."
    fi
}

# === Install kerbrute ===
function install_kerbrute {
    echo "[*] Installing kerbrute..."
    mkdir -p ~/Tools/kerbrute && cd ~/Tools/kerbrute || return
    if curl -s https://api.github.com/repos/ropnop/kerbrute/releases/latest \
        | grep browser_download_url | grep linux_amd64 | cut -d '"' -f 4 \
        | wget -qi - -O kerbrute >/dev/null 2>&1 && \
       chmod +x kerbrute && sudo mv kerbrute /usr/local/bin/kerbrute; then
        echo "[+] kerbrute installed."
    else
        echo "[!] Failed to install kerbrute."
    fi
}

# === Sliver C2 Framework ===
function install_sliver {
    echo "[*] Installing Sliver C2..."
    sudo apt install -y build-essential golang make git >/dev/null 2>&1
    rm -rf ~/Tools/sliver
    mkdir -p ~/Tools && cd ~/Tools || return

    if git clone https://github.com/BishopFox/sliver.git >/dev/null 2>&1; then
        cd ~/Tools/sliver || { echo "[!] Sliver repo not found after clone."; return; }

        echo "[*] Building Sliver (this may take a moment)..."
        if make >> ~/build_log.txt 2>&1; then
            echo "[+] Sliver built successfully."

            # Copy binaries to /usr/local/bin if they exist
            if [[ -f ./sliver-server && -f ./sliver-client ]]; then
                sudo cp ./sliver-server ./sliver-client /usr/local/bin/
                echo "[+] Sliver binaries installed to /usr/local/bin."
            else
                echo "[!] Sliver binaries not found after build."
            fi
        else
            echo "[!] Sliver build failed. See ~/build_log.txt for details."
        fi
    else
        echo "[!] Failed to clone Sliver repository."
    fi
}

#██████╗  █████╗ ████████╗ █████╗     ██╗   ██╗██╗███████╗██╗   ██╗ █████╗ ██╗     ██╗███████╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
#██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗    ██║   ██║██║██╔════╝██║   ██║██╔══██╗██║     ██║╚══███╔╝██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
#██║  ██║███████║   ██║   ███████║    ██║   ██║██║███████╗██║   ██║███████║██║     ██║  ███╔╝ ███████║   ██║   ██║██║   ██║██╔██╗ ██║
#██║  ██║██╔══██║   ██║   ██╔══██║    ╚██╗ ██╔╝██║╚════██║██║   ██║██╔══██║██║     ██║ ███╔╝  ██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
#██████╔╝██║  ██║   ██║   ██║  ██║     ╚████╔╝ ██║███████║╚██████╔╝██║  ██║███████╗██║███████╗██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
#╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝      ╚═══╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝
#                                                                                                                                    

# === ELK Stack ===
function install_elk_stack {
    echo "[*] Installing ELK stack..."
    sudo apt-get install -y apt-transport-https gnupg openjdk-11-jdk >/dev/null 2>&1
    curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic.gpg
    echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main" | \
        sudo tee /etc/apt/sources.list.d/elastic-7.x.list >/dev/null
    sudo apt-get update -y >/dev/null 2>&1
    if sudo apt-get install -y elasticsearch kibana logstash filebeat >/dev/null 2>&1; then
        echo "[+] ELK stack installed."
    else
        echo "[!] Failed to install ELK stack."
    fi

    echo "[*] Installing logstash-codec-nmap..."
    sudo /usr/share/logstash/bin/logstash-plugin install logstash-codec-nmap >/dev/null 2>&1
    echo "[+] logstash-codec-nmap installed."

    echo "[*] Enabling ELK services..."
    sudo systemctl enable --now elasticsearch kibana logstash filebeat >/dev/null 2>&1
    echo "[+] ELK services started."
}

# === Filebeat Config ===
function install_filebeat_nmap_pipeline {
    echo "[*] Configuring Filebeat for Nmap..."
    sudo tee /etc/filebeat/filebeat.yml >/dev/null <<EOF
filebeat.inputs:
- type: filestream
  enabled: true
  paths:
    - /home/$USER/Scans/**/*.xml
  parsers:
    - decode_xml:
        id: nmap-decoder
output.logstash:
  hosts: ["localhost:5044"]
EOF
    sudo systemctl restart filebeat >/dev/null 2>&1
    echo "[+] Filebeat configured."
}

# === Create ~/Scans with sample Nmap scan ===
function create_scans_folder {
    echo "[*] Creating ~/Scans/ structure..."
    mkdir -p ~/Scans/EventA ~/Scans/EventB
    cat <<EOF > ~/Scans/sample_scan.xml
<?xml version="1.0"?>
<nmaprun scanner="nmap" args="example" start="0">
  <host>
    <status state="up"/>
    <address addr="10.10.10.10" addrtype="ipv4"/>
    <hostnames><hostname name="target.local"/></hostnames>
    <ports>
      <port protocol="tcp" portid="80"><state state="open"/><service name="http"/></port>
      <port protocol="tcp" portid="443"><state state="open"/><service name="https"/></port>
    </ports>
  </host>
</nmaprun>
EOF
    cp ~/Scans/sample_scan.xml ~/Scans/EventA/
    cp ~/Scans/sample_scan.xml ~/Scans/EventB/
    echo "[+] Sample Nmap XML scan created in ~/Scans and subfolders."
}

# ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗   ██╗██████╗ 
#██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║   ██║██╔══██╗
#██║     ██║     █████╗  ███████║██╔██╗ ██║██║   ██║██████╔╝
#██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║   ██║██╔═══╝ 
#╚██████╗███████╗███████╗██║  ██║██║ ╚████║╚██████╔╝██║     
# ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝     
#                                                           

# === Regenerate font cache ===
function regenerate_fonts {
    echo "[*] Rebuilding font cache..."
    sudo fc-cache -fv >/dev/null 2>&1
    echo "[+] Font cache rebuilt."
}

# === Autostart browser after reboot ===
function setup_browser_autostart {
    echo "[*] Setting browser to auto-open on reboot..."
    mkdir -p ~/.config/autostart
    cat <<EOF > ~/.config/autostart/open-kibana.desktop
[Desktop Entry]
Type=Application
Exec=xdg-open http://localhost:9200/ && xdg-open http://localhost:5601/app/home#/
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Open Kibana
EOF
    echo "[+] Autostart desktop entry created."
}

# === Create sample Nmap starter dashboard for Kibana ===
function create_sample_dashboard_file {
    echo "[*] Running: create_sample_dashboard_file"
    printf '{"type":"dashboard","id":"nmap-overview","attributes":{"title":"Nmap Scan Overview","description":"Basic visual overview of Nmap scan results.","panelsJSON":"[]","optionsJSON":"{\"darkTheme\":false}","version":1,"timeRestore":false,"kibanaSavedObjectMeta":{"searchSourceJSON":"{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"}},"references":[]}' > ~/kibana-nmap-sample.ndjson
    echo -e "${SUCCESS}[+]${ENDCOLOR} Dashboard file written to ~/kibana-nmap-sample.ndjson"
}

# === Import dashboard into Kibana with retries ===
function kibana_import_retry {
    echo "[*] Waiting for Kibana to become available..."
    for i in {1..20}; do
        if curl -s http://localhost:5601/api/status | grep -q "Kibana status is green"; then
            echo "[*] Kibana ready on attempt $i."
            break
        fi
        echo "[*] Kibana not ready (attempt $i), retrying in 5s..."
        sleep 5
    done
    echo "[*] Importing dashboard..."
    curl -X POST "http://localhost:5601/api/saved_objects/_import?overwrite=true" \      -H "kbn-xsrf: true" \      -F file=@~/kibana-nmap-sample.ndjson
    echo -e "${SUCCESS}[+]${ENDCOLOR} Dashboard imported."
}

# === Reboot system ===
function final_reboot {
    echo "[*] Build completed at \$(date)"
    echo "[*] Rebooting in 5 seconds..."
    sleep 5
    sudo reboot
}

# === Build Function ===
function build {
	# Terminal / Logging
    fix_kali_gpg_key
    fix_locales_and_fonts
    update_os
	# Dependencies / Languages
    update_wordlists
	configure_firefox
    install_golang
	# Tools
    install_ncat
    install_projectdiscovery_tools
	install_gowitness
    install_massdns
    install_kerbrute
	install_sliver
	# Data Visualization
    install_elk_stack
    install_filebeat_nmap_pipeline
    create_scans_folder
	# Cleanup
    regenerate_fonts
    setup_browser_autostart
	
	final_reboot
	#create_sample_dashboard_file # Optional
	#kibana_import_retry # Optional
}

# === Main ===
build
echo "[*] Build finished at $(date)"