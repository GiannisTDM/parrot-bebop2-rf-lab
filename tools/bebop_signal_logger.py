#!/usr/bin/env python3
"""Terminal Wi-Fi signal logger for a Parrot Bebop 2.

The logger connects to the Bebop's root Telnet shell, finds the associated
SkyController, and records read-only Broadcom link statistics to CSV.
It has no third-party Python dependencies.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import re
import secrets
import socket
import statistics
import sys
import time
from pathlib import Path
from typing import Iterable


IAC = 255
DONT = 254
DO = 253
WONT = 252
WILL = 251

MAC_RE = re.compile(r"(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b")
INT_RE = re.compile(r"-?\d+")
PROMPT_RE = re.compile(rb"(?:^|[\r\n])[^\r\n]{0,100}[#$] ?$")

CSV_FIELDS = [
    "timestamp",
    "elapsed_s",
    "label",
    "battery_percent",
    "station_mac",
    "channel",
    "rssi_dbm",
    "noise_dbm",
    "snr_db",
    "a0_last_dbm",
    "a1_last_dbm",
    "a0_average_dbm",
    "a1_average_dbm",
    "a0_noise_dbm",
    "a1_noise_dbm",
    "tx_rate_kbps",
    "rx_rate_kbps",
    "tx_packets",
    "rx_packets",
    "tx_failures_total",
    "tx_failures_delta",
]


class TelnetShell:
    def __init__(self, host: str, port: int, timeout: float = 5.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.sock: socket.socket | None = None

    def connect(self) -> None:
        self.sock = socket.create_connection((self.host, self.port), self.timeout)
        self.sock.settimeout(0.25)
        self._read_until_prompt(8.0)
        # Disable terminal echo for this private session. Otherwise BusyBox
        # echoes the command containing our completion marker and can make a
        # marker-based client mistake the echo for completed command output.
        self.sock.sendall(b"stty -echo\n")
        self._read_until_prompt(5.0)

    def close(self) -> None:
        if self.sock is not None:
            try:
                self.sock.close()
            finally:
                self.sock = None

    def _clean_telnet(self, data: bytes) -> bytes:
        if self.sock is None:
            return data
        clean = bytearray()
        i = 0
        while i < len(data):
            if data[i] != IAC:
                clean.append(data[i])
                i += 1
                continue
            if i + 1 >= len(data):
                break
            command = data[i + 1]
            if command == IAC:
                clean.append(IAC)
                i += 2
            elif command in (DO, DONT, WILL, WONT) and i + 2 < len(data):
                option = data[i + 2]
                reply = WONT if command in (DO, DONT) else DONT
                self.sock.sendall(bytes((IAC, reply, option)))
                i += 3
            else:
                i += 2
        return bytes(clean)

    def _read_until_prompt(self, timeout: float) -> bytes:
        if self.sock is None:
            raise ConnectionError("Telnet socket is not connected")
        deadline = time.monotonic() + timeout
        output = bytearray()
        while time.monotonic() < deadline:
            try:
                block = self.sock.recv(65536)
            except socket.timeout:
                continue
            if not block:
                raise ConnectionError("Bebop closed the Telnet connection")
            output.extend(self._clean_telnet(block))
            if PROMPT_RE.search(bytes(output)):
                return bytes(output)
        raise TimeoutError("Timed out waiting for the Bebop shell prompt")

    def run(self, command: str, timeout: float = 5.0) -> str:
        if self.sock is None:
            raise ConnectionError("Telnet socket is not connected")
        marker = f"__PES_END_{secrets.token_hex(6)}__"
        wire = f"{command}; printf '\\n{marker}:%s\\n' $?\n".encode()
        self.sock.sendall(wire)
        deadline = time.monotonic() + timeout
        output = bytearray()
        marker_bytes = marker.encode()
        marker_pattern = re.compile(
            rb"(?:^|[\r\n])" + re.escape(marker_bytes) + rb":([0-9]+)(?:[\r\n]|$)"
        )
        while time.monotonic() < deadline:
            try:
                block = self.sock.recv(65536)
            except socket.timeout:
                continue
            if not block:
                raise ConnectionError("Bebop closed the Telnet connection")
            output.extend(self._clean_telnet(block))
            if marker_pattern.search(bytes(output)):
                break
        else:
            raise TimeoutError(f"Timed out running read-only query: {command}")

        raw_output = bytes(output)
        marker_match = marker_pattern.search(raw_output)
        if marker_match is None:
            raise RuntimeError("Completion marker disappeared from Telnet output")
        text = raw_output[: marker_match.start()].decode("utf-8", "replace").replace("\r", "")
        lines = text.splitlines()
        return "\n".join(lines).strip()


def first_int(text: str) -> int | None:
    match = INT_RE.search(text)
    return int(match.group()) if match else None


def ints_after_colon(line: str) -> list[int]:
    value = line.split(":", 1)[1] if ":" in line else line
    return [int(item) for item in INT_RE.findall(value)]


def value_from_lines(text: str, labels: Iterable[str]) -> int | None:
    lowered = tuple(label.lower() for label in labels)
    for line in text.splitlines():
        if any(label in line.lower() for label in lowered):
            values = ints_after_colon(line)
            if values:
                return values[0]
    return None


def pair_from_lines(text: str, labels: Iterable[str]) -> tuple[int | None, int | None]:
    lowered = tuple(label.lower() for label in labels)
    for line in text.splitlines():
        if any(label in line.lower() for label in lowered):
            values = ints_after_colon(line)
            if values:
                return values[0], values[1] if len(values) > 1 else None
    return None, None


def parse_counter(text: str, name: str) -> int | None:
    match = re.search(rf"(?i)(?:^|\s){re.escape(name)}\s+(\d+)", text)
    return int(match.group(1)) if match else None


def parse_sample(raw: str, previous_txfail: int | None) -> dict[str, int | None]:
    sections: dict[str, str] = {}
    current = ""
    for line in raw.splitlines():
        if line.startswith("__") and line.endswith("__"):
            current = line.strip("_").lower()
            sections[current] = ""
        elif current:
            sections[current] += line + "\n"

    sta = sections.get("sta", "")
    phy = sections.get("phy", "")
    counters = sections.get("counters", "")

    a0_last, a1_last = pair_from_lines(
        sta, ("per antenna rssi of last rx data frame", "per antenna rssi")
    )
    if a0_last is None:
        phy_values = [int(value) for value in INT_RE.findall(phy)]
        negative_values = [value for value in phy_values if -127 <= value <= 0]
        if negative_values:
            a0_last = negative_values[0]
            a1_last = negative_values[1] if len(negative_values) > 1 else None

    a0_avg, a1_avg = pair_from_lines(
        sta, ("per antenna average rssi", "per antenna avg rssi")
    )
    a0_noise, a1_noise = pair_from_lines(sta, ("per antenna noise floor",))

    rssi = first_int(sections.get("rssi", ""))
    noise = first_int(sections.get("noise", ""))
    if rssi is None:
        available = [v for v in (a0_avg, a1_avg, a0_last, a1_last) if v is not None]
        if available:
            rssi = round(sum(available[:2]) / len(available[:2]))
    if noise is None:
        available_noise = [v for v in (a0_noise, a1_noise) if v is not None]
        if available_noise:
            noise = round(sum(available_noise) / len(available_noise))

    txfail = parse_counter(counters, "txfail")
    if txfail is None:
        txfail = value_from_lines(sta, ("tx failures", "tx data pkts retry exhausted"))
    txfail_delta = None
    if txfail is not None and previous_txfail is not None:
        txfail_delta = max(0, txfail - previous_txfail)

    channel_text = sections.get("channel", "")
    channel_match = re.search(r"(?i)(?:target channel|channel)\s+(\d+)", channel_text)
    channel = int(channel_match.group(1)) if channel_match else first_int(channel_text)

    return {
        "battery_percent": first_int(sections.get("battery", "")),
        "channel": channel,
        "rssi_dbm": rssi,
        "noise_dbm": noise,
        "snr_db": rssi - noise if rssi is not None and noise is not None else None,
        "a0_last_dbm": a0_last,
        "a1_last_dbm": a1_last,
        "a0_average_dbm": a0_avg,
        "a1_average_dbm": a1_avg,
        "a0_noise_dbm": a0_noise,
        "a1_noise_dbm": a1_noise,
        "tx_rate_kbps": value_from_lines(sta, ("rate of last tx pkt",)),
        "rx_rate_kbps": value_from_lines(sta, ("rate of last rx pkt",)),
        "tx_packets": value_from_lines(sta, ("tx data pkts", "tx pkts")),
        "rx_packets": value_from_lines(sta, ("rx data pkts", "rx pkts")),
        "tx_failures_total": txfail,
        "tx_failures_delta": txfail_delta,
    }


def signal_bar(value: int | None, width: int = 20) -> str:
    if value is None:
        return "?" * width
    filled = round(max(0, min(100, value + 100)) / 100 * width)
    return "#" * filled + "." * (width - filled)


def printable(value: object, suffix: str = "") -> str:
    return "--" if value is None or value == "" else f"{value}{suffix}"


def discover_station(shell: TelnetShell, requested_mac: str | None) -> str | None:
    if requested_mac:
        if not MAC_RE.fullmatch(requested_mac):
            raise ValueError(f"Invalid station MAC: {requested_mac}")
        return requested_mac.lower()
    output = shell.run("/usr/sbin/bcmwl -i eth0 assoclist 2>&1")
    matches = MAC_RE.findall(output)
    return matches[0].lower() if matches else None


def build_query(mac: str, include_battery: bool) -> str:
    battery = (
        "echo __BATTERY__; "
        "ulogcat -d 2>/dev/null | sed -n "
        "'s/.*Battery percentage : *\\([0-9][0-9]*\\).*/\\1/p' | tail -n 1; "
        if include_battery
        else "echo __BATTERY__; "
    )
    return (
        f"{battery}"
        "echo __CHANNEL__; /usr/sbin/bcmwl -i eth0 channel 2>&1; "
        f"echo __STA__; /usr/sbin/bcmwl -i eth0 sta_info {mac} 2>&1; "
        f"echo __RSSI__; /usr/sbin/bcmwl -i eth0 rssi {mac} 2>&1; "
        "echo __NOISE__; /usr/sbin/bcmwl -i eth0 noise 2>&1; "
        "echo __PHY__; /usr/sbin/bcmwl -i eth0 phy_rssi_ant 2>&1; "
        "echo __COUNTERS__; /usr/sbin/bcmwl -i eth0 counters 2>&1 | "
        "grep -E '(^| )txfail( |$)'"
    )


def connect_with_wait(args: argparse.Namespace) -> TelnetShell:
    targets = [(args.host, args.port)] if args.host else [
        ("127.0.0.1", 2323),
        ("192.168.42.1", 23),
    ]
    announced = False
    while True:
        for host, port in targets:
            shell = TelnetShell(host, port, timeout=min(3.0, args.connect_timeout))
            try:
                shell.connect()
                print(f"BEBOP FOUND — Telnet {host}:{port}")
                return shell
            except (OSError, TimeoutError, ConnectionError):
                shell.close()
        if not args.wait:
            choices = ", ".join(f"{host}:{port}" for host, port in targets)
            raise ConnectionError(f"Could not reach the Bebop at {choices}")
        if not announced:
            choices = " or ".join(f"{host}:{port}" for host, port in targets)
            print(f"WAITING FOR BEBOP — trying {choices}; Ctrl+C to stop")
            announced = True
        time.sleep(2.0)


def run_logger(args: argparse.Namespace) -> int:
    shell = connect_with_wait(args)
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    csv_path = output_dir / f"bebop-signal-{stamp}.csv"
    raw_path = output_dir / f"bebop-signal-{stamp}.raw.txt"

    try:
        mac = None
        while mac is None:
            mac = discover_station(shell, args.mac)
            if mac is None:
                if not args.wait:
                    raise RuntimeError("No station is associated with the Bebop")
                print("WAITING FOR SKYCONTROLLER — no associated station yet", end="\r", flush=True)
                time.sleep(2.0)
        print(f"SKYCONTROLLER FOUND — {mac}")
        print(f"LOGGING — {csv_path}")
        print("Press Ctrl+C to stop and print the summary.\n")

        start = time.monotonic()
        next_sample = start
        sample_number = 0
        previous_txfail = None
        last_battery = None
        a0_values: list[int] = []
        a1_values: list[int] = []
        snr_values: list[int] = []

        with csv_path.open("w", newline="", encoding="utf-8") as csv_file, raw_path.open(
            "w", encoding="utf-8"
        ) as raw_file:
            writer = csv.DictWriter(csv_file, fieldnames=CSV_FIELDS)
            writer.writeheader()
            while args.samples == 0 or sample_number < args.samples:
                now = time.monotonic()
                if now < next_sample:
                    time.sleep(next_sample - now)
                include_battery = sample_number == 0 or sample_number % max(1, round(15 / args.interval)) == 0
                raw = shell.run(build_query(mac, include_battery), timeout=max(5.0, args.interval * 2))
                sample = parse_sample(raw, previous_txfail)
                if sample["battery_percent"] is not None:
                    last_battery = sample["battery_percent"]
                sample["battery_percent"] = last_battery
                if sample["tx_failures_total"] is not None:
                    previous_txfail = sample["tx_failures_total"]

                elapsed = time.monotonic() - start
                row = {
                    "timestamp": dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="milliseconds"),
                    "elapsed_s": f"{elapsed:.3f}",
                    "label": args.label,
                    "station_mac": mac,
                    **sample,
                }
                writer.writerow(row)
                csv_file.flush()
                raw_file.write(f"\n===== sample {sample_number + 1} {row['timestamp']} =====\n{raw}\n")
                raw_file.flush()

                for key, destination in (
                    ("a0_last_dbm", a0_values),
                    ("a1_last_dbm", a1_values),
                    ("snr_db", snr_values),
                ):
                    if isinstance(sample[key], int):
                        destination.append(sample[key])

                a0 = sample["a0_last_dbm"]
                a1 = sample["a1_last_dbm"]
                status = (
                    f"{elapsed:7.1f}s  BAT {printable(last_battery, '%'):>4}  "
                    f"A0 {printable(a0, ' dBm'):>8} [{signal_bar(a0)}]  "
                    f"A1 {printable(a1, ' dBm'):>8} [{signal_bar(a1)}]  "
                    f"SNR {printable(sample['snr_db'], ' dB'):>6}  "
                    f"TXfail +{printable(sample['tx_failures_delta'])}"
                )
                print(status, end="\r", flush=True)
                sample_number += 1
                next_sample = start + sample_number * args.interval

    except KeyboardInterrupt:
        print("\n\nCAPTURE STOPPED")
    finally:
        shell.close()

    print(f"Samples: {sample_number}")
    if a0_values:
        print(f"A0 dBm: min {min(a0_values)}, mean {statistics.fmean(a0_values):.1f}, max {max(a0_values)}")
    if a1_values:
        print(f"A1 dBm: min {min(a1_values)}, mean {statistics.fmean(a1_values):.1f}, max {max(a1_values)}")
    if snr_values:
        print(f"SNR dB: min {min(snr_values)}, mean {statistics.fmean(snr_values):.1f}, max {max(snr_values)}")
    print(f"CSV: {csv_path}")
    print(f"Raw: {raw_path}")
    return 0


def self_test() -> int:
    fixture = """__BATTERY__
39
__CHANNEL__
target channel 11
__STA__
 tx data pkts: 1234
 rx data pkts: 2345
 rate of last tx pkt: 65000 kbps
 rate of last rx pkt: 58500 kbps
 per antenna rssi of last rx data frame: -16 -21
 per antenna average rssi of rx data frames: -17 -22
 per antenna noise floor: -92 -91
__RSSI__
-18
__NOISE__
-92
__PHY__
-16 -21
__COUNTERS__
txfail 158
"""
    parsed = parse_sample(fixture, 150)
    expected = {
        "battery_percent": 39,
        "channel": 11,
        "rssi_dbm": -18,
        "noise_dbm": -92,
        "snr_db": 74,
        "a0_last_dbm": -16,
        "a1_last_dbm": -21,
        "tx_failures_total": 158,
        "tx_failures_delta": 8,
    }
    for key, value in expected.items():
        if parsed.get(key) != value:
            raise AssertionError(f"{key}: expected {value}, got {parsed.get(key)}")
    print("Self-test passed")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Log Bebop 2 per-chain Wi-Fi RSSI/SNR to CSV through Telnet."
    )
    parser.add_argument("--host", help="Telnet host; default tries relay then 192.168.42.1")
    parser.add_argument("--port", type=int, default=23, help="Telnet port with --host (default: 23)")
    parser.add_argument("--mac", help="SkyController MAC; default discovers the first associated station")
    parser.add_argument("--interval", type=float, default=1.0, help="Seconds per sample (default: 1.0)")
    parser.add_argument("--samples", type=int, default=0, help="Stop after N samples; 0 runs until Ctrl+C")
    parser.add_argument(
        "--label",
        default="",
        help="Experiment label stored in every CSV row, for example stock or epa2",
    )
    parser.add_argument(
        "--output-dir",
        default=str(Path(__file__).resolve().parents[1] / "measurements"),
        help="Destination directory for CSV and raw logs",
    )
    parser.add_argument("--connect-timeout", type=float, default=5.0)
    parser.add_argument("--no-wait", dest="wait", action="store_false", help="Fail instead of waiting")
    parser.add_argument("--self-test", action="store_true", help="Test the parser without a drone")
    parser.set_defaults(wait=True)
    args = parser.parse_args()
    if args.interval < 0.25:
        parser.error("--interval must be at least 0.25 seconds")
    if args.samples < 0:
        parser.error("--samples cannot be negative")
    return args


def main() -> int:
    args = parse_args()
    if args.self_test:
        return self_test()
    try:
        return run_logger(args)
    except (ConnectionError, OSError, RuntimeError, TimeoutError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
