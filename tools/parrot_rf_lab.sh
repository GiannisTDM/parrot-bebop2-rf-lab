#!/bin/sh
# Parrot RF Lab - unified BCM43526 monitor and NVM experiment tool.
# Runs on the stock BusyBox ash shell of both Parrot Bebop 2 and
# SkyController 2. No Python or third-party packages are required.

VERSION="0.3.1"
WL_BIN="${WL_BIN:-/usr/sbin/bcmwl}"
INTERVAL="${RF_LAB_INTERVAL:-1}"
REQUESTED_PEER="${RF_LAB_PEER:-}"
NO_COLOR="${NO_COLOR:-0}"
NO_CLEAR="${RF_LAB_NO_CLEAR:-0}"
DEVICE_OVERRIDE="${RF_LAB_DEVICE:-auto}"
ACTIVE_NVM_OVERRIDE="${RF_LAB_NVM:-}"

ESC="$(printf '\033')"
if [ "$NO_COLOR" = "1" ]; then
    RESET=""; BOLD=""; DIM=""; CYAN=""; GREEN=""; YELLOW=""; RED=""; BLUE=""; WHITE=""
else
    RESET="${ESC}[0m"
    BOLD="${ESC}[1m"
    DIM="${ESC}[2m"
    CYAN="${ESC}[96m"
    GREEN="${ESC}[92m"
    YELLOW="${ESC}[93m"
    RED="${ESC}[91m"
    BLUE="${ESC}[94m"
    WHITE="${ESC}[97m"
fi

DEVICE=""
DEVICE_LABEL=""
ROLE_LABEL=""
RX_DIRECTION=""
ACTIVE_NVM=""
FACTORY_NVM=""
FTP_ROOT=""
BACKUP_DIR=""
LOG_DIR=""
WL_WITH_INTERFACE=0
STAGE_FILE=""
PEER_MAC=""
PEER_IP=""
CURSOR_HIDDEN=0

cleanup()
{
    [ -z "$STAGE_FILE" ] || rm -f "$STAGE_FILE" "${STAGE_FILE}.new" 2>/dev/null
    [ "$CURSOR_HIDDEN" -eq 0 ] || printf '%s[?25h' "$ESC"
    printf '%s' "$RESET"
}

trap cleanup 0
trap 'cleanup; exit 130' 1 2 15

clear_screen()
{
    [ "$NO_CLEAR" = "1" ] || printf '%s[H%s[J' "$ESC" "$ESC"
}

pause_screen()
{
    printf '\n%sPress Enter to continue...%s' "$DIM" "$RESET"
    IFS= read -r _pause_answer
}

is_integer()
{
    case "$1" in
        -*)
            _integer_tail="${1#-}"
            case "$_integer_tail" in ""|*[!0-9]*) return 1 ;; esac
            ;;
        ""|*[!0-9]*) return 1 ;;
    esac
    return 0
}

is_unsigned()
{
    case "$1" in
        ""|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

first_integer()
{
    awk '
        {
            for (i = 1; i <= NF; i++) {
                value = $i
                sub(/^[^0-9-]+/, "", value)
                sub(/[^0-9]+$/, "", value)
                if (value ~ /^-?[0-9]+$/) {
                    print value
                    exit
                }
            }
        }
    '
}

extract_mac()
{
    awk '
        {
            for (i = 1; i <= NF; i++) {
                candidate = $i
                gsub(/^[^0-9A-Fa-f]+|[^0-9A-Fa-f:]+$/, "", candidate)
                test_value = candidate
                colon_count = gsub(/:/, "", test_value)
                if (colon_count == 5 && candidate ~ /^[0-9A-Fa-f:]+$/) {
                    print tolower(candidate)
                    exit
                }
            }
        }
    '
}

average_two()
{
    if is_integer "$1" && is_integer "$2"; then
        printf '%s\n' $((($1 + $2) / 2))
    elif is_integer "$1"; then
        printf '%s\n' "$1"
    elif is_integer "$2"; then
        printf '%s\n' "$2"
    else
        printf '%s\n' ""
    fi
}

format_rate()
{
    if ! is_unsigned "$1"; then
        printf '%s' "--"
        return
    fi
    _rate_whole=$(($1 / 1000))
    _rate_tenth=$((($1 % 1000) / 100))
    if [ "$_rate_tenth" -eq 0 ]; then
        printf '%s' "$_rate_whole"
    else
        printf '%s.%s' "$_rate_whole" "$_rate_tenth"
    fi
}

format_mbps_from_bytes()
{
    if ! is_unsigned "$1" || ! is_unsigned "$2" || [ "$2" -eq 0 ]; then
        printf '%s' "--"
        return
    fi
    _mbps_tenths=$(($1 * 8 * 10 / ($2 * 1000000)))
    printf '%s.%s' $(($_mbps_tenths / 10)) $(($_mbps_tenths % 10))
}

qdbm_value()
{
    if ! is_unsigned "$1"; then
        printf '%s' "--"
        return
    fi
    _q_whole=$(($1 / 4))
    case $(($1 % 4)) in
        0) _q_frac="00" ;;
        1) _q_frac="25" ;;
        2) _q_frac="50" ;;
        3) _q_frac="75" ;;
    esac
    printf '%s.%s' "$_q_whole" "$_q_frac"
}

signal_color_code()
{
    _signal_value="$1"
    if ! is_integer "$_signal_value"; then
        printf '%s' "250"
    elif [ "$_signal_value" -le -60 ]; then
        printf '%s' "196"
    elif [ "$_signal_value" -le -40 ]; then
        _signal_step=$((($_signal_value + 60) * 5 / 20))
        case "$_signal_step" in
            0) printf '%s' 196 ;; 1) printf '%s' 202 ;; 2) printf '%s' 208 ;;
            3) printf '%s' 214 ;; 4) printf '%s' 220 ;; *) printf '%s' 226 ;;
        esac
    elif [ "$_signal_value" -le -20 ]; then
        _signal_step=$((($_signal_value + 40) * 5 / 20))
        case "$_signal_step" in
            0) printf '%s' 226 ;; 1) printf '%s' 190 ;; 2) printf '%s' 154 ;;
            3) printf '%s' 118 ;; 4) printf '%s' 82 ;; *) printf '%s' 46 ;;
        esac
    elif [ "$_signal_value" -lt -5 ]; then
        _signal_step=$((($_signal_value + 20) * 5 / 15))
        case "$_signal_step" in
            0) printf '%s' 46 ;; 1) printf '%s' 47 ;; 2) printf '%s' 48 ;;
            3) printf '%s' 49 ;; 4) printf '%s' 50 ;; *) printf '%s' 51 ;;
        esac
    else
        printf '%s' "51"
    fi
}

paint_signal()
{
    _paint_value="$1"
    _paint_text="$2"
    if [ "$NO_COLOR" = "1" ]; then
        printf '%s' "$_paint_text"
    else
        _paint_code="$(signal_color_code "$_paint_value")"
        printf '%s[38;5;%sm%s%s' "$ESC" "$_paint_code" "$_paint_text" "$RESET"
    fi
}

signal_bar()
{
    _bar_value="$1"
    _bar_width="${2:-28}"
    if ! is_integer "$_bar_value"; then
        printf '%*s' "$_bar_width" "" | tr ' ' '?'
        return
    fi
    if [ "$_bar_value" -le -90 ]; then
        _bar_filled=0
    elif [ "$_bar_value" -ge -5 ]; then
        _bar_filled="$_bar_width"
    else
        _bar_filled=$((($_bar_value + 90) * _bar_width / 85))
    fi
    _bar_empty=$((_bar_width - _bar_filled))
    _bar_left="$(printf '%*s' "$_bar_filled" "" | tr ' ' '=')"
    _bar_right="$(printf '%*s' "$_bar_empty" "" | tr ' ' '.')"
    paint_signal "$_bar_value" "${_bar_left}${_bar_right}"
}

wl()
{
    if [ -n "${RF_LAB_FIXTURE_DIR:-}" ]; then
        _fixture_name="$1"
        shift
        [ -f "${RF_LAB_FIXTURE_DIR}/${_fixture_name}.txt" ] && cat "${RF_LAB_FIXTURE_DIR}/${_fixture_name}.txt"
        return
    fi
    if [ "$WL_WITH_INTERFACE" -eq 1 ]; then
        "$WL_BIN" -i eth0 "$@"
    else
        "$WL_BIN" "$@"
    fi
}

detect_device()
{
    case "$DEVICE_OVERRIDE" in
        bebop2|bebop|drone)
            DEVICE="bebop2"
            ;;
        sc2|skycontroller2|controller)
            DEVICE="sc2"
            ;;
        auto)
            if [ -n "$ACTIVE_NVM_OVERRIDE" ]; then
                case "$ACTIVE_NVM_OVERRIDE" in
                    *-ffff-ffff.nvm) DEVICE="sc2" ;;
                    *) DEVICE="bebop2" ;;
                esac
            elif [ -f /lib/firmware/brcm/bcm43526.nvm ]; then
                DEVICE="bebop2"
            elif [ -f /lib/firmware/brcm/bcm43526-ffff-ffff.nvm ]; then
                DEVICE="sc2"
            else
                return 1
            fi
            ;;
        *)
            printf '%sUnknown RF_LAB_DEVICE value: %s%s\n' "$RED" "$DEVICE_OVERRIDE" "$RESET" >&2
            return 1
            ;;
    esac

    if [ "$DEVICE" = "bebop2" ]; then
        DEVICE_LABEL="Bebop 2"
        ROLE_LABEL="AP / aircraft"
        ACTIVE_NVM="${ACTIVE_NVM_OVERRIDE:-/lib/firmware/brcm/bcm43526.nvm}"
        FACTORY_NVM=""
        FTP_ROOT="${RF_LAB_FTP_ROOT:-/data/ftp/internal_000}"
        RX_DIRECTION="SkyController 2 -> Bebop 2"
        WL_WITH_INTERFACE=1
    else
        DEVICE_LABEL="SkyController 2"
        ROLE_LABEL="station / controller"
        ACTIVE_NVM="${ACTIVE_NVM_OVERRIDE:-/lib/firmware/brcm/bcm43526-ffff-ffff.nvm}"
        FACTORY_NVM="/factory/bcm43526-ffff-ffff.nvm"
        if [ -d /data/lib/ftp/internal_000 ]; then
            FTP_ROOT="${RF_LAB_FTP_ROOT:-/data/lib/ftp/internal_000}"
        else
            FTP_ROOT="${RF_LAB_FTP_ROOT:-/var/lib/ftp/internal_000}"
        fi
        RX_DIRECTION="Bebop 2 -> SkyController 2"
        WL_WITH_INTERFACE=0
    fi
    BACKUP_DIR="${FTP_ROOT}/rf_lab_backups"
    LOG_DIR="${FTP_ROOT}/rf_lab_logs"
    return 0
}

discover_peer()
{
    if [ -n "$REQUESTED_PEER" ]; then
        PEER_MAC="$(printf '%s\n' "$REQUESTED_PEER" | extract_mac)"
    elif [ "$DEVICE" = "sc2" ]; then
        PEER_MAC="$(wl bssid 2>/dev/null | extract_mac)"
    else
        _assoc="$(wl assoclist 2>/dev/null)"
        PEER_MAC="$(printf '%s\n' "$_assoc" | awk '
            {
                for (i = 1; i <= NF; i++) {
                    candidate = $i
                    test_value = candidate
                    colon_count = gsub(/:/, "", test_value)
                    if (colon_count == 5 && candidate ~ /^[0-9A-Fa-f:]+$/) {
                        candidate = tolower(candidate)
                        if (first == "") first = candidate
                        if (candidate ~ /^a0:14:3d:/) {
                            print candidate
                            selected = 1
                            exit
                        }
                    }
                }
            }
            END { if (!selected && first != "") print first }
        ')"
    fi

    if [ -n "$PEER_MAC" ]; then
        PEER_IP="$(awk -v wanted="$PEER_MAC" '
            NR > 1 && tolower($4) == tolower(wanted) { print $1; exit }
        ' /proc/net/arp 2>/dev/null)"
    else
        PEER_IP=""
    fi
}

parse_sta_info()
{
    awk '
        function after_colon(line, item, count) {
            sub(/^[^:]*:[ \t]*/, "", line)
            count = split(line, item, /[ \t]+/)
            return count
        }
        /per antenna rssi of last rx data frame:/ {
            n = after_colon($0, v); if (n >= 1) a0=v[1]; if (n >= 2) a1=v[2]; next
        }
        /per antenna average rssi of rx data frames:/ {
            n = after_colon($0, v); if (n >= 1) av0=v[1]; if (n >= 2) av1=v[2]; next
        }
        /rate of last tx pkt:/ { n=after_colon($0,v); if(n>=1) txrate=v[1]; next }
        /rate of last rx pkt:/ { n=after_colon($0,v); if(n>=1) rxrate=v[1]; next }
        /tx data pkts:/ { n=after_colon($0,v); if(n>=1) txpkts=v[1]; next }
        /tx data bytes:/ { n=after_colon($0,v); if(n>=1) txbytes=v[1]; next }
        /rx data pkts:/ { n=after_colon($0,v); if(n>=1) rxpkts=v[1]; next }
        /rx data bytes:/ { n=after_colon($0,v); if(n>=1) rxbytes=v[1]; next }
        /tx failures:/ { n=after_colon($0,v); if(n>=1) stafail=v[1]; next }
        /tx data pkts retried:/ { n=after_colon($0,v); if(n>=1) staretry=v[1]; next }
        /tx data pkts retry exhausted:/ { n=after_colon($0,v); if(n>=1) staexhaust=v[1]; next }
        END {
            if(a0=="")a0="NA"; if(a1=="")a1="NA"; if(av0=="")av0="NA"; if(av1=="")av1="NA";
            if(txrate=="")txrate="NA"; if(rxrate=="")rxrate="NA";
            if(txpkts=="")txpkts="NA"; if(rxpkts=="")rxpkts="NA"; if(stafail=="")stafail="NA";
            if(txbytes=="")txbytes="NA"; if(rxbytes=="")rxbytes="NA";
            if(staretry=="")staretry="NA"; if(staexhaust=="")staexhaust="NA";
            printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", \
                a0,a1,av0,av1,txrate,rxrate,txpkts,rxpkts,stafail,txbytes,rxbytes,staretry,staexhaust
        }
    '
}

counter_value()
{
    _counter_name="$1"
    awk -v wanted="$_counter_name" '
        {
            for (i = 1; i < NF; i++) {
                if ($i == wanted) {
                    value = $(i + 1)
                    gsub(/[^0-9]/, "", value)
                    if (value != "") print value
                    exit
                }
            }
        }
    '
}

counter_delta()
{
    if ! is_unsigned "$1" || ! is_unsigned "$2"; then
        printf '%s' "0"
    elif [ "$1" -ge "$2" ]; then
        printf '%s' $(($1 - $2))
    else
        printf '%s' "$1"
    fi
}

nvm_get()
{
    _nvm_key="$1"
    _nvm_file="${2:-$ACTIVE_NVM}"
    [ -f "$_nvm_file" ] || return
    awk -F= -v wanted="$_nvm_key" '
        $1 == wanted {
            sub(/^[^=]*=/, "")
            sub(/[\r\n]+$/, "")
            print
            exit
        }
    ' "$_nvm_file"
}

runtime_nvm_get()
{
    _runtime_key="$1"
    printf '%s\n' "$RUNTIME_NVRAM" | awk -F= -v wanted="$_runtime_key" '
        $1 == wanted { sub(/^[^=]*=/, ""); print; exit }
    '
}

file_digest()
{
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" 2>/dev/null | awk '{print $1}'
    else
        cksum "$1" 2>/dev/null | awk '{print $1 ":" $2}'
    fi
}

radio_static_refresh()
{
    RADIO_SSID="$(wl ssid 2>/dev/null | tr '\r\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')"
    RADIO_CHANNEL="$(wl channel 2>/dev/null | tr '\r\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')"
    RADIO_CHANSPEC="$(wl chanspec 2>/dev/null | tr '\r\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')"
    RADIO_COUNTRY="$(wl country 2>/dev/null | tr '\r\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')"
    RADIO_NRATE="$(wl nrate 2>/dev/null | tr '\r\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')"
    RADIO_QTXPOWER="$(wl qtxpower 2>/dev/null | tr '\r\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')"
    RADIO_TXINSTPWR="$(wl txinstpwr 2>/dev/null | tr '\r\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')"
    RUNTIME_NVRAM="$(wl nvram_dump 2>/dev/null)"
}

print_header()
{
    printf '%s%s+------------------------------------------------------------------------------+%s\n' "$BOLD" "$CYAN" "$RESET"
    printf '%s%s| PARROT RF LAB %-10s | %-16s | %-20s |%s\n' "$BOLD" "$CYAN" "$VERSION" "$DEVICE_LABEL" "$ROLE_LABEL" "$RESET"
    printf '%s%s+------------------------------------------------------------------------------+%s\n' "$BOLD" "$CYAN" "$RESET"
}

show_nvm_summary()
{
    _summary_file="${1:-$ACTIVE_NVM}"
    _epa="$(nvm_get epagain2g "$_summary_file")"
    _pd="$(nvm_get pdgain2g "$_summary_file")"
    _m0="$(nvm_get maxp2ga0 "$_summary_file")"
    _m1="$(nvm_get maxp2ga1 "$_summary_file")"
    _fem="$(nvm_get femctrl "$_summary_file")"
    printf '  2.4 GHz: epagain=%-4s pdgain=%-4s maxp A0/A1=%s/%s (decoded %s/%s dBm) femctrl=%s\n' \
        "${_epa:---}" "${_pd:---}" "${_m0:---}" "${_m1:---}" \
        "$(qdbm_value "$_m0")" "$(qdbm_value "$_m1")" "${_fem:---}"
    if [ "$_pd" = "16" ] && { [ "$_m0" = "90" ] || [ "$_m1" = "90" ]; }; then
        printf '  %sKNOWN-BAD COMBINATION: PD16/MAXP90 produced about -70 dBm at 5 m.%s\n' "$RED" "$RESET"
    fi
}

sample_link()
{
    discover_peer
    if [ -z "$PEER_MAC" ]; then
        return 1
    fi

    STA_INFO="$(wl sta_info "$PEER_MAC" 2>/dev/null)"
    [ -n "$STA_INFO" ] || return 1
    PARSED="$(printf '%s\n' "$STA_INFO" | parse_sta_info)"
    OLD_IFS="$IFS"; IFS='|'; set -- $PARSED; IFS="$OLD_IFS"
    A0="$1"; A1="$2"; A0_AVG="$3"; A1_AVG="$4"; TX_RATE_KBPS="$5"; RX_RATE_KBPS="$6"
    STA_TX_PKTS="$7"; STA_RX_PKTS="$8"; STA_TX_FAIL="$9"
    STA_TX_BYTES="${10}"; STA_RX_BYTES="${11}"; STA_TX_RETRY="${12}"; STA_TX_EXHAUST="${13}"
    [ "$A0" = "NA" ] && A0=""
    [ "$A1" = "NA" ] && A1=""
    [ "$A0_AVG" = "NA" ] && A0_AVG=""
    [ "$A1_AVG" = "NA" ] && A1_AVG=""
    [ "$TX_RATE_KBPS" = "NA" ] && TX_RATE_KBPS=""
    [ "$RX_RATE_KBPS" = "NA" ] && RX_RATE_KBPS=""
    [ "$STA_TX_PKTS" = "NA" ] && STA_TX_PKTS=""
    [ "$STA_RX_PKTS" = "NA" ] && STA_RX_PKTS=""
    [ "$STA_TX_FAIL" = "NA" ] && STA_TX_FAIL=""
    [ "$STA_TX_BYTES" = "NA" ] && STA_TX_BYTES=""
    [ "$STA_RX_BYTES" = "NA" ] && STA_RX_BYTES=""
    [ "$STA_TX_RETRY" = "NA" ] && STA_TX_RETRY=""
    [ "$STA_TX_EXHAUST" = "NA" ] && STA_TX_EXHAUST=""

    SIGNAL="$(average_two "$A0" "$A1")"
    NOISE="$(wl noise 2>/dev/null | first_integer)"
    if [ "$DEVICE" = "bebop2" ]; then
        DRIVER_RSSI="$(wl rssi "$PEER_MAC" 2>/dev/null | first_integer)"
    else
        DRIVER_RSSI="$(wl rssi 2>/dev/null | first_integer)"
    fi
    [ -n "$DRIVER_RSSI" ] || DRIVER_RSSI="$SIGNAL"
    if is_integer "$SIGNAL" && is_integer "$NOISE"; then
        SNR=$((SIGNAL - NOISE))
    else
        SNR=""
    fi

    COUNTERS="$(wl counters 2>/dev/null)"
    C_TXFRAME="$(printf '%s\n' "$COUNTERS" | counter_value txframe)"
    C_RXFRAME="$(printf '%s\n' "$COUNTERS" | counter_value rxframe)"
    C_TXBYTE="$(printf '%s\n' "$COUNTERS" | counter_value txbyte)"
    C_RXBYTE="$(printf '%s\n' "$COUNTERS" | counter_value rxbyte)"
    C_TXRETRANS="$(printf '%s\n' "$COUNTERS" | counter_value txretrans)"
    C_TXERROR="$(printf '%s\n' "$COUNTERS" | counter_value txerror)"
    C_RXERROR="$(printf '%s\n' "$COUNTERS" | counter_value rxerror)"
    C_TXFAIL="$(printf '%s\n' "$COUNTERS" | counter_value txfail)"
    C_RXCRC="$(printf '%s\n' "$COUNTERS" | counter_value rxcrc)"
    C_RXBADFCS="$(printf '%s\n' "$COUNTERS" | counter_value rxbadfcs)"
    [ -n "$C_TXFAIL" ] || C_TXFAIL="$STA_TX_FAIL"
    return 0
}

prepare_log()
{
    _log_label="$1"
    _log_label="$(printf '%s' "$_log_label" | tr -c 'A-Za-z0-9_.-' '_')"
    [ -n "$_log_label" ] || _log_label="experiment"
    mkdir -p "$LOG_DIR" 2>/dev/null || return 1
    _log_stamp="$(date '+%Y%m%d-%H%M%S')"
    LOGFILE="${LOG_DIR}/${DEVICE}-${_log_stamp}-${_log_label}.csv"
    printf '%s\n' 'timestamp,device,rx_direction,peer_mac,peer_ip,a0_dbm,a1_dbm,a0_avg_dbm,a1_avg_dbm,signal_dbm,driver_rssi_dbm,noise_dbm,snr_db,last_tx_rate_mbps,last_rx_rate_mbps,actual_tx_mbps,actual_rx_mbps,peer_txfail_total,peer_txfail_delta,peer_retry_delta,peer_retry_exhausted_delta,driver_txfail_total,driver_txfail_delta,driver_txretrans_delta,driver_txerror_delta,driver_rxerror_delta,driver_rxcrc_delta,driver_rxbadfcs_delta,epagain2g,pdgain2g,maxp2ga0,maxp2ga1,femctrl,runtime_epagain2g,runtime_pdgain2g,runtime_maxp2ga0,runtime_maxp2ga1,label' > "$LOGFILE" || return 1
    LOG_LABEL="$_log_label"
    return 0
}

append_log()
{
    [ -n "${LOGFILE:-}" ] || return
    _log_epa="$(nvm_get epagain2g)"
    _log_pd="$(nvm_get pdgain2g)"
    _log_m0="$(nvm_get maxp2ga0)"
    _log_m1="$(nvm_get maxp2ga1)"
    _log_fem="$(nvm_get femctrl)"
    _log_rt_epa="$(runtime_nvm_get epagain2g)"; _log_rt_pd="$(runtime_nvm_get pdgain2g)"
    _log_rt_m0="$(runtime_nvm_get maxp2ga0)"; _log_rt_m1="$(runtime_nvm_get maxp2ga1)"
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$DEVICE" "$RX_DIRECTION" "$PEER_MAC" "${PEER_IP:---}" \
        "${A0:---}" "${A1:---}" "${A0_AVG:---}" "${A1_AVG:---}" "${SIGNAL:---}" "${DRIVER_RSSI:---}" "${NOISE:---}" "${SNR:---}" \
        "$(format_rate "$TX_RATE_KBPS")" "$(format_rate "$RX_RATE_KBPS")" "$TX_MBPS" "$RX_MBPS" \
        "${STA_TX_FAIL:---}" "$D_STA_TXFAIL" "$D_STA_TXRETRY" "$D_STA_TXEXHAUST" \
        "${C_TXFAIL:---}" "$D_TXFAIL" "$D_TXRETRANS" "$D_TXERROR" "$D_RXERROR" "$D_RXCRC" "$D_RXBADFCS" \
        "${_log_epa:---}" "${_log_pd:---}" "${_log_m0:---}" "${_log_m1:---}" "${_log_fem:---}" \
        "${_log_rt_epa:---}" "${_log_rt_pd:---}" "${_log_rt_m0:---}" "${_log_rt_m1:---}" "$LOG_LABEL" >> "$LOGFILE"
}

monitor_collect_display_config()
{
    MON_FILE_EPA="$(nvm_get epagain2g)"; MON_FILE_PD="$(nvm_get pdgain2g)"
    MON_FILE_M0="$(nvm_get maxp2ga0)"; MON_FILE_M1="$(nvm_get maxp2ga1)"
    MON_FILE_FEM="$(nvm_get femctrl)"
    MON_RT_EPA="$(runtime_nvm_get epagain2g)"; MON_RT_PD="$(runtime_nvm_get pdgain2g)"
    MON_RT_M0="$(runtime_nvm_get maxp2ga0)"; MON_RT_M1="$(runtime_nvm_get maxp2ga1)"
    MON_STATUS=""
    [ -z "$MON_RT_EPA" ] || [ "$MON_RT_EPA" = "$MON_FILE_EPA" ] || MON_STATUS="FILE/RUNTIME MISMATCH - reboot before evaluating"
    [ -z "$MON_RT_PD" ] || [ "$MON_RT_PD" = "$MON_FILE_PD" ] || MON_STATUS="FILE/RUNTIME MISMATCH - reboot before evaluating"
    [ -z "$MON_RT_M0" ] || [ "$MON_RT_M0" = "$MON_FILE_M0" ] || MON_STATUS="FILE/RUNTIME MISMATCH - reboot before evaluating"
    [ -z "$MON_RT_M1" ] || [ "$MON_RT_M1" = "$MON_FILE_M1" ] || MON_STATUS="FILE/RUNTIME MISMATCH - reboot before evaluating"
    if [ "$MON_FILE_PD" = "16" ] && { [ "$MON_FILE_M0" = "90" ] || [ "$MON_FILE_M1" = "90" ]; }; then
        MON_STATUS="KNOWN-BAD PD16/MAXP90 profile - about -70 dBm at 5 m"
    fi
    MON_LOG_NAME="${LOGFILE##*/}"
    [ -n "$MON_LOG_NAME" ] || MON_LOG_NAME="--"
}

monitor_print_peer()
{
    printf '  Peer: %s%-17s%s  IP: %-15s  Sample: %-7s\n' "$BLUE" "$PEER_MAC" "$RESET" "${PEER_IP:---}" "$SAMPLE_NO"
}

monitor_print_radio()
{
    printf '  SSID: %-31s  Channel: %s\n' "${RADIO_SSID:---}" "${RADIO_CHANSPEC:-${RADIO_CHANNEL:---}}"
}

monitor_print_a0()
{
    printf '  A0  '; signal_bar "$A0" 30; printf '  '; paint_signal "$A0" "$(printf '%4s dBm' "${A0:---}")"; printf '  avg %4s\n' "${A0_AVG:---}"
}

monitor_print_a1()
{
    printf '  A1  '; signal_bar "$A1" 30; printf '  '; paint_signal "$A1" "$(printf '%4s dBm' "${A1:---}")"; printf '  avg %4s\n' "${A1_AVG:---}"
}

monitor_print_average()
{
    printf '  AVG '; signal_bar "$SIGNAL" 30; printf '  '; paint_signal "$SIGNAL" "$(printf '%4s dBm' "${SIGNAL:---}")"; printf '\n'
}

monitor_print_rssi()
{
    printf '  Driver RSSI: '; paint_signal "$DRIVER_RSSI" "$(printf '%4s dBm' "${DRIVER_RSSI:---}")"
    printf '   Noise: %4s dBm   SNR: %3s dB\n' "${NOISE:---}" "${SNR:---}"
}

monitor_print_rates()
{
    printf '  Last frame rates   TX: %6s Mbps   RX: %6s Mbps  %s(not throughput)%s\n' \
        "$(format_rate "$TX_RATE_KBPS")" "$(format_rate "$RX_RATE_KBPS")" "$DIM" "$RESET"
}

monitor_print_traffic()
{
    printf '  Actual traffic     TX: %6s Mbps   RX: %6s Mbps  over %ss\n' "$TX_MBPS" "$RX_MBPS" "$INTERVAL"
}

monitor_print_peer_errors()
{
    printf '  Peer deltas        TX fail: %-5s retries: %-6s exhausted: %-5s\n' \
        "$D_STA_TXFAIL" "$D_STA_TXRETRY" "$D_STA_TXEXHAUST"
}

monitor_print_driver_errors()
{
    printf '  Driver deltas      TX fail: %-5s retrans: %-6s TX/RX err: %s/%s\n' \
        "$D_TXFAIL" "$D_TXRETRANS" "$D_TXERROR" "$D_RXERROR"
}

monitor_print_rx_errors()
{
    printf '                     RX CRC: %-6s bad FCS: %-6s\n' "$D_RXCRC" "$D_RXBADFCS"
}

monitor_print_file_config()
{
    printf '  File: epa=%-3s pd=%-3s maxp=%s/%s (%s/%s dBm) fem=%s\n' \
        "${MON_FILE_EPA:---}" "${MON_FILE_PD:---}" "${MON_FILE_M0:---}" "${MON_FILE_M1:---}" \
        "$(qdbm_value "$MON_FILE_M0")" "$(qdbm_value "$MON_FILE_M1")" "${MON_FILE_FEM:---}"
}

monitor_print_runtime_config()
{
    printf '  Runtime: epa=%-3s pd=%-3s maxp=%s/%s\n' \
        "${MON_RT_EPA:---}" "${MON_RT_PD:---}" "${MON_RT_M0:---}" "${MON_RT_M1:---}"
}

monitor_print_status()
{
    if [ -n "$MON_STATUS" ]; then
        printf '  %s%s%s\n' "$YELLOW" "$MON_STATUS" "$RESET"
    else
        printf '\n'
    fi
}

monitor_print_qtxpower()
{
    printf '  qtxpower: %s  %s(driver request/ceiling)%s\n' "${RADIO_QTXPOWER:---}" "$DIM" "$RESET"
}

monitor_print_txinstpwr()
{
    printf '  txinstpwr: %s  %s(driver estimate)%s\n' "${RADIO_TXINSTPWR:---}" "$DIM" "$RESET"
}

monitor_print_log()
{
    printf '  CSV: %s\n' "$MON_LOG_NAME"
}

monitor_separator()
{
    printf '%s+------------------------------------------------------------------------------+%s\n' "$DIM" "$RESET"
}

monitor_draw_full()
{
    clear_screen
    print_header
    printf '  RX direction: %s%s%s\n' "$BOLD" "$RX_DIRECTION" "$RESET"
    monitor_print_peer
    monitor_print_radio
    monitor_separator
    monitor_print_a0
    monitor_print_a1
    monitor_print_average
    printf '\n'
    monitor_print_rssi
    monitor_separator
    monitor_print_rates
    monitor_print_traffic
    monitor_print_peer_errors
    monitor_print_driver_errors
    monitor_print_rx_errors
    monitor_separator
    printf '  Active NVM file and driver runtime:\n'
    monitor_print_file_config
    monitor_print_runtime_config
    monitor_print_status
    monitor_print_qtxpower
    monitor_print_txinstpwr
    monitor_print_log
    monitor_separator
    printf '  %sq%s menu   %sr%s refresh radio metadata   Ctrl+C exits\n' "$CYAN" "$RESET" "$CYAN" "$RESET"
}

monitor_move_to_row()
{
    printf '%s[%s;1H%s[2K' "$ESC" "$1" "$ESC"
}

monitor_update_in_place()
{
    monitor_move_to_row 5; monitor_print_peer
    monitor_move_to_row 8; monitor_print_a0
    monitor_move_to_row 9; monitor_print_a1
    monitor_move_to_row 10; monitor_print_average
    monitor_move_to_row 12; monitor_print_rssi
    monitor_move_to_row 14; monitor_print_rates
    monitor_move_to_row 15; monitor_print_traffic
    monitor_move_to_row 16; monitor_print_peer_errors
    monitor_move_to_row 17; monitor_print_driver_errors
    monitor_move_to_row 18; monitor_print_rx_errors
    printf '%s[28;79H' "$ESC"
}

monitor_mode()
{
    _monitor_label="${1:-}"
    LOGFILE=""
    LOG_LABEL=""
    if [ -n "$_monitor_label" ]; then
        if ! prepare_log "$_monitor_label"; then
            printf '%sUnable to create CSV under %s%s\n' "$RED" "$LOG_DIR" "$RESET" >&2
            return 1
        fi
    fi

    MONITOR_IN_PLACE=0
    if [ -t 1 ] && [ "$NO_CLEAR" != "1" ]; then
        MONITOR_IN_PLACE=1
        CURSOR_HIDDEN=1
        printf '%s[?25l' "$ESC"
    fi

    radio_static_refresh
    PREV_TXBYTE=""; PREV_RXBYTE=""; PREV_TXFAIL=""; PREV_TXRETRANS=""
    PREV_STA_TXFAIL=""; PREV_STA_TXRETRY=""; PREV_STA_TXEXHAUST=""
    PREV_TXERROR=""; PREV_RXERROR=""; PREV_RXCRC=""; PREV_RXBADFCS=""
    SAMPLE_NO=0
    MONITOR_FRAME_DRAWN=0
    MONITOR_WAIT_DRAWN=0

    while :; do
        if ! sample_link; then
            if [ "$MONITOR_WAIT_DRAWN" -eq 0 ]; then
                clear_screen
                print_header
                printf '\n  %sWaiting for Wi-Fi peer...%s\n' "$RED" "$RESET"
                printf '  q: return to menu   Ctrl+C: exit\n'
                MONITOR_WAIT_DRAWN=1
                MONITOR_FRAME_DRAWN=0
            fi
            _wait_key=""
            if [ -t 0 ]; then
                IFS= read -r -s -t "$INTERVAL" -n 1 _wait_key
            else
                sleep "$INTERVAL"
            fi
            [ "$_wait_key" = "q" ] && break
            continue
        fi
        MONITOR_WAIT_DRAWN=0

        LINK_TXBYTE="${STA_TX_BYTES:-$C_TXBYTE}"
        LINK_RXBYTE="${STA_RX_BYTES:-$C_RXBYTE}"
        D_TXBYTE="$(counter_delta "$LINK_TXBYTE" "$PREV_TXBYTE")"
        D_RXBYTE="$(counter_delta "$LINK_RXBYTE" "$PREV_RXBYTE")"
        D_TXFAIL="$(counter_delta "$C_TXFAIL" "$PREV_TXFAIL")"
        D_TXRETRANS="$(counter_delta "$C_TXRETRANS" "$PREV_TXRETRANS")"
        D_STA_TXFAIL="$(counter_delta "$STA_TX_FAIL" "$PREV_STA_TXFAIL")"
        D_STA_TXRETRY="$(counter_delta "$STA_TX_RETRY" "$PREV_STA_TXRETRY")"
        D_STA_TXEXHAUST="$(counter_delta "$STA_TX_EXHAUST" "$PREV_STA_TXEXHAUST")"
        D_TXERROR="$(counter_delta "$C_TXERROR" "$PREV_TXERROR")"
        D_RXERROR="$(counter_delta "$C_RXERROR" "$PREV_RXERROR")"
        D_RXCRC="$(counter_delta "$C_RXCRC" "$PREV_RXCRC")"
        D_RXBADFCS="$(counter_delta "$C_RXBADFCS" "$PREV_RXBADFCS")"
        TX_MBPS="$(format_mbps_from_bytes "$D_TXBYTE" "$INTERVAL")"
        RX_MBPS="$(format_mbps_from_bytes "$D_RXBYTE" "$INTERVAL")"
        PREV_TXBYTE="$LINK_TXBYTE"; PREV_RXBYTE="$LINK_RXBYTE"; PREV_TXFAIL="$C_TXFAIL"
        PREV_TXRETRANS="$C_TXRETRANS"; PREV_TXERROR="$C_TXERROR"; PREV_RXERROR="$C_RXERROR"
        PREV_RXCRC="$C_RXCRC"; PREV_RXBADFCS="$C_RXBADFCS"
        PREV_STA_TXFAIL="$STA_TX_FAIL"; PREV_STA_TXRETRY="$STA_TX_RETRY"; PREV_STA_TXEXHAUST="$STA_TX_EXHAUST"
        SAMPLE_NO=$((SAMPLE_NO + 1))

        append_log
        monitor_collect_display_config
        if [ "$MONITOR_IN_PLACE" -eq 1 ] && [ "$MONITOR_FRAME_DRAWN" -eq 1 ]; then
            monitor_update_in_place
        else
            monitor_draw_full
            MONITOR_FRAME_DRAWN=1
        fi

        _monitor_key=""
        if [ -t 0 ]; then
            IFS= read -r -s -t "$INTERVAL" -n 1 _monitor_key
        else
            sleep "$INTERVAL"
        fi
        case "$_monitor_key" in
            q|Q) break ;;
            r|R) radio_static_refresh; MONITOR_FRAME_DRAWN=0 ;;
        esac
    done

    if [ "$CURSOR_HIDDEN" -eq 1 ]; then
        printf '%s[?25h' "$ESC"
        CURSOR_HIDDEN=0
    fi
    return 0
}

snapshot()
{
    clear_screen
    print_header
    discover_peer
    printf '\n%sDevice%s\n' "$BOLD" "$RESET"
    printf '  Model:       %s\n' "$DEVICE_LABEL"
    printf '  Role:        %s\n' "$ROLE_LABEL"
    printf '  RX direction:%s\n' " $RX_DIRECTION"
    printf '  Peer MAC/IP: %s / %s\n' "${PEER_MAC:---}" "${PEER_IP:---}"
    printf '  Active NVM:  %s\n' "$ACTIVE_NVM"
    printf '  Digest:      %s\n' "$(file_digest "$ACTIVE_NVM")"
    [ ! -f "$FACTORY_NVM" ] || printf '  Factory NVM: %s (%s)\n' "$FACTORY_NVM" "$(file_digest "$FACTORY_NVM")"
    printf '\n%sNVM summary%s\n' "$BOLD" "$RESET"
    show_nvm_summary "$ACTIVE_NVM"

    for _snap_cmd in ver revinfo status channel chanspec country qtxpower txchain rxchain nrate rate rateset mpc interference noise phy_rssi_ant txinstpwr; do
        printf '\n%s[%s]%s\n' "$CYAN" "$_snap_cmd" "$RESET"
        wl "$_snap_cmd" 2>&1 | sed 's/^/  /'
    done
    if [ -n "$PEER_MAC" ]; then
        printf '\n%s[sta_info %s]%s\n' "$CYAN" "$PEER_MAC" "$RESET"
        wl sta_info "$PEER_MAC" 2>&1 | sed 's/^/  /'
    fi
    printf '\n%s[counters: selected]%s\n' "$CYAN" "$RESET"
    wl counters 2>&1 | awk '
        {
            wanted=""
            for(i=1;i<NF;i++) {
                if($i ~ /^(txframe|txbyte|txretrans|txerror|txfail|rxframe|rxbyte|rxerror|rxcrc|rxbadfcs|rxbadplcp)$/) {
                    printf "  %-12s %s\n", $i, $(i+1)
                }
            }
        }
    '
}

export_snapshot()
{
    mkdir -p "$LOG_DIR" 2>/dev/null || {
        printf '%sCould not create %s%s\n' "$RED" "$LOG_DIR" "$RESET"
        return 1
    }
    _snapshot_path="${LOG_DIR}/${DEVICE}-snapshot-$(date '+%Y%m%d-%H%M%S').txt"
    (
        NO_COLOR=1; NO_CLEAR=1
        RESET=""; BOLD=""; DIM=""; CYAN=""; GREEN=""; YELLOW=""; RED=""; BLUE=""; WHITE=""
        snapshot
    ) > "$_snapshot_path" 2>&1
    printf '%sSnapshot saved:%s %s\n' "$GREEN" "$RESET" "$_snapshot_path"
}

validate_key_value()
{
    case "$1" in
        ""|*[!A-Za-z0-9_]*) return 1 ;;
    esac
    case "$2" in
        ""|*"="*|*"#"*|*[!A-Za-z0-9_,.:+-]*) return 1 ;;
    esac
    return 0
}

nvm_set()
{
    _set_file="$1"; _set_key="$2"; _set_value="$3"
    validate_key_value "$_set_key" "$_set_value" || return 1
    _set_count="$(grep -c "^${_set_key}=" "$_set_file" 2>/dev/null)"
    [ "$_set_count" = "1" ] || return 2
    awk -v wanted="$_set_key" -v replacement="$_set_value" '
        index($0, wanted "=") == 1 { print wanted "=" replacement; next }
        { print }
    ' "$_set_file" > "${_set_file}.new" || return 1
    mv "${_set_file}.new" "$_set_file" || return 1
    return 0
}

validate_stage()
{
    [ -s "$STAGE_FILE" ] || return 1
    for _identity_key in sromrev boardtype vendid devid boardrev macaddr; do
        [ "$(nvm_get "$_identity_key" "$ACTIVE_NVM")" = "$(nvm_get "$_identity_key" "$STAGE_FILE")" ] || {
            printf '%sIdentity field changed unexpectedly: %s%s\n' "$RED" "$_identity_key" "$RESET" >&2
            return 1
        }
    done
    for _required_key in epagain2g pdgain2g maxp2ga0 maxp2ga1 femctrl; do
        [ "$(grep -c "^${_required_key}=" "$STAGE_FILE" 2>/dev/null)" = "1" ] || {
            printf '%sRequired key missing or duplicated: %s%s\n' "$RED" "$_required_key" "$RESET" >&2
            return 1
        }
    done
    return 0
}

show_stage_diff()
{
    if cmp -s "$ACTIVE_NVM" "$STAGE_FILE"; then
        printf '  %sNo staged changes.%s\n' "$DIM" "$RESET"
    else
        diff -u "$ACTIVE_NVM" "$STAGE_FILE" 2>/dev/null | sed -n '/^@@/,$p' | sed -n '1,160p'
    fi
}

stage_preset()
{
    _preset="$1"
    case "$_preset" in
        stock)
            _p_epa=0; _p_pd=7
            if [ "$DEVICE" = "bebop2" ]; then _p_m0=76; _p_m1=76; else _p_m0=80; _p_m1=80; fi
            ;;
        epa2_pd7)
            _p_epa=2; _p_pd=7
            if [ "$DEVICE" = "bebop2" ]; then _p_m0=76; _p_m1=76; else _p_m0=80; _p_m1=80; fi
            ;;
        epa2_pd14_m80)
            _p_epa=2; _p_pd=14; _p_m0=80; _p_m1=80
            ;;
        epa2_pd16_m80)
            _p_epa=2; _p_pd=16; _p_m0=80; _p_m1=80
            ;;
        *) return 1 ;;
    esac
    nvm_set "$STAGE_FILE" epagain2g "$_p_epa" || return 1
    nvm_set "$STAGE_FILE" pdgain2g "$_p_pd" || return 1
    nvm_set "$STAGE_FILE" maxp2ga0 "$_p_m0" || return 1
    nvm_set "$STAGE_FILE" maxp2ga1 "$_p_m1" || return 1
    return 0
}

root_rw()
{
    mount -o remount,rw / >/dev/null 2>&1 || mount -o rw,remount / >/dev/null 2>&1
}

root_is_rw()
{
    mount 2>/dev/null | awk '$3 == "/" && $0 ~ /\(rw[,)]/ { found=1 } END { exit(found ? 0 : 1) }'
}

root_ro()
{
    mount -o remount,ro / >/dev/null 2>&1 || mount -o ro,remount / >/dev/null 2>&1
}

apply_stage()
{
    if cmp -s "$ACTIVE_NVM" "$STAGE_FILE"; then
        printf '%sNothing to apply.%s\n' "$YELLOW" "$RESET"
        return 0
    fi
    validate_stage || return 1
    printf '\n%sPending changes:%s\n' "$BOLD" "$RESET"
    show_stage_diff
    printf '\n%sThis edits only the active filesystem NVM. Factory/OTP data is never touched.%s\n' "$YELLOW" "$RESET"
    printf 'Type %sAPPLY%s to create a recovery backup and write the file: ' "$BOLD" "$RESET"
    IFS= read -r _apply_answer
    [ "$_apply_answer" = "APPLY" ] || {
        printf 'Cancelled.\n'
        return 0
    }

    mkdir -p "$BACKUP_DIR" 2>/dev/null || {
        printf '%sCannot create backup directory: %s%s\n' "$RED" "$BACKUP_DIR" "$RESET"
        return 1
    }
    _backup_path="${BACKUP_DIR}/${DEVICE}-bcm43526-$(date '+%Y%m%d-%H%M%S')-$(file_digest "$ACTIVE_NVM").nvm"
    cp -p "$ACTIVE_NVM" "$_backup_path" 2>/dev/null || cp "$ACTIVE_NVM" "$_backup_path" || {
        printf '%sBackup failed; active NVM was not touched.%s\n' "$RED" "$RESET"
        return 1
    }

    _root_was_rw=0
    root_is_rw && _root_was_rw=1
    if [ "$_root_was_rw" -eq 0 ] && ! root_rw; then
        printf '%sCould not remount / read-write. Backup remains at %s%s\n' "$RED" "$_backup_path" "$RESET"
        return 1
    fi
    if cp "$STAGE_FILE" "$ACTIVE_NVM" && sync && cmp -s "$STAGE_FILE" "$ACTIVE_NVM"; then
        [ "$_root_was_rw" -eq 1 ] || root_ro
        printf '%sNVM updated successfully.%s\n' "$GREEN" "$RESET"
        printf 'Backup: %s\n' "$_backup_path"
        printf '%sA reboot is required before the Broadcom runtime uses these values.%s\n' "$YELLOW" "$RESET"
        cp "$ACTIVE_NVM" "$STAGE_FILE"
        return 0
    fi

    printf '%sWrite verification failed; restoring the backup.%s\n' "$RED" "$RESET"
    if cp "$_backup_path" "$ACTIVE_NVM" 2>/dev/null && sync && cmp -s "$_backup_path" "$ACTIVE_NVM"; then
        printf '%sOriginal NVM restored and verified.%s\n' "$GREEN" "$RESET"
    else
        printf '%sCRITICAL: automatic restore could not be verified. Use this backup before rebooting: %s%s\n' \
            "$RED" "$_backup_path" "$RESET"
    fi
    [ "$_root_was_rw" -eq 1 ] || root_ro
    return 1
}

choose_backup_to_stage()
{
    _backup_list="$(ls -1t "$BACKUP_DIR"/*.nvm 2>/dev/null)"
    if [ -z "$_backup_list" ]; then
        printf '%sNo backups found under %s%s\n' "$YELLOW" "$BACKUP_DIR" "$RESET"
        return
    fi
    printf '%s\n' "$_backup_list" | awk '{printf "  %2d) %s\n", NR, $0}'
    printf 'Select a backup number, or Enter to cancel: '
    IFS= read -r _backup_number
    [ -n "$_backup_number" ] || return
    is_unsigned "$_backup_number" || return
    _chosen_backup="$(printf '%s\n' "$_backup_list" | sed -n "${_backup_number}p")"
    [ -f "$_chosen_backup" ] || {
        printf '%sInvalid selection.%s\n' "$RED" "$RESET"
        return
    }
    cp "$_chosen_backup" "$STAGE_FILE" || return
    if validate_stage; then
        printf '%sBackup staged for review. Use Apply when ready.%s\n' "$GREEN" "$RESET"
    else
        printf '%sBackup failed validation; resetting stage.%s\n' "$RED" "$RESET"
        cp "$ACTIVE_NVM" "$STAGE_FILE"
    fi
}

advanced_edit()
{
    printf '\n%sRF-related keys in the staged file:%s\n' "$BOLD" "$RESET"
    grep -n -E '^(epagain|pdgain|maxp|pa[25]g|femctrl|tssipos|tworangetssi|papdcap|pdoffset|mcs.*po|.*bw.*po|rxgains|noiselvl|rxgainerr|ag[ab]|sar|ccode|regrev)' "$STAGE_FILE" | sed -n '1,220p'
    printf '\nExisting key to edit (Enter cancels): '
    IFS= read -r _edit_key
    [ -n "$_edit_key" ] || return
    _old_value="$(nvm_get "$_edit_key" "$STAGE_FILE")"
    if [ -z "$_old_value" ]; then
        printf '%sKey not found or empty.%s\n' "$RED" "$RESET"
        return
    fi
    printf 'Current %s=%s\nNew value: ' "$_edit_key" "$_old_value"
    IFS= read -r _edit_value
    validate_key_value "$_edit_key" "$_edit_value" || {
        printf '%sInvalid key/value syntax.%s\n' "$RED" "$RESET"
        return
    }
    case "$_edit_key" in
        sromrev|boardtype|boardrev|boardflags*|macaddr|devid|vendid)
            printf '%sIdentity and board-definition fields are deliberately read-only in this tool.%s\n' "$RED" "$RESET"
            return
            ;;
        ccode|regrev)
            printf '%s%s changes the regulatory profile, not PA calibration.%s\n' "$RED" "$_edit_key" "$RESET"
            printf 'Type REGULATORY to stage it: '
            IFS= read -r _regulatory_answer
            [ "$_regulatory_answer" = "REGULATORY" ] || return
            ;;
        pa*|rxgains*|swctrlmap*|temp*|rawtempsense)
            printf '%s%s is calibration- or hardware-critical.%s\n' "$RED" "$_edit_key" "$RESET"
            printf 'Type CALIBRATION to stage it: '
            IFS= read -r _critical_answer
            [ "$_critical_answer" = "CALIBRATION" ] || return
            ;;
    esac
    if nvm_set "$STAGE_FILE" "$_edit_key" "$_edit_value"; then
        printf '%sStaged: %s=%s%s\n' "$GREEN" "$_edit_key" "$_edit_value" "$RESET"
    else
        printf '%sCould not stage the edit.%s\n' "$RED" "$RESET"
    fi
}

parameter_help()
{
    clear_screen
    print_header
    printf '\n%sParameter map: documented versus empirical%s\n\n' "$BOLD" "$RESET"
    printf '  %-22s %s\n' 'maxp2ga0/maxp2ga1' 'Documented maximum 2.4 GHz power, 0.25 dB units.'
    printf '  %-22s %s\n' '' 'For related chips, nominal CCK target = maxp/4 - 1.5 dB.'
    printf '  %-22s %s\n' 'mcs*/ofdm*/cck*po' 'Per-rate power backoffs, generally 0.5 dB nibbles.'
    printf '  %-22s %s\n' 'pa2ga0/pa2ga1' 'TSSI-derived PA calibration coefficients; do not guess.'
    printf '  %-22s %s\n' 'epagain2g' 'PA topology/mode selector. Value 2 causes the large measured jump.'
    printf '  %-22s %s\n' 'pdgain2g' 'Power-detector/TSSI gain selector; exact BCM43526 encoding unknown.'
    printf '  %-22s %s\n' 'femctrl' 'Selects a built-in FEM control table; not a simple on/off bit.'
    printf '  %-22s %s\n' 'rxgains*' 'RX/eLNA gain-model calibration; not direct enable switches.'
    printf '\n%sCurrent empirical matrix at 5 m%s\n' "$BOLD" "$RESET"
    printf '  %-24s %s\n' 'PD14 / MAXP80' 'about -21/-22 dBm'
    printf '  %-24s %s\n' 'PD16 / MAXP80' 'about -17 dBm'
    printf '  %-24s %s%s%s\n' 'PD16 / MAXP90' "$RED" 'known collapse to about -70 dBm' "$RESET"
    printf '  %-24s %s\n' 'Stock both endpoints' 'about -36.5 and -31.5 dBm directionally'
    printf '\n%sInterpretation%s\n' "$BOLD" "$RESET"
    printf '  maxp is a calibrated ceiling/target input, while pdgain changes the detector\n'
    printf '  model feeding the closed-loop PA control. Their interaction is non-monotonic.\n'
    printf '  Every experiment should log both directions, throughput and error deltas.\n'
    pause_screen
}

config_menu()
{
    if ! root_is_rw; then
        printf '%sThe root filesystem is read-only.%s\n' "$RED" "$RESET"
        printf 'Before using the NVM editor, run: %smount -o remount,rw /%s\n' "$BOLD" "$RESET"
        printf 'After editing, run: %ssync; mount -o remount,ro /%s\n' "$BOLD" "$RESET"
        return 1
    fi
    if [ ! -f "$ACTIVE_NVM" ]; then
        printf '%sActive NVM not found: %s%s\n' "$RED" "$ACTIVE_NVM" "$RESET"
        return 1
    fi
    STAGE_FILE="/tmp/parrot_rf_lab.$$.nvm"
    cp "$ACTIVE_NVM" "$STAGE_FILE" || return 1

    while :; do
        clear_screen
        print_header
        printf '\n%sActive file%s\n  %s\n  digest: %s\n' "$BOLD" "$RESET" "$ACTIVE_NVM" "$(file_digest "$ACTIVE_NVM")"
        show_nvm_summary "$ACTIVE_NVM"
        printf '\n%sStaged file%s\n' "$BOLD" "$RESET"
        show_nvm_summary "$STAGE_FILE"
        printf '\n%sStaged diff%s\n' "$BOLD" "$RESET"
        show_stage_diff
        printf '\n  %s1%s  Stock profile for this device\n' "$CYAN" "$RESET"
        printf '  %s2%s  EPA2 / PD7 / factory MAXP  %s(isolate EPA mode)%s\n' "$CYAN" "$RESET" "$DIM" "$RESET"
        printf '  %s3%s  EPA2 / PD14 / MAXP80       %s(~-21/-22 dBm observed)%s\n' "$CYAN" "$RESET" "$DIM" "$RESET"
        printf '  %s4%s  EPA2 / PD16 / MAXP80       %s(~-17 dBm observed)%s\n' "$CYAN" "$RESET" "$DIM" "$RESET"
        printf '  %s5%s  Advanced existing-key editor\n' "$CYAN" "$RESET"
        printf '  %s6%s  Stage a recovery backup\n' "$CYAN" "$RESET"
        printf '  %s7%s  Reset stage from active file\n' "$CYAN" "$RESET"
        printf '  %sa%s  Apply staged changes with backup\n' "$GREEN" "$RESET"
        printf '  %sh%s  Parameter help and experiment matrix\n' "$CYAN" "$RESET"
        printf '  %sq%s  Return to main menu\n\n' "$CYAN" "$RESET"
        printf 'Choice: '
        IFS= read -r _config_choice
        case "$_config_choice" in
            1) stage_preset stock ;;
            2) stage_preset epa2_pd7 ;;
            3) stage_preset epa2_pd14_m80 ;;
            4) stage_preset epa2_pd16_m80 ;;
            5) advanced_edit; pause_screen ;;
            6) choose_backup_to_stage; pause_screen ;;
            7) cp "$ACTIVE_NVM" "$STAGE_FILE" ;;
            a|A) apply_stage; pause_screen ;;
            h|H) parameter_help ;;
            q|Q) break ;;
        esac
    done
    rm -f "$STAGE_FILE" "${STAGE_FILE}.new"
    STAGE_FILE=""
    printf '\n%sNVM editor closed. Flush writes and restore the normal read-only mount:%s\n' "$YELLOW" "$RESET"
    printf '  sync\n  mount -o remount,ro /\n'
    pause_screen
}

main_menu()
{
    while :; do
        clear_screen
        print_header
        printf '\n  Peer: '
        discover_peer
        if [ -n "$PEER_MAC" ]; then
            printf '%s%s%s (%s)\n' "$GREEN" "$PEER_MAC" "$RESET" "${PEER_IP:---}"
        else
            printf '%snot associated%s\n' "$YELLOW" "$RESET"
        fi
        printf '  Active NVM: %s\n' "$ACTIVE_NVM"
        show_nvm_summary "$ACTIVE_NVM"
        printf '\n  %s1%s  Live RF dashboard\n' "$CYAN" "$RESET"
        printf '  %s2%s  Live dashboard + CSV experiment log\n' "$CYAN" "$RESET"
        printf '  %s3%s  Comprehensive read-only snapshot\n' "$CYAN" "$RESET"
        printf '  %s4%s  Export snapshot to FTP storage\n' "$CYAN" "$RESET"
        printf '  %s5%s  NVM experiment editor / presets / recovery\n' "$CYAN" "$RESET"
        printf '  %s6%s  BCM43526 parameter help\n' "$CYAN" "$RESET"
        printf '  %sq%s  Quit\n\n' "$CYAN" "$RESET"
        printf 'Choice: '
        IFS= read -r _main_choice
        case "$_main_choice" in
            1) monitor_mode ;;
            2)
                printf 'Experiment label (for example stock, pd14_m80, pd16_m80): '
                IFS= read -r _experiment_label
                monitor_mode "$_experiment_label"
                ;;
            3) snapshot; pause_screen ;;
            4) export_snapshot; pause_screen ;;
            5) config_menu ;;
            6) parameter_help ;;
            q|Q) break ;;
        esac
    done
}

self_test()
{
    _test_sta=' tx failures: 7
 tx data pkts: 1200
 tx data bytes: 4800000
 rx data pkts: 2400
 rx data bytes: 9600000
 rate of last tx pkt: 65000 kbps
 rate of last rx pkt: 19500 kbps
 tx data pkts retried: 9
 tx data pkts retry exhausted: 2
 per antenna rssi of last rx data frame: -15 -20 0 0
 per antenna average rssi of rx data frames: -16 -21 0 0
 per antenna noise floor: 0 0 0 0'
    _test_parsed="$(printf '%s\n' "$_test_sta" | parse_sta_info)"
    [ "$_test_parsed" = '-15|-20|-16|-21|65000|19500|1200|2400|7|4800000|9600000|9|2' ] || {
        printf 'sta_info parser failed: %s\n' "$_test_parsed" >&2
        return 1
    }
    [ "$(signal_color_code -60)" = 196 ] || return 1
    [ "$(signal_color_code -40)" = 226 ] || return 1
    [ "$(signal_color_code -20)" = 46 ] || return 1
    [ "$(signal_color_code -5)" = 51 ] || return 1
    [ "$(format_rate 19500)" = 19.5 ] || return 1
    [ "$(qdbm_value 80)" = 20.00 ] || return 1
    is_integer -17 || return 1
    ! is_integer '1-2' || return 1

    _test_nvm="$(mktemp /tmp/parrot-rf-selftest.XXXXXX)" || return 1
    printf '%s\n' \
        'sromrev=11' 'boardtype=0x623' 'vendid=0x14e4' 'devid=0x43a0' \
        'boardrev=0x1452' 'macaddr=00:90:4c:00:00:00' 'epagain2g=0' \
        'pdgain2g=7' 'maxp2ga0=76' 'maxp2ga1=76' 'femctrl=1' > "$_test_nvm"
    nvm_set "$_test_nvm" pdgain2g 16 || { rm -f "$_test_nvm"; return 1; }
    [ "$(nvm_get pdgain2g "$_test_nvm")" = 16 ] || { rm -f "$_test_nvm"; return 1; }
    rm -f "$_test_nvm"
    printf 'Parrot RF Lab self-test passed\n'
    return 0
}

usage()
{
    printf '%s\n' \
        "Parrot RF Lab ${VERSION}" \
        "Usage: $0 [menu|monitor|log LABEL|snapshot|export|config|help|self-test]" \
        "" \
        "Environment:" \
        "  RF_LAB_INTERVAL=N      sample interval in whole seconds (default 1)" \
        "  RF_LAB_PEER=MAC        force peer MAC" \
        "  RF_LAB_DEVICE=auto|bebop2|sc2" \
        "  NO_COLOR=1             disable ANSI color" \
        "  RF_LAB_NO_CLEAR=1      do not clear screen between samples"
}

case "$INTERVAL" in
    ""|*[!0-9]*|0) printf 'RF_LAB_INTERVAL must be a positive whole number.\n' >&2; exit 2 ;;
esac

case "${1:-menu}" in
    self-test|--self-test)
        self_test
        exit $?
        ;;
    -h|--help)
        usage
        exit 0
        ;;
esac

if ! detect_device; then
    printf '%sCould not identify Bebop 2 or SkyController 2.%s\n' "$RED" "$RESET" >&2
    printf 'Set RF_LAB_DEVICE=bebop2 or RF_LAB_DEVICE=sc2 if auto-detection is unavailable.\n' >&2
    exit 1
fi

if [ ! -x "$WL_BIN" ] && [ -z "${RF_LAB_FIXTURE_DIR:-}" ]; then
    printf '%sBroadcom utility not found: %s%s\n' "$RED" "$WL_BIN" "$RESET" >&2
    exit 1
fi

case "${1:-menu}" in
    menu) main_menu ;;
    monitor) monitor_mode ;;
    log) monitor_mode "${2:-experiment}" ;;
    snapshot) snapshot ;;
    export) export_snapshot ;;
    config) config_menu ;;
    help) parameter_help ;;
    *) usage; exit 2 ;;
esac
