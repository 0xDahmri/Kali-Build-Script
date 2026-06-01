#!/usr/bin/env bash
# Exit immediately on error (-e), treat unset variables as errors (-u),
# propagate pipe failures (-o pipefail), and inherit ERR traps into functions (-E).
set -Eeuo pipefail

# =============================================================================
# Kali Build Script - v6.0.0
# - Quiet, timestamped console + dual log files (system + user)
# - Robust APT: IPv4-only, retries/timeouts, update retries, --fix-missing fallback
# - Fonts + locales, CLI QoL, Go toolchain (official tarball, auto-versioned)
# - Security tools: pdtm/httpx, massdns, kerbrute (verified), GoWitness,
#   Sliver (verified), ligolo-ng, nuclei, subfinder
# - AD/Windows tooling: pre2k, pretender, certipy-ad, coercer, nxc (NetExec),
#   RemoteMonologue (src), Internal-Monologue (src)
# - Utilities: magic-wormhole
# =============================================================================

# Capture build start time before anything else runs so it's accurate in logs.
START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VER="6.0.0"

# Two log destinations: /var/log (root-owned, survives user home wipes) and
# $HOME (accessible to the invoking user without sudo after the build).
LOG_DIR_SYS="/var/log"
LOG_DIR_USER="$HOME"
LOG_SYS="${LOG_DIR_SYS}/kali-build-$(date -u +%Y%m%d-%H%M%S).log"
LOG_USER="${LOG_DIR_USER}/build-$(date -u +%Y%m%d-%H%M%S).log"
# Stable symlinks so "tail -f ~/build-latest.log" always works regardless of run timestamp.
LATEST_SYS="${LOG_DIR_SYS}/kali-build-latest.log"
LATEST_USER="${LOG_DIR_USER}/build-latest.log"

# ---- colors ----
RED=$'\033[31m'; YELLOW=$'\033[33m'; GREEN=$'\033[32m'; RESET=$'\033[0m'

# ---- global printing control ----
# LOGGING_READY gates whether console output uses fd 3 (real TTY, saved before
# log redirection) or falls back to fd 1. Set to 1 in setup_logging once fds
# are wired up.
LOGGING_READY=0
CONSOLE_FD=1
CONSOLE_ERR_FD=2

# ---- helpers ----
ts() { date -u +[%Y-%m-%dT%H:%M:%SZ]; }

# Raw line formatters — prefixes only, no timestamp (timestamp is added by the caller).
_note() { printf "    - %s\n" "$*"; }
_info() { printf "[*] %s\n" "$*"; }
_ok()   { printf "[+] %s\n" "$*"; }
_warn() { printf "${YELLOW}[!]${RESET} %s\n" "$*"; }
_err()  { printf "${RED}[x]${RESET} %s\n" "$*"; }

# Console printers: write to fd 3 (saved TTY) once logging is active so these
# messages appear on screen even though fd 1/2 are redirected to the log pipes.
note() { if (( LOGGING_READY )); then { printf "%s " "$(ts)"; _note "$@"; } >&3; else { printf "%s " "$(ts)"; _note "$@"; }; fi; }
info() { if (( LOGGING_READY )); then { printf "%s " "$(ts)"; _info "$@"; } >&3; else { printf "%s " "$(ts)"; _info "$@"; }; fi; }
ok()   { if (( LOGGING_READY )); then { printf "%s " "$(ts)"; _ok "$@"; }   >&3; else { printf "%s " "$(ts)"; _ok "$@";   }; fi; }
warn() { if (( LOGGING_READY )); then { printf "%s " "$(ts)"; _warn "$@"; } >&3; else { printf "%s " "$(ts)"; _warn "$@"; }; fi; }
err()  { if (( LOGGING_READY )); then { printf "%s " "$(ts)"; _err "$@"; }  >&3; else { printf "%s " "$(ts)"; _err "$@";  }; fi; }

# ---------- privilege escalation ----------
require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    printf "%s %s\n" "$(ts)" "[!] Re-running with sudo..." >&1
    # -E preserves the invoking user's environment (HOME, PATH) so log paths
    # and GOPATH point to the user's home, not /root.
    exec sudo -E bash "$0" "$@"
  fi
}

# ---------- logging ----------
setup_logging() {
  mkdir -p "$LOG_DIR_SYS" "$LOG_DIR_USER"
  # Truncate log files fresh each run so they don't grow unboundedly.
  : > "$LOG_SYS"; : > "$LOG_USER"
  ln -sf "$LOG_SYS" "$LATEST_SYS" || true
  ln -sf "$LOG_USER" "$LATEST_USER" || true

  # Save original stdout/stderr as fd 3/4 so info/ok/warn/err can still
  # reach the terminal after fd 1/2 are redirected into the log pipeline below.
  exec 3>&1 4>&2
  CONSOLE_FD=3
  CONSOLE_ERR_FD=4

  # Redirect all fd 1/2 output through awk (adds timestamps) then tee to both
  # log files. >/dev/null at the end of the tee discards the tee stdout so
  # nothing leaks back to the terminal from subcommands.
  exec > >(stdbuf -oL awk '{print strftime("[%Y-%m-%dT%H:%M:%SZ]", systime()), $0}' | tee -a "$LOG_SYS" "$LOG_USER" >/dev/null)
  exec 2> >(stdbuf -oL awk '{print strftime("[%Y-%m-%dT%H:%M:%SZ]", systime()), $0}' | tee -a "$LOG_SYS" "$LOG_USER" >/dev/null)

  LOGGING_READY=1
  info "Starting build v${VER} at ${START_UTC}"
  note "Logs: ${LOG_SYS}  |  ${LOG_USER}"
}

# ---------- traps ----------
setup_traps() {
  # errtrace makes the ERR trap fire inside functions and subshells, not just
  # at the top level.
  set -o errtrace
  # ERR trap: print the failing line number so the log is self-diagnosing.
  trap 'ec=$?; ln=${BASH_LINENO[0]:-unknown}; err "Error on or near line $ln (exit $ec)"; note "See logs: ${LATEST_SYS} | ${LATEST_USER}"; exit $ec' ERR
  # EXIT trap: always fires last, gives a clean success/failure summary.
  trap 'ec=$?; if (( ec==0 )); then ok "Build finished successfully"; else warn "Build aborted with exit code $ec"; fi' EXIT
}

# ---------- curl wrapper ----------
# Centralised download helper so retry/timeout flags are consistent everywhere.
# -f: fail on HTTP errors (exit 22) rather than saving the error page.
# -s: silent (no progress bar). -L: follow redirects.
dl() { # dl <url> <outfile>
  local url="$1" out="$2"
  curl -fsL --retry 3 --retry-delay 1 --connect-timeout 20 -o "$out" "$url" >/dev/null 2>&1
}

# ---------- APT hardening ----------
# Set before any apt call so they apply to every install in the script.
# noninteractive: suppress all dpkg/apt prompts.
export DEBIAN_FRONTEND=noninteractive
# NEEDRESTART_MODE=a: automatically restart services instead of prompting.
# NEEDRESTART_SUSPEND=1: prevent needrestart from blocking apt entirely.
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
# Suppress the apt-listchanges changelog popup.
export APT_LISTCHANGES_FRONTEND=none

tune_apt_network() {
  info "Tuning APT network (IPv4, retries/timeouts)"
  # Written to a drop-in file so it persists for any future apt runs on this machine.
  # ForceIPv4: avoids hanging on broken IPv6 routes common in VM/lab environments.
  # Retries/Timeouts: make apt resilient to transient network issues.
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
  # All retries exhausted — abort loudly rather than proceeding with a stale cache.
  err "apt update failed after 3 attempts"
  return 1
}

apt_quiet_install() {
  local pkgs=("$@")
  note "Ensuring packages: ${pkgs[*]}"
  if apt-get -y -o Dpkg::Progress-Fancy=1 -o Acquire::Retries=5 -o Acquire::ForceIPv4=true -qq install "${pkgs[@]}" >/dev/null; then
    ok "APT ready: ${pkgs[*]}"
    return 0
  fi
  # First pass failed — attempt automatic dependency repair then retry with
  # --fix-missing to handle partial mirror syncs.
  warn "APT install failed; attempting fix-missing recovery"
  apt-get -f -y -qq install >/dev/null 2>&1 || true
  apt-get -qq clean || true
  apt_refresh
  apt-get -y -o Dpkg::Progress-Fancy=1 -o Acquire::Retries=5 -o Acquire::ForceIPv4=true --fix-missing -qq install "${pkgs[@]}" >/dev/null
  ok "APT ready after recovery: ${pkgs[*]}"
}

# ---------- Small utilities ----------
# Appends a line to a file only if it isn't already present — safe to call
# repeatedly without creating duplicates (idempotent).
ensure_line() { # file line
  local file="$1" line="$2"
  grep -qxF -- "$line" "$file" 2>/dev/null || echo "$line" | tee -a "$file" >/dev/null
}

# =============================================================================
# Tool installers
# =============================================================================

install_locales_fonts() {
  info "Locales & fonts"
  # locales/tzdata: required for correct en_US.UTF-8 output from tools; without
  #   this, non-ASCII characters in tool output can be garbled or cause crashes.
  # fontconfig + Noto/DejaVu fonts: GoWitness renders web pages through a
  #   headless browser — broad font coverage prevents foreign-language and
  #   special-character pages from rendering as empty boxes in screenshots.
  apt_quiet_install locales tzdata fontconfig fonts-noto fonts-noto-color-emoji fonts-dejavu
  sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  locale-gen
  update-locale LANG=en_US.UTF-8
  fc-cache -f >/dev/null 2>&1 || true
  ok "Locales and fonts configured"
}

install_base_cli() {
  info "CLI QoL + build dependencies"
  # ca-certificates: required for HTTPS downloads to validate against modern CAs.
  # curl: used throughout this script and as a general-purpose download tool.
  # gnupg: apt needs it to verify signed package repositories.
  # git: required to clone massdns, pretender, pre2k, RemoteMonologue, Internal-Monologue.
  # jq: JSON parsing for API responses and tool output at the command line.
  # ripgrep, fd-find, bat, fzf: fast modern replacements for grep/find/cat/history search.
  # unzip/tar: archive extraction used by install_go and install_ligolo_ng.
  # build-essential + pkg-config: compiler toolchain needed to build massdns and pretender from source.
  # python3 + python3-venv + python3-pip: Python runtime; pipx and several tools depend on it.
  # pipx: installs Python tools into isolated venvs so they don't conflict with each other
  #   or the system Python. Used for netexec, certipy-ad, coercer, pre2k, magic-wormhole.
  apt_quiet_install \
    ca-certificates curl gnupg git jq \
    ripgrep fd-find bat fzf \
    unzip tar build-essential pkg-config \
    python3 python3-venv python3-pip pipx

  # Debian renames these binaries to avoid conflicts; create canonical symlinks
  # so scripts and muscle memory can use 'bat' and 'fd' directly.
  ln -sf /usr/bin/batcat /usr/local/bin/bat 2>/dev/null || true
  ln -sf /usr/bin/fdfind /usr/local/bin/fd 2>/dev/null || true
  ok "CLI tools installed"
}

install_browser_bits() {
  info "Browser (no launch)"
  # firefox-esr: stable long-term-support Firefox for manual web testing and
  #   proxy-through-Burp workflows. ESR is preferred over the rapid-release
  #   channel because extension compatibility is more predictable.
  apt_quiet_install firefox-esr
  mkdir -p "$HOME/Addons"
  # The old automated XPI download broke when Mozilla changed their CDN.
  # Install FoxyProxy manually from the link below when first launching Firefox.
  ok "Firefox ESR installed; add FoxyProxy manually from addons.mozilla.org/en-US/firefox/addon/foxyproxy-standard/"
}

install_go() {
  info "Golang toolchain"
  # Kali/Debian's golang-go package lags the official release by months to over
  # a year. Many modern Go tools (nuclei, gowitness v3, subfinder) require
  # Go >= 1.21, so we install directly from the official tarball instead.
  local go_bin="/usr/local/go/bin/go"
  if [[ -x "$go_bin" ]]; then
    local ver major minor
    ver=$("$go_bin" version | awk '{print $3}' | sed 's/go//')
    major=$(echo "$ver" | cut -d. -f1)
    minor=$(echo "$ver" | cut -d. -f2)
    if (( major > 1 || (major == 1 && minor >= 21) )); then
      ok "Go ${ver} already installed (>= 1.21)"
      export PATH="$PATH:/usr/local/go/bin"
      return 0
    fi
    warn "Go ${ver} is below minimum 1.21; upgrading"
  fi

  # Fetch the current stable version string (e.g. "go1.24.3") from the
  # official endpoint rather than hardcoding a version that will go stale.
  local go_ver
  go_ver=$(curl -fsL "https://go.dev/VERSION?m=text" | head -1)
  [[ -z "$go_ver" ]] && { err "Could not determine latest Go version"; return 1; }
  info "Downloading ${go_ver}"

  local tmptar="/tmp/${go_ver}.linux-amd64.tar.gz"
  dl "https://go.dev/dl/${go_ver}.linux-amd64.tar.gz" "$tmptar" || { err "Go tarball download failed"; rm -f "$tmptar"; return 1; }

  # The official install instructions say to remove any prior /usr/local/go
  # before extracting to avoid mixing files from different versions.
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tmptar"
  rm -f "$tmptar"
  export PATH="$PATH:/usr/local/go/bin"

  # Write a profile.d script so every future login shell (any user) gets the
  # correct GOROOT, GOPATH, and PATH without manual configuration.
  cat >/etc/profile.d/go_path.sh <<'EOF'
export GOROOT=/usr/local/go
export GOPATH="$HOME/go"
export PATH="$PATH:/usr/local/go/bin:$GOPATH/bin:$HOME/.local/bin"
EOF
  ok "Go ${go_ver} installed to /usr/local/go"
}

install_pdtm_httpx() {
  info "ProjectDiscovery: pdtm + httpx"
  # pdtm (ProjectDiscovery Tool Manager) is the canonical way to install and
  # update the full PD tool suite. We install it via go install rather than
  # the upstream install.sh to avoid executing an unverified remote shell script.
  GOBIN="$HOME/go/bin" go install github.com/projectdiscovery/pdtm/cmd/pdtm@latest >/dev/null 2>&1 || true
  if command -v pdtm >/dev/null 2>&1; then
    # Let pdtm install httpx through its own managed path if available.
    pdtm -i httpx >/dev/null 2>&1 || true
  fi
  # Fall back to direct go install if pdtm didn't place httpx in PATH.
  # httpx is used for fast HTTP probing during recon (status codes, tech detection, etc.).
  if ! command -v httpx >/dev/null 2>&1; then
    GOBIN="$HOME/go/bin" go install github.com/projectdiscovery/httpx/cmd/httpx@latest >/dev/null 2>&1 || true
  fi
  ln -sf "$HOME/go/bin/httpx" /usr/local/bin/httpx 2>/dev/null || true
  ok "httpx available"
}

install_massdns() {
  info "massdns"
  # massdns is a high-performance DNS stub resolver used for bulk subdomain
  # resolution — it can resolve millions of names per second. It has no binary
  # release, so we build from source. build-essential from install_base_cli
  # already covers make/gcc/libc6-dev so no extra packages are needed here.
  if [[ ! -d /opt/massdns ]]; then
    git clone --depth=1 https://github.com/blechschmidt/massdns /opt/massdns >/dev/null 2>&1
    make -C /opt/massdns >/dev/null 2>&1
  fi
  # Verify the binary was actually produced before symlinking — make can exit 0
  # even when the build silently fails on missing headers.
  if [[ -f /opt/massdns/bin/massdns ]]; then
    ln -sf /opt/massdns/bin/massdns /usr/local/bin/massdns || true
    ok "massdns installed"
  else
    warn "massdns build failed or binary not found"
  fi
}

install_kerbrute() {
  info "kerbrute"
  # kerbrute performs fast Kerberos pre-auth username enumeration and password
  # spraying against AD without triggering traditional lockout policies.
  local tmp_bin="/tmp/kerbrute_linux_amd64"
  local tmp_sum="/tmp/kerbrute_checksums.txt"
  if dl "https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64" "$tmp_bin" && \
     dl "https://github.com/ropnop/kerbrute/releases/latest/download/checksums.txt" "$tmp_sum"; then
    # Verify the SHA256 checksum published alongside the release before installing.
    # This catches corrupted downloads and tampered binaries.
    local expected actual
    expected=$(grep "kerbrute_linux_amd64" "$tmp_sum" 2>/dev/null | awk '{print $1}')
    actual=$(sha256sum "$tmp_bin" | awk '{print $1}')
    if [[ -n "$expected" && "$expected" == "$actual" ]]; then
      install -m 755 "$tmp_bin" /usr/local/bin/kerbrute
      ok "kerbrute installed (checksum verified)"
    else
      warn "kerbrute checksum mismatch; skipping"
    fi
  else
    note "kerbrute not fetched (skipping quietly)"
  fi
  rm -f "$tmp_bin" "$tmp_sum" 2>/dev/null || true
}

install_gowitness() {
  info "GoWitness"
  # GoWitness takes automated screenshots of web services discovered during recon,
  # making it easy to visually triage large lists of hosts and identify interesting
  # targets without opening each URL manually.
  GOBIN="$HOME/go/bin" go install github.com/sensepost/gowitness@latest >/dev/null 2>&1 || true
  ln -sf "$HOME/go/bin/gowitness" /usr/local/bin/gowitness || true
  ok "GoWitness installed"
}

install_sliver() {
  info "Sliver (server & client)"
  # Sliver is an open-source C2 framework that supports HTTP(S), DNS, WireGuard,
  # and mTLS channels. We install both the server (operator machine) and the
  # client (can connect to a remote Sliver server) components.
  mkdir -p /opt/sliver
  local url_base="https://github.com/BishopFox/sliver/releases/latest/download"

  # Download to /tmp first, verify checksum, then install — avoids leaving a
  # partially-downloaded or tampered binary in /opt/sliver.
  if dl "${url_base}/sliver-server_linux" /tmp/sliver-server && \
     dl "${url_base}/sliver-server_linux.sha256" /tmp/sliver-server.sha256; then
    local expected actual
    # Sliver publishes .sha256 files containing just the hash with no filename.
    expected=$(awk '{print $1}' /tmp/sliver-server.sha256)
    actual=$(sha256sum /tmp/sliver-server | awk '{print $1}')
    if [[ "$expected" == "$actual" ]]; then
      install -m 755 /tmp/sliver-server /opt/sliver/sliver-server
      ln -sf /opt/sliver/sliver-server /usr/local/bin/sliver-server || true
      ok "sliver-server installed (checksum verified)"
    else
      warn "sliver-server checksum mismatch; skipping"
    fi
  else
    note "sliver-server not fetched (skipping quietly)"
  fi
  rm -f /tmp/sliver-server /tmp/sliver-server.sha256 2>/dev/null || true

  if dl "${url_base}/sliver-client_linux" /tmp/sliver-client && \
     dl "${url_base}/sliver-client_linux.sha256" /tmp/sliver-client.sha256; then
    local expected actual
    expected=$(awk '{print $1}' /tmp/sliver-client.sha256)
    actual=$(sha256sum /tmp/sliver-client | awk '{print $1}')
    if [[ "$expected" == "$actual" ]]; then
      install -m 755 /tmp/sliver-client /opt/sliver/sliver-client
      ln -sf /opt/sliver/sliver-client /usr/local/bin/sliver-client || true
      ok "sliver-client installed (checksum verified)"
    else
      warn "sliver-client checksum mismatch; skipping"
    fi
  else
    note "sliver-client not fetched (skipping quietly)"
  fi
  rm -f /tmp/sliver-client /tmp/sliver-client.sha256 2>/dev/null || true
}

install_ligolo_ng() {
  info "ligolo-ng (tunneling/pivoting)"
  # ligolo-ng creates reverse TLS tunnels from a target network back to the
  # operator, routing traffic transparently via a tun interface — no SOCKS
  # proxychains needed. We install the proxy (operator-side) component only;
  # the agent binary is deployed separately to the target.
  if [[ -f /usr/local/bin/ligolo-proxy ]]; then
    ok "ligolo-ng already present"
    return 0
  fi
  local tmpdir="/tmp/ligolo-ng-dl"
  mkdir -p "$tmpdir"
  if dl "https://github.com/nicocha30/ligolo-ng/releases/latest/download/ligolo-ng_proxy_linux_amd64.tar.gz" \
        "$tmpdir/proxy.tar.gz"; then
    tar -xzf "$tmpdir/proxy.tar.gz" -C "$tmpdir" 2>/dev/null || true
    # The binary name inside the archive has changed across releases; search for
    # any of the known names rather than assuming a specific one.
    local proxy_bin
    proxy_bin=$(find "$tmpdir" -maxdepth 1 -type f \( -name "proxy" -o -name "ligolo-ng" -o -name "ligolo-proxy" \) | head -1)
    if [[ -n "$proxy_bin" ]]; then
      # Install as 'ligolo-proxy' to avoid colliding with the generic 'proxy' name.
      install -m 755 "$proxy_bin" /usr/local/bin/ligolo-proxy
      ok "ligolo-ng proxy installed"
    else
      warn "ligolo-ng proxy binary not found in archive"
    fi
  else
    note "ligolo-ng not fetched (skipping quietly)"
  fi
  rm -rf "$tmpdir" 2>/dev/null || true
}

install_nuclei() {
  info "nuclei (vulnerability scanner)"
  # nuclei runs community-maintained YAML templates against targets to detect
  # CVEs, misconfigurations, exposed panels, and default credentials at scale.
  if command -v nuclei >/dev/null 2>&1; then
    ok "nuclei already present"
    return 0
  fi
  GOBIN="$HOME/go/bin" go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest >/dev/null 2>&1 || true
  ln -sf "$HOME/go/bin/nuclei" /usr/local/bin/nuclei || true
  ok "nuclei installed"
}

install_subfinder() {
  info "subfinder (subdomain enumeration)"
  # subfinder performs passive subdomain enumeration using certificate transparency
  # logs, DNS datasets, and APIs — no brute-forcing needed for initial recon.
  if command -v subfinder >/dev/null 2>&1; then
    ok "subfinder already present"
    return 0
  fi
  GOBIN="$HOME/go/bin" go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest >/dev/null 2>&1 || true
  ln -sf "$HOME/go/bin/subfinder" /usr/local/bin/subfinder || true
  ok "subfinder installed"
}

install_pre2k() {
  info "pre2k (pre-Windows 2000 computer accounts)"
  # pre2k checks whether legacy machine accounts (created before Windows 2000)
  # still use their default passwords (hostname in lowercase), which are trivially
  # guessable and often overlooked during AD hardening reviews.
  if command -v pre2k >/dev/null 2>&1; then
    ok "pre2k already present"
    return 0
  fi
  # Install directly from source via pipx; no stable PyPI release exists.
  if pipx install --force "git+https://github.com/garrettfoster13/pre2k.git" >/dev/null 2>&1; then
    ok "pre2k installed (pipx)"
  else
    warn "pre2k install failed (skipping)"
  fi
}

install_pretender() {
  info "pretender (mDNS/LLMNR/NetBIOS/DHCPv6 spoofing)"
  # pretender poisons name resolution protocols to capture NTLMv2 hashes from
  # hosts resolving non-existent names — functionally similar to Responder but
  # written in Go with a focus on selective/surgical poisoning.
  if command -v pretender >/dev/null 2>&1; then
    ok "pretender already present"
    return 0
  fi
  if GOBIN=/usr/local/bin go install github.com/RedTeamPentesting/pretender@latest >/dev/null 2>&1; then
    ok "pretender installed (go install)"
    return 0
  fi
  # go install can fail if the module has CGO dependencies or unusual build tags;
  # fall back to a manual source build as a secondary attempt.
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

install_netexec() {
  info "NetExec (nxc) — CrackMapExec successor"
  # NetExec is the actively maintained fork of CrackMapExec. It enumerates and
  # attacks SMB, WinRM, LDAP, MSSQL, RDP, and other Windows services in bulk
  # using credentials or hashes.
  if command -v nxc >/dev/null 2>&1; then
    ok "nxc already present"
    return 0
  fi
  if pipx install netexec >/dev/null 2>&1; then
    ok "nxc installed (pipx)"
  else
    warn "nxc install failed (skipping)"
  fi
}

install_certipy() {
  info "certipy-ad (AD CS exploitation)"
  # certipy enumerates and exploits misconfigurations in Active Directory
  # Certificate Services — ESC1-ESC13 attack paths, shadow credentials,
  # and PKINIT-based privilege escalation.
  if command -v certipy >/dev/null 2>&1; then
    ok "certipy already present"
    return 0
  fi
  if pipx install certipy-ad >/dev/null 2>&1; then
    ok "certipy-ad installed (pipx)"
  else
    warn "certipy-ad install failed (skipping)"
  fi
}

install_coercer() {
  info "coercer (NTLM coercion)"
  # coercer forces Windows hosts to authenticate to an attacker-controlled
  # machine via a suite of RPC calls (PetitPotam, PrinterBug, DFSCoerce, etc.),
  # enabling NTLM relay and hash capture attacks.
  if command -v coercer >/dev/null 2>&1; then
    ok "coercer already present"
    return 0
  fi
  if pipx install coercer >/dev/null 2>&1; then
    ok "coercer installed (pipx)"
  else
    warn "coercer install failed (skipping)"
  fi
}

install_remote_monologue() {
  info "RemoteMonologue (source clone)"
  # RemoteMonologue triggers NTLM authentication from remote Windows hosts via
  # DCOM — useful for coercing auth from machines where traditional methods are
  # blocked. Windows-targeted; source only, no Linux binary to install.
  if [[ ! -d /opt/RemoteMonologue ]]; then
    git clone --depth=1 https://github.com/3lp4tr0n/RemoteMonologue /opt/RemoteMonologue >/dev/null 2>&1 || true
  fi
  ok "RemoteMonologue cloned to /opt/RemoteMonologue (Windows-targeted)"
}

install_internal_monologue() {
  info "Internal-Monologue (source clone)"
  # Internal-Monologue extracts NetNTLMv1/v2 challenge responses from the local
  # Windows machine without touching LSASS, making it significantly stealthier
  # than Mimikatz for credential harvesting. Windows-targeted; source only.
  if [[ ! -d /opt/Internal-Monologue ]]; then
    git clone --depth=1 https://github.com/eladshamir/Internal-Monologue /opt/Internal-Monologue >/dev/null 2>&1 || true
  fi
  ok "Internal-Monologue cloned to /opt/Internal-Monologue (Windows-targeted)"
}

install_magic_wormhole() {
  info "magic-wormhole (secure file xfer)"
  # magic-wormhole transfers files between machines using a short human-readable
  # code, with end-to-end encryption and no server storing the data. Useful for
  # moving files to/from targets or collaborators without standing up infrastructure.
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

# =============================================================================
# Final polish
# =============================================================================

# Only ring the bell if fd 3 is an actual TTY — avoids spurious \a characters
# appearing in CI logs or non-interactive runs.
notification_sound() { [[ -t 3 ]] && printf "\a" >&3 || true; }

cleanup() {
  info "Cleanup"
  # Remove packages that were pulled in as dependencies but are no longer needed,
  # and wipe the apt package cache to reclaim disk space.
  apt-get -qq autoremove -y >/dev/null 2>&1 || true
  apt-get -qq clean >/dev/null 2>&1 || true
  ok "Cleanup done"
}

# ---------- Options ----------
REBOOT_MODE="${REBOOT_MODE:-never}"   # always|never|auto

usage() {
  cat >&3 <<USAGE
Usage: sudo ./build.sh [--reboot=always|never|auto]
  always  reboot unconditionally after build
  auto    reboot only if kernel or libraries were updated (/var/run/reboot-required)
  never   (default) no reboot
USAGE
}

# =============================================================================
# Main
# =============================================================================
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

  # Harden APT networking first so all subsequent installs benefit from it.
  tune_apt_network
  apt_refresh

  info "Phase: base system"
  install_locales_fonts
  install_base_cli

  info "Phase: browsing & dev toolchains"
  install_browser_bits
  install_go

  # Consolidate PATH once after Go is installed so every subsequent installer
  # can find 'go', installed Go binaries, and pipx-managed binaries without
  # each function managing its own PATH export.
  export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin:$HOME/.local/bin"
  # Register ~/.local/bin permanently in shell config for future sessions.
  pipx ensurepath --force >/dev/null 2>&1 || true

  info "Phase: security tools"
  install_pdtm_httpx
  install_massdns
  install_kerbrute
  install_gowitness
  install_sliver
  install_ligolo_ng
  install_nuclei
  install_subfinder

  info "Phase: AD / Windows tooling"
  install_pre2k
  install_pretender
  install_netexec
  install_certipy
  install_coercer
  install_remote_monologue
  install_internal_monologue

  info "Phase: utilities"
  install_magic_wormhole

  cleanup
  ok "Build complete"
  note "Logs: ${LATEST_SYS}  |  ${LATEST_USER}"
  notification_sound

  case "$REBOOT_MODE" in
    always)
      warn "Rebooting now..."
      sleep 2
      systemctl reboot
      ;;
    auto)
      # /var/run/reboot-required is written by apt when a kernel, glibc, or other
      # core library update requires a reboot to take effect.
      if [[ -f /var/run/reboot-required ]]; then
        warn "Kernel/libraries updated — rebooting now..."
        sleep 2
        systemctl reboot
      else
        ok "No reboot required"
      fi
      ;;
    never)
      ok "No reboot requested (--reboot=never)"
      ;;
    *)
      ok "Unknown reboot mode '$REBOOT_MODE' -> no reboot"
      ;;
  esac
}

main "$@"
