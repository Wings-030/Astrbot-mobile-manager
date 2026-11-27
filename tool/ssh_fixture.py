# SPDX-License-Identifier: AGPL-3.0-or-later
"""Test-only SSH server that forwards to one loopback port."""
import json
import socket
import socketserver
import sys
from threading import Lock, Thread

import paramiko
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ed25519


class Fixture(socketserver.ThreadingTCPServer):
    daemon_threads = True

    def __init__(self, target_port, client_key):
        super().__init__(("127.0.0.1", 0), Peer)
        self.target_port = target_port
        self.client_key = client_key
        self.host_key = paramiko.RSAKey.generate(2048)
        self.transports = set()
        self.lock = Lock()

    def drop(self, rotate=False):
        with self.lock:
            if rotate:
                self.host_key = paramiko.RSAKey.generate(2048)
            for transport in self.transports:
                transport.close()


class Auth(paramiko.ServerInterface):
    def __init__(self, server):
        self.server = server

    def get_allowed_auths(self, username):
        return "password,publickey"

    def check_auth_password(self, username, password):
        if username == "fixture" and password == "test-only-password":
            return paramiko.AUTH_SUCCESSFUL
        return paramiko.AUTH_FAILED

    def check_auth_publickey(self, username, key):
        if username == "fixture" and key.asbytes() == self.server.client_key:
            return paramiko.AUTH_SUCCESSFUL
        return paramiko.AUTH_FAILED

    def check_channel_direct_tcpip_request(self, chanid, origin, destination):
        if destination == ("127.0.0.1", self.server.target_port):
            return paramiko.OPEN_SUCCEEDED
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED


class Peer(socketserver.BaseRequestHandler):
    def handle(self):
        transport = paramiko.Transport(self.request)
        with self.server.lock:
            self.server.transports.add(transport)
            transport.add_server_key(self.server.host_key)
        try:
            transport.start_server(server=Auth(self.server))
            while transport.is_active():
                channel = transport.accept(0.5)
                if channel is not None:
                    Thread(target=self.forward, args=(channel,), daemon=True).start()
        except (OSError, EOFError, paramiko.SSHException):
            pass
        finally:
            transport.close()
            with self.server.lock:
                self.server.transports.discard(transport)

    def forward(self, channel):
        try:
            target = socket.create_connection(("127.0.0.1", self.server.target_port), timeout=5)
        except OSError:
            channel.close()
            return
        with target, channel:
            target.settimeout(None)
            upstream = Thread(target=self.relay, args=(channel, target), daemon=True)
            upstream.start()
            self.relay(target, channel)
            channel.close()
            upstream.join(timeout=2)

    @staticmethod
    def relay(source, destination):
        try:
            while data := source.recv(65536):
                destination.sendall(data)
            destination.shutdown(socket.SHUT_WR)
        except (OSError, EOFError):
            pass


def main():
    key = ed25519.Ed25519PrivateKey.generate()
    client_public = key.public_key().public_bytes(
        serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH
    )
    _, raw_key = client_public.split()
    import base64

    private_key = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.OpenSSH,
        serialization.BestAvailableEncryption(b"test-only-passphrase"),
    )
    with Fixture(int(sys.argv[1]), base64.b64decode(raw_key)) as fixture:
        Thread(target=fixture.serve_forever, daemon=True).start()
        print(json.dumps({"port": fixture.server_address[1], "key": private_key.decode()}), flush=True)
        for command in sys.stdin:
            if command.strip() in ("drop", "rotate"):
                fixture.drop(rotate=command.strip() == "rotate")
                print("ok", flush=True)
        fixture.drop()
        fixture.shutdown()


if __name__ == "__main__":
    main()
