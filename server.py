import ssl
import socket
import json
import base64
import secrets
import threading
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives import hashes
from cryptography.x509 import load_pem_x509_certificate
import os
import time
# نسخه پروتکل
# --- تنظیمات ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, 'config.json')
with open(CONFIG_PATH, 'r') as f:
    config = json.load(f)
VERSION = config.get('version', '1.0.0')
# Use separate ports for TCP and UDP
TCP_PORT = 8443
UDP_PORT = 1195
# endpoint برای دانلود سرتیفیکیت
from http.server import SimpleHTTPRequestHandler, HTTPServer
import threading
# --- اضافه کردن: API ثبت کلاینت ---
from http.server import BaseHTTPRequestHandler
import json

# حذف کامل منطق ثبت کلاینت و client_id
# حذف REGISTERED_CLIENTS_PATH و save_registered_client و RegisterClientHandler و serve_register_api
CONFIG_DEVICE_MAP_PATH = os.path.join(BASE_DIR, 'config_device_map.json')

# حذف فراخوانی serve_register_api() در انتهای فایل

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile=config['certfile'], keyfile=config['keyfile'])

HOST = config['host']
PORT = config['port']
PROTOCOL = config.get('protocol', 'novaguard')

# --- تولید کلید نشست برای هر کلاینت ---
def generate_session_key():
    return secrets.token_bytes(32)  # 32 bytes for ChaCha20

# --- توابع بسته novaguard ---
def build_packet(payload: bytes, session_key: bytes) -> bytes:
    random_pad = secrets.token_bytes(secrets.choice(range(4, 17)))
    fake_ip = secrets.token_bytes(4)
    fake_port = secrets.token_bytes(2)
    nonce = secrets.token_bytes(12)
    cipher = ChaCha20Poly1305(session_key)
    encrypted = cipher.encrypt(nonce, payload, None)
    length = len(encrypted).to_bytes(2, 'big')
    mac = encrypted[-8:]  # 8 bytes از انتهای رمزنگاری (ساده، در نسخه بعدی HMAC)
    packet = random_pad + fake_ip + fake_port + nonce + length + encrypted + mac
    return packet

def parse_packet(packet: bytes, session_key: bytes) -> bytes:
    pad_len = packet[0] % 13 + 4
    nonce = packet[pad_len+6:pad_len+18]
    length = int.from_bytes(packet[pad_len+18:pad_len+20], 'big')
    encrypted = packet[pad_len+20:pad_len+20+length]
    cipher = ChaCha20Poly1305(session_key)
    payload = cipher.decrypt(nonce, encrypted, None)
    return payload

# --- تولید Connection Code ---
def get_cert_fingerprint(certfile):
    with open(certfile, 'rb') as f:
        cert = load_pem_x509_certificate(f.read())
    fp = cert.fingerprint(hashes.SHA256())
    return ':'.join([fp.hex()[i:i+2].upper() for i in range(0, len(fp.hex()), 2)])

def generate_connection_code():
    with open(CONFIG_PATH, 'r') as f:
        config = json.load(f)
    info = {
        "server": config["host"],
        "tcp_port": config["tcp_port"],
        "udp_port": config["udp_port"],
        "config_id": config.get("config_id", ""),
        "fingerprint": get_cert_fingerprint(config['certfile']),
        "protocol": config.get("protocol", "novaguard")
    }
    b64 = base64.urlsafe_b64encode(json.dumps(info).encode()).decode()
    return f"ng://{b64}"

def send_packet_fragmented(sock, packet, addr=None, is_udp=False):
    size = len(packet)
    part = size // 3
    fragments = [packet[0:part], packet[part:2*part], packet[2*part:]]
    for frag in fragments:
        if is_udp:
            sock.sendto(frag, addr)
        else:
            sock.sendall(frag)
        time.sleep(0.025)  # 25ms

def receive_fragments(sock, expected_len, is_udp=False):
    fragments = []
    total = 0
    while len(fragments) < 3 and total < expected_len:
        if is_udp:
            frag, _ = sock.recvfrom(expected_len)
        else:
            frag = sock.recv(expected_len)
        fragments.append(frag)
        total += len(frag)
    return b''.join(fragments)

# --- مدیریت هر کلاینت ---
def load_config_device_map():
    if os.path.exists(CONFIG_DEVICE_MAP_PATH):
        with open(CONFIG_DEVICE_MAP_PATH, 'r') as f:
            return json.load(f)
    return {}

def save_config_device_map(mapping):
    with open(CONFIG_DEVICE_MAP_PATH, 'w') as f:
        json.dump(mapping, f, indent=2)

def check_and_bind_config_device(config_id, device_id):
    mapping = load_config_device_map()
    if config_id in mapping:
        return mapping[config_id] == device_id  # Only allow if device_id matches
    else:
        mapping[config_id] = device_id
        save_config_device_map(mapping)
        return True

def handle_client(conn, addr):
    session_key = generate_session_key()
    print(f"[+] New session for {addr}")
    try:
        # --- انتظار دریافت پیام اولیه شامل config_id و device_id ---
        initial_data = receive_fragments(conn, 1024)
        try:
            initial_json = json.loads(initial_data.decode())
            config_id = initial_json.get('config_id')
            device_id = initial_json.get('device_id')
            if not config_id or not device_id:
                conn.sendall(b'Error: Missing config_id or device_id')
                conn.close()
                print(f"[!] Missing config_id/device_id from {addr}")
                return
            if not check_and_bind_config_device(config_id, device_id):
                conn.sendall(b'Error: Config already bound to another device')
                conn.close()
                print(f"[!] Config {config_id} already bound to another device (from {addr})")
                return
            print(f"[+] Config {config_id} bound to device {device_id}")
        except Exception as e:
            conn.sendall(f'Error: {e}'.encode())
            conn.close()
            print(f"[!] Initial JSON parse error from {addr}: {e}")
            return
        # --- ادامه منطق قبلی ---
        while True:
            data = receive_fragments(conn, 4096)
            if not data:
                break
            try:
                payload = parse_packet(data, session_key)
                print(f"[>] Received from {addr}: {payload}")
                # پاسخ نمونه (echo)
                response = build_packet(payload, session_key)
                send_packet_fragmented(conn, response)
            except Exception as e:
                print(f"[!] Packet parse error from {addr}: {e}")
                break
    except Exception as e:
        print(f"[!] Connection error with {addr}: {e}")
    finally:
        conn.close()
        print(f"[-] Session closed for {addr}")

def serve_cert():
    class Handler(SimpleHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/novaguard.crt':
                self.send_response(200)
                self.send_header('Content-type', 'application/x-x509-ca-cert')
                self.end_headers()
                with open('/root/novaguard/novaguard.crt', 'rb') as f:
                    self.wfile.write(f.read())
            else:
                self.send_response(404)
                self.end_headers()
    t = threading.Thread(target=lambda: HTTPServer(("0.0.0.0", 8080), Handler).serve_forever(), daemon=True)
    t.start()

# حذف فراخوانی serve_register_api() در انتهای فایل

def udp_server():
    udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp_sock.bind((HOST, UDP_PORT))
    print(f"[UDP] novaguard server listening on {HOST}:{UDP_PORT}")
    while True:
        try:
            data, addr = receive_fragments(udp_sock, 4096, is_udp=True), None
            print(f"[UDP] Received from {addr}: {data}")
            # Echo back (for now)
            send_packet_fragmented(udp_sock, data, addr, is_udp=True)
        except Exception as e:
            print(f"[UDP] Error: {e}")

# --- سرور اصلی ---
def main():
    # Start UDP server in a thread
    t_udp = threading.Thread(target=udp_server, daemon=True)
    t_udp.start()
    # TCP server as before
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0) as sock:
        sock.bind((HOST, TCP_PORT))
        sock.listen(100)
        print(f"[TCP] novaguard server listening on {HOST}:{TCP_PORT} (TLS enabled)")
        print(f"Connection Code: {generate_connection_code()}")
        with context.wrap_socket(sock, server_side=True) as ssock:
            while True:
                try:
                    conn, addr = ssock.accept()
                    print(f"[TCP] Connection from {addr}")
                    t = threading.Thread(target=handle_client, args=(conn, addr), daemon=True)
                    t.start()
                except Exception as e:
                    print(f"[TCP] Accept error: {e}")

if __name__ == "__main__":
    main()
    serve_cert()
