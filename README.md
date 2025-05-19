# Kali Build Script

A lightweight script that transforms a fresh Kali Linux VM into a CTF-ready pentesting environment.

---

## 🚀 Features

- **System Maintenance**  
  - Runs `apt update && apt upgrade`  
  - Rebuilds locale and font caches  
- **Centralized Logging**  
  - Configures Filebeat → Logstash → Elasticsearch  
- **Shell Recon Helpers**  
  - `alive` &ndash; ping sweep  
  - `initial` &ndash; default Nmap scan (`-sC -sV -vv`) with custom input/output  
  - `venvclone` &ndash; clone a Git repo and spin up a Python virtualenv  
- **Wordlist Refresh**  
  - Pulls the latest SecLists into `/usr/share/seclists`  
- **ELK Stack Deployment**  
  - Elasticsearch, Kibana, Logstash, Filebeat  
  - `logstash-codec-nmap` plugin for parsing Nmap XML  

---

## 🛠️ Installed Tools

- `sshuttle`  
- `sshpass`  
- `golang-go`  
- `firefox-esr`  
- `FoxyProxy Standard (Firefox extension)`  
- `pdtm (ProjectDiscovery Tools Manager)`  
- `GoWitness`  
- `massdns`  
- `kerbrute`  
- `Sliver`  
- `elasticsearch`  
- `kibana`  
- `logstash`  
- `filebeat`  
- `logstash-codec-nmap`  

---

## ⚙️ Usage

**Do not run as sudo!**  
