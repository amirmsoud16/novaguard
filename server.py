import ssl
import socket
import json
import base64
import secrets
import threading
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives import hashes
from cryptography.x509 import load_pem_x509_certificate

# --- تنظیمات ---
with open('config.json', 'r') as f:
    config = json.load(f)

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
    info = {
        "server": HOST,
        "port": PORT,
        "fingerprint": get_cert_fingerprint(config['certfile']),
        "protocol": PROTOCOL
    }
    b64 = base64.urlsafe_b64encode(json.dumps(info).encode()).decode()
    return f"ng://{b64}"

# --- مدیریت هر کلاینت ---
def handle_client(conn, addr):
    session_key = generate_session_key()
    print(f"[+] New session for {addr}")
    try:
        while True:
            data = conn.recv(4096)
            if not data:
                break
            try:
                payload = parse_packet(data, session_key)
                print(f"[>] Received from {addr}: {payload}")
                # پاسخ نمونه (echo)
                response = build_packet(payload, session_key)
                conn.sendall(response)
            except Exception as e:
                print(f"[!] Packet parse error from {addr}: {e}")
                break
    except Exception as e:
        print(f"[!] Connection error with {addr}: {e}")
    finally:
        conn.close()
        print(f"[-] Session closed for {addr}")

# --- سرور اصلی ---
def main():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0) as sock:
        sock.bind((HOST, PORT))
        sock.listen(100)
        print(f"novaguard server listening on {HOST}:{PORT} (TLS enabled)")
        print(f"Connection Code: {generate_connection_code()}")
        with context.wrap_socket(sock, server_side=True) as ssock:
            while True:
                try:
                    conn, addr = ssock.accept()
                    print(f"[+] Connection from {addr}")
                    t = threading.Thread(target=handle_client, args=(conn, addr), daemon=True)
                    t.start()
                except Exception as e:
                    print(f"[!] Accept error: {e}")

if __name__ == "__main__":
    main()
