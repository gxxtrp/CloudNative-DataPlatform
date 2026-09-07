#!/usr/bin/env python3
import socket
import time
import sys

ports = [30000, 30080, 30088, 30300, 30443, 31686, 32746, 38081, 38200]
sockets = []

for port in ports:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("0.0.0.0", port))
        s.listen(128)
        sockets.append(s)
        print(f"Registered dummy listening socket for port {port}")
    except Exception as e:
        print(f"Failed to bind port {port}: {e}")

sys.stdout.flush()

while True:
    time.sleep(60)
