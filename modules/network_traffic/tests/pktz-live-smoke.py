#!/usr/bin/env python3
"""Deterministic privileged pktz TCP/UDP cumulative-byte smoke test."""

import argparse
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time

TCP_TX = 1024 * 1024
TCP_RX = 512 * 1024
UDP_MESSAGES = 256
UDP_SIZE = 1024


def receive_exact(sock, size):
    received = 0
    while received < size:
        chunk = sock.recv(min(65536, size - received))
        if not chunk:
            raise RuntimeError("socket closed before fixed payload completed")
        received += len(chunk)


def run_servers(ready, ports):
    tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tcp.bind(("127.0.0.1", 0))
    tcp.listen(1)
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.bind(("127.0.0.1", 0))
    ports.extend([tcp.getsockname()[1], udp.getsockname()[1]])
    ready.set()

    conn, _ = tcp.accept()
    receive_exact(conn, TCP_TX)
    conn.sendall(b"r" * TCP_RX)
    conn.close()
    tcp.close()

    for _ in range(UDP_MESSAGES):
        data, peer = udp.recvfrom(UDP_SIZE + 1)
        udp.sendto(data, peer)
    udp.close()


def run_client(tcp_port, udp_port, gate):
    tcp = socket.create_connection(("127.0.0.1", tcp_port))
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.connect(("127.0.0.1", udp_port))
    print(os.getpid(), flush=True)
    while not os.path.exists(gate):
        time.sleep(0.02)

    tcp.sendall(b"t" * TCP_TX)
    receive_exact(tcp, TCP_RX)

    payload = b"u" * UDP_SIZE
    for _ in range(UDP_MESSAGES):
        udp.send(payload)
        if udp.recv(UDP_SIZE + 1) != payload:
            raise RuntimeError("UDP echo payload mismatch")
    time.sleep(2)
    udp.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pktz", default="pktz")
    parser.add_argument("--sudo", action="store_true")
    args = parser.parse_args()

    ready = threading.Event()
    ports = []
    server = threading.Thread(target=run_servers, args=(ready, ports), daemon=True)
    server.start()
    ready.wait()

    with tempfile.TemporaryDirectory(prefix="pktz-live-") as temp:
        gate = os.path.join(temp, "go")
        child_args = [sys.executable, __file__, "--client", str(ports[0]), str(ports[1]), gate]
        client = subprocess.Popen(child_args, stdout=subprocess.PIPE, text=True)
        pid = int(client.stdout.readline().strip())
        command = [args.pktz, "--log", "--pid", str(pid)]
        if args.sudo:
            command = ["sudo", "-A", *command]
        collector = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        time.sleep(1.25)
        open(gate, "w", encoding="utf-8").close()
        client_status = client.wait(timeout=15)
        time.sleep(1)
        collector.terminate()
        stdout, stderr = collector.communicate(timeout=5)
        if client_status != 0:
            raise SystemExit(f"client failed: {client_status}")

    rows = []
    for line in stdout.splitlines():
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if row.get("type") == "process" and row.get("pid") == pid:
            rows.append(row)
    if len(rows) < 2:
        raise SystemExit(
            f"pktz produced {len(rows)} process rows (collector status {collector.returncode}); "
            f"stdout={stdout[:500]!r}; stderr={stderr.strip()!r}"
        )

    baseline = rows[0]
    final = rows[-1]
    rx = final["rx_bytes"] - baseline["rx_bytes"]
    tx = final["tx_bytes"] - baseline["tx_bytes"]
    required_rx = TCP_RX
    optional_udp_rx = UDP_MESSAGES * UDP_SIZE
    expected_tx = TCP_TX + UDP_MESSAGES * UDP_SIZE
    print(json.dumps({"pid": pid, "rows": len(rows), "rx_delta": rx, "tx_delta": tx,
                      "required_rx": required_rx, "optional_udp_rx": optional_udp_rx,
                      "expected_tx": expected_tx, "udp_rx_observed": rx >= required_rx + optional_udp_rx}))
    if tx < expected_tx:
        raise SystemExit("pktz TX total missed TCP or UDP payload")
    if rx < required_rx:
        raise SystemExit("pktz RX total missed required TCP payload")


if __name__ == "__main__":
    if "--client" in sys.argv:
        index = sys.argv.index("--client")
        run_client(int(sys.argv[index + 1]), int(sys.argv[index + 2]), sys.argv[index + 3])
    else:
        main()
