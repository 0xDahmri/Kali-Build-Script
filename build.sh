#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# Kali Build Script - v5.11.0
# - Quiet, timestamped console + dual log files (system + user)
# - Robust APT: IPv4-only, retries/timeouts, update retries, --fix-missing fallback
# - Fonts + locales, CLI QoL, Go toolchain
# - Security tools: pdtm/httpx, massdns, kerbrute, GoWitness, Sliver
# - NEW: pre2k, pretender, RemoteMonologue (src), Internal-Monologue (src), soapy, magic-wormhole
# - No ELK, no Scans
# =============================================================================

START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VER="5.11.0"
LOG_DIR_SYS="/var/log"
LOG_DIR_USER="$HOME"
LOG_SYS="${LOG_DIR_SYS}/kali-build-$(date -u +%Y%m%d-%H%M%S).log"
LOG_USER="${LOG_DIR_USER}/build-$(date -u +%Y%m%d-%H%M%S).log"
LATEST_SYS="${LOG_DIR_SYS}/kali-build-latest.log"
LATEST_USER="${LOG_DIR_USER}/build-latest.log"

# ---- colors ----
RED=$'\033[31m'; YELLOW=$'\033[33m'; GREEN=$'\033[32m'; RESET=$'\033[0m'

# ---- global printing control ----
LOGGING_READY=0
CONSOLE_FD=1
CONSOLE_ERR_FD=2

# ---- helpers ----
ts() { date -u +[%Y-%m-%dT%H:%M:%SZ]; }

# Raw line formatters (these include newlines)
_note() { printf "    - %s\n" "$*"; }
_info() { printf "[*] %s\n" "$*"; }
_ok()   { printf "[+] %s\n" "$*"; }
_warn() { printf "${YELLOW}[!]${RESET} %s\n" "$*"; }
_err()  { printf "${RED}[x]${RESET} %s\n" "$*"; }

# Console printers — preserve newlines
note() { if (( LOGGING_READY )); then { printf "%s " "$(ts)"; _note "$@"; } >&3; else { printf "%s " "$(ts)"; _note "$@"; }; fi; }
info() { if (( LOGGING_READY )); then { printf "%s " "$(ts)"; _info "$@"; } >&3; else { printf "%s " "$(ts)"; _info "$@"; }; fi; }
ok()   { if (( LOGGING_READY )); then { printf "%s " "$(ts)"; _ok "$@"; }   >&3; else { printf "%s " "$(ts)"; _ok "$@";   }; fi; }
warn() { if (( LOGGING_READY )); then { printf "%s " "$(ts)"; _warn "$@"; } >&3; else { printf "%s " "$(ts)"; _warn "$@"; }; fi; }
err()  { if (( LOGGING_READY )); then { printf "%s " "$(ts)"; _err "$@"; }  >&3; else { printf "%s " "$(ts)"; _err "$@";  }; fi; }

# ---------- privilege escalation ----------
require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    printf "%s %s\n" "$(ts)" "[!] This script performs system changes and should run as root." >&1
    printf "%s %s\n" "$(ts)" "[!] Re-running with sudo..." >&1
    exec sudo -E bash "$0" "$@"
  fi
}

# ---------- logging ----------
setup_logging() {
  mkdir -p "$LOG_DIR_SYS" "$LOG_DIR_USER"
  : > "$LOG_SYS"; : > "$LOG_USER"
  ln -sf "$LOG_SYS" "$LATEST_SYS" || true
  ln -sf "$LOG_USER" "$LATEST_USER" || true

  exec 3>&1 4>&2
  CONSOLE_FD=3
  CONSOLE_ERR_FD=4

  exec > >(stdbuf -oL awk '{print strftime("[%Y-%m-%dT%H:%M:%SZ]", systime()), $0}' | tee -a "$LOG_SYS" "$LOG_USER" >/dev/null)
  exec 2> >(stdbuf -oL awk '{print strftime("[%Y-%m-%dT%H:%M:%SZ]", systime()), $0}' | tee -a "$LOG_SYS" "$LOG_USER" >/dev/null)

  LOGGING_READY=1
  info "Starting build v${VER} at ${START_UTC}"
  note "Logs: ${LOG_SYS}  |  ${LOG_USER}"
}

# ---------- traps ----------
setup_traps() {
  set -o errtrace
  trap 'ec=$?; ln=${BASH_LINENO[0]:-unknown}; err "Error on or near line $ln (exit $ec)"; note "See logs: ${LATEST_SYS} | ${LATEST_USER}"; exit $ec' ERR
  trap 'ec=$?; if (( ec==0 )); then ok "Build finished successfully"; else warn "Build aborted with exit code $ec"; fi' EXIT
}

# ---------- curl wrapper ----------
dl() { # dl <url> <outfile>
  local url="$1" out="$2"
  curl -fsL --retry 3 --retry-delay 1 --connect-timeout 20 -o "$out" "$url" >/dev/null 2>&1
}

# ---------- APT hardening (IPv4 + retries + timeouts) ----------
export DEBIAN_FRONTEND=noninteractive

tune_apt_network() {
  info "Tuning APT network (IPv4, retries/timeouts)"
  cat >/etc/apt/apt.conf.d/99network-tuning <<'EOF'
Acquire::ForceIPv4 "true";
Acquire::Retries "5";
Acquire::http::Timeout "20";
Acquire::https::Timeout "20";
EOF
  ok "APT network tuning applied"
}

apt_refresh() {
  info "Refreshing apt cache"
  local i
  for i in 1 2 3; do
    if apt-get -qq update; then
      ok "apt update (attempt $i) OK"
      return 0
    fi
    warn "apt update failed (attempt $i); retrying..."
    sleep 3
  done
  apt-get -qq update
  ok "apt update final OK"
}

apt_quiet_install() {
  local pkgs=("$@")
  note "Ensuring packages: ${pkgs[*]}"
  if apt-get -y -o Dpkg::Progress-Fancy=1 -o Acquire::Retries=5 -o Acquire::ForceIPv4=true -qq install "${pkgs[@]}" >/dev/null; then
    ok "APT ready: ${pkgs[*]}"
    return 0
  fi
  warn "APT install failed; attempting fix-missing recovery"
  apt-get -f -y -qq install >/dev/null 2>&1 || true
  apt-get -qq clean || true
  apt_refresh
  apt-get -y -o Dpkg::Progress-Fancy=1 -o Acquire::Retries=5 -o Acquire::ForceIPv4=true --fix-missing -qq install "${pkgs[@]}" >/dev/null
  ok "APT ready after recovery: ${pkgs[*]}"
}

# ---------- Small utilities ----------
ensure_line() { # file line
  local file="$1" line="$2"
  grep -qxF -- "$line" "$file" 2>/dev/null || echo "$line" | tee -a "$file" >/dev/null
}

# ---------- Tool installers ----------
install_locales_fonts() {
  info "Locales & fonts"
  apt_quiet_install locales tzdata fontconfig fonts-noto fonts-noto-color-emoji fonts-dejavu
  sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  locale-gen
  update-locale LANG=en_US.UTF-8
  fc-cache -f >/dev/null 2>&1 || true
  ok "Locales and fonts configured"
}

install_base_cli() {
  info "CLI QoL"
  apt_quiet_install ca-certificates curl gnupg git jq ripgrep fd-find bat fzf unzip tar build-essential pkg-config python3 python3-venv python3-pip pipx
  ln -sf /usr/bin/batcat /usr/local/bin/bat || true
  ln -sf /usr/bin/fdfind /usr/local/bin/fd || true
  ok "CLI tools installed"
}

install_browser_bits() {
  info "Browser (no launch)"
  apt_quiet_install firefox-esr
  mkdir -p "$HOME/Addons"
  if dl "https://addons.mozilla.org/firefox/downloads/latest/foxyproxy-standard/latest.xpi" \
        "$HOME/Addons/foxyproxy_standard-latest.xpi"; then
    ok "FoxyProxy XPI saved"
  else
    note "FoxyProxy XPI not fetched (skipping quietly)"
  fi
}

install_go() {
  info "Golang toolchain"
  apt_quiet_install golang-go
  ensure_line "/etc/profile.d/go_path.sh" 'export GOPATH="$HOME/go"'
  ensure_line "/etc/profile.d/go_path.sh" 'export PATH="$PATH:$HOME/go/bin"'
  ok "Go installed"
}

install_pdtm_httpx() {
  info "ProjectDiscovery: pdtm + httpx"
  curl -fsL https://raw.githubusercontent.com/projectdiscovery/pdtm/main/install.sh | bash >/dev/null 2>&1 || true
  export PATH="$PATH:$HOME/.pdtm/bin:$HOME/go/bin"
  if command -v pdtm >/dev/null 2>&1; then
    pdtm -i httpx >/dev/null 2>&1 || true
  fi
  if ! command -v httpx >/dev/null 2>&1; then
    GOBIN="$HOME/go/bin" go install github.com/projectdiscovery/httpx/cmd/httpx@latest >/dev/null 2>&1 || true
  fi
  ok "httpx available"
}

install_massdns() {
  info "massdns"
  apt_quiet_install git make gcc libc6-dev
  if [[ ! -d /opt/massdns ]]; then
    git clone --depth=1 https://github.com/blechschmidt/massdns /opt/massdns >/dev/null 2>&1
    make -C /opt/massdns >/dev/null 2>&1
    ln -sf /opt/massdns/bin/massdns /usr/local/bin/massdns || true
  fi
  ok "massdns installed"
}

install_kerbrute() {
  info "kerbrute"
  local url="https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64"
  if dl "$url" /usr/local/bin/kerbrute; then
    chmod +x /usr/local/bin/kerbrute || true
    ok "kerbrute available"
  else
    note "kerbrute not fetched (skipping quietly)"
  fi
}

install_gowitness() {
  info "GoWitness"
  export PATH="$PATH:$HOME/go/bin"
  GOBIN="$HOME/go/bin" go install github.com/sensepost/gowitness@latest >/dev/null 2>&1 || true
  ln -sf "$HOME/go/bin/gowitness" /usr/local/bin/gowitness || true
  ok "GoWitness installed"
}

install_sliver() {
  info "Sliver (server & client)"
  mkdir -p /opt/sliver && cd /opt/sliver
  if dl "https://github.com/BishopFox/sliver/releases/latest/download/sliver-server_linux" sliver-server; then
    chmod +x sliver-server || true
    ln -sf /opt/sliver/sliver-server /usr/local/bin/sliver-server || true
  else
    note "sliver-server not fetched (skipping quietly)"
  fi
  if dl "https://github.com/BishopFox/sliver/releases/latest/download/sliver-client_linux" sliver-client; then
    chmod +x sliver-client || true
    ln -sf /opt/sliver/sliver-client /usr/local/bin/sliver-client || true
  else
    note "sliver-client not fetched (skipping quietly)"
  fi
  ok "Sliver step complete"
}

install_pre2k() {
  info "pre2k (pre-Windows 2000 computer accounts)"
  if command -v pre2k >/dev/null 2>&1; then
    ok "pre2k already present"
    return 0
  fi
  if pipx install --force "git+https://github.com/garrettfoster13/pre2k.git" >/dev/null 2>&1; then
    ok "pre2k installed (pipx)"
  else
    warn "pre2k install failed (skipping)"
  fi
}

install_pretender() {
  info "pretender (mDNS/LLMNR/NetBIOS/DHCPv6 spoofing)"
  # Try go install directly to /usr/local/bin; fallback to clone+build
  if command -v pretender >/dev/null 2>&1; then
    ok "pretender already present"
    return 0
  fi
  if GOBIN=/usr/local/bin go install github.com/RedTeamPentesting/pretender@latest >/dev/null 2>&1; then
    ok "pretender installed (go install)"
    return 0
  fi
  warn "pretender go install failed; trying source build"
  if [[ ! -d /opt/pretender ]]; then
    git clone --depth=1 https://github.com/RedTeamPentesting/pretender /opt/pretender >/dev/null 2>&1 || true
  fi
  if [[ -d /opt/pretender ]]; then
    (cd /opt/pretender && go build -trimpath -o /usr/local/bin/pretender >/dev/null 2>&1) || true
    if command -v pretender >/dev/null 2>&1; then
      ok "pretender built from source"
    else
      warn "pretender build failed (skipping)"
    fi
  else
    warn "pretender source unavailable (skipping)"
  fi
}

install_remote_monologue() {
  info "RemoteMonologue (source clone)"
  if [[ ! -d /opt/RemoteMonologue ]]; then
    git clone --depth=1 https://github.com/3lp4tr0n/RemoteMonologue /opt/RemoteMonologue >/dev/null 2>&1 || true
  fi
  ok "RemoteMonologue cloned to /opt/RemoteMonologue (Windows-targeted)"
}

install_internal_monologue() {
  info "Internal-Monologue (source clone)"
  if [[ ! -d /opt/Internal-Monologue ]]; then
    git clone --depth=1 https://github.com/eladshamir/Internal-Monologue /opt/Internal-Monologue >/dev/null 2>&1 || true
  fi
  ok "Internal-Monologue cloned to /opt/Internal-Monologue (Windows-targeted)"
}

install_soapy() {
  info "soapy (Python AO simulation)"
  if command -v soapy >/dev/null 2>&1; then
    ok "soapy already present"
    return 0
  fi
  if pipx install soapy >/dev/null 2>&1; then
    ok "soapy installed (pipx)"
  else
    note "soapy not installed (skipping quietly)"
  fi
}

install_magic_wormhole() {
  info "magic-wormhole (secure file xfer)"
  if command -v wormhole >/dev/null 2>&1; then
    ok "wormhole already present"
    return 0
  fi
  if pipx install magic-wormhole >/dev/null 2>&1; then
    ok "magic-wormhole installed (wormhole CLI)"
  else
    note "magic-wormhole not installed (skipping quietly)"
  fi
}

# ---------- Final polish ----------
notification_sound() { printf "\a" >&3 || true; }

cleanup() {
  info "Cleanup"
  apt-get -qq autoremove -y >/dev/null 2>&1 || true
  apt-get -qq clean >/dev/null 2>&1 || true
  ok "Cleanup done"
}

# ---------- Options ----------
REBOOT_MODE="${REBOOT_MODE:-never}"   # always|never|auto

usage() {
  cat >&3 <<USAGE
Usage: sudo ./build.sh [--reboot=always|never|auto]
Default: --reboot=${REBOOT_MODE}
USAGE
}

# ---------- Main ----------
main() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --reboot=*) REBOOT_MODE="${arg#*=}";;
      -h|--help) usage; exit 0;;
    esac
  done

  require_root "$@"
  setup_logging
  setup_traps

  # Harden APT networking first, then refresh once
  tune_apt_network
  apt_refresh

  info "Phase: base system"
  install_locales_fonts
  install_base_cli

  info "Phase: browsing & dev toolchains"
  install_browser_bits
  install_go

  info "Phase: security tools"
  install_pdtm_httpx
  install_massdns
  install_kerbrute
  install_gowitness
  install_sliver
  install_pre2k
  install_pretender
  install_remote_monologue
  install_internal_monologue
  install_soapy
  install_magic_wormhole

  cleanup
  ok "Build complete"
  note "Logs: ${LATEST_SYS}  |  ${LATEST_USER}"
  notification_sound

  case "$REBOOT_MODE" in
    always) warn "Rebooting now..."; sleep 2; systemctl reboot ;;
    auto)   warn "Rebooting now..."; sleep 2; systemctl reboot ;;
    never)  ok "No reboot requested (--reboot=never)";;
    *)      ok "Unknown reboot mode '$REBOOT_MODE' -> no reboot";;
  esac
}

main "$@"
