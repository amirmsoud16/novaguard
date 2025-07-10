package main

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"golang.org/x/crypto/chacha20poly1305"
)

// NovaGuardConfig represents the server configuration
type NovaGuardConfig struct {
	Server      string `json:"server"`
	TCPPort     int    `json:"tcp_port"`
	UDPPort     int    `json:"udp_port"`
	ConfigID    string `json:"config_id"`
	SessionID   string `json:"session_id"`
	Protocol    string `json:"protocol"`
	Encryption  string `json:"encryption"`
	Version     string `json:"version"`
	CertFile    string `json:"certfile"`
	KeyFile     string `json:"keyfile"`
}

// ClientSession represents a client connection session
type ClientSession struct {
	conn       net.Conn
	sessionKey []byte
	configID   string
	deviceID   string
	mu         sync.Mutex
	createdAt  time.Time
}

// Server represents the NovaGuard server
type Server struct {
	config     *NovaGuardConfig
	tlsConfig  *tls.Config
	sessions   map[string]*ClientSession
	sessionsMu sync.RWMutex
	shutdown   chan struct{}
}

// HandshakeMessage represents the initial handshake from client
type HandshakeMessage struct {
	ConfigID string `json:"config_id"`
	DeviceID string `json:"device_id"`
}

// ConnectionInfo represents the connection information for ng:// format
type ConnectionInfo struct {
	Server      string `json:"server"`
	TCPPort     int    `json:"tcp_port"`
	UDPPort     int    `json:"udp_port"`
	ConfigID    string `json:"config_id"`
	SessionID   string `json:"session_id"`
	Protocol    string `json:"protocol"`
	Encryption  string `json:"encryption"`
	Version     string `json:"version"`
	Fingerprint string `json:"fingerprint"`
}

// DeviceMapping represents the device to config mapping
type DeviceMapping map[string]string

var (
	server *Server
	deviceMap DeviceMapping
	deviceMapMu sync.RWMutex
	showCodeOnly bool
)

func main() {
	// Parse command line flags
	flag.BoolVar(&showCodeOnly, "show-code", false, "Show connection code and exit")
	flag.Parse()

	var configs []NovaGuardConfig
	if _, err := os.Stat("configs.json"); err == nil {
		// اگر configs.json وجود داشت، همه کانفیگ‌ها را بخوان
		data, err := os.ReadFile("configs.json")
		if err != nil {
			log.Fatalf("Failed to read configs.json: %v", err)
		}
		if err := json.Unmarshal(data, &configs); err != nil {
			log.Fatalf("Failed to parse configs.json: %v", err)
		}
	} else {
		// اگر نبود، فقط config.json را بخوان
		config, err := loadConfig()
		if err != nil {
			log.Fatalf("Failed to load config: %v", err)
		}
		configs = append(configs, *config)
	}

	// Load device mapping
	deviceMap = loadDeviceMapping()

	// Setup TLS (فقط یک بار کافی است)
	certFile := configs[0].CertFile
	keyFile := configs[0].KeyFile
	if certFile == "" { certFile = "novaguard.crt" }
	if keyFile == "" { keyFile = "novaguard.key" }
	tlsConfig, err := setupTLS(certFile, keyFile)
	if err != nil {
		log.Fatalf("Failed to setup TLS: %v", err)
	}

	// Setup signal handling for graceful shutdown
	shutdown := make(chan struct{})
	setupSignalHandlingCustom(shutdown)

	// برای هر کانفیگ یک goroutine برای TCP و یک goroutine برای UDP راه‌اندازی کن
	for _, cfg := range configs {
		go startTCPServerOnPort(cfg.TCPPort, tlsConfig, shutdown)
		go startUDPServerOnPort(cfg.UDPPort, shutdown)
	}

	// Start session cleanup goroutine (مثل قبل)
	go sessionCleanupCustom(shutdown)

	fmt.Printf("NovaGuard Server started\n")
	for _, cfg := range configs {
		fmt.Printf("TCP Port: %d, UDP Port: %d\n", cfg.TCPPort, cfg.UDPPort)
	}
	fmt.Printf("Press Ctrl+C to stop the server\n")

	// Keep server running
	<-shutdown
	fmt.Println("\nShutting down server...")
}

// نسخه جدید setupSignalHandling که کانال shutdown را می‌گیرد
func setupSignalHandlingCustom(shutdown chan struct{}) {
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigChan
		close(shutdown)
	}()
}

// نسخه جدید sessionCleanup که کانال shutdown را می‌گیرد
func sessionCleanupCustom(shutdown chan struct{}) {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			cleanupOldSessions()
		case <-shutdown:
			return
		}
	}
}

// سرور TCP روی پورت دلخواه
func startTCPServerOnPort(port int, tlsConfig *tls.Config, shutdown chan struct{}) {
	listener, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		log.Printf("Failed to start TCP server on port %d: %v", port, err)
		return
	}
	defer listener.Close()
	log.Printf("TCP server listening on port %d", port)
	for {
		select {
		case <-shutdown:
			return
		default:
			conn, err := listener.Accept()
			if err != nil {
				log.Printf("Failed to accept connection: %v", err)
				continue
			}
			go handleTCPClient(conn)
		}
	}
}

// سرور UDP روی پورت دلخواه
func startUDPServerOnPort(port int, shutdown chan struct{}) {
	addr := fmt.Sprintf(":%d", port)
	conn, err := net.ListenPacket("udp", addr)
	if err != nil {
		log.Printf("Failed to start UDP server on port %d: %v", port, err)
		return
	}
	defer conn.Close()
	log.Printf("UDP server listening on port %d", port)
	buffer := make([]byte, 4096)
	for {
		select {
		case <-shutdown:
			return
		default:
			conn.SetReadDeadline(time.Now().Add(1 * time.Second))
			n, clientAddr, err := conn.ReadFrom(buffer)
			if err != nil {
				if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
					continue
				}
				log.Printf("UDP read error: %v", err)
				continue
			}
			go handleUDPPacket(conn, clientAddr, buffer[:n])
		}
	}
}

func handleTCPClient(conn net.Conn) {
	defer conn.Close()

	// Set connection timeout
	conn.SetDeadline(time.Now().Add(30 * time.Second))

	// Wrap connection with TLS
	tlsConn := tls.Server(conn, server.tlsConfig)
	if err := tlsConn.Handshake(); err != nil {
		log.Printf("TLS handshake failed: %v", err)
		return
	}

	// Reset deadline after handshake
	tlsConn.SetDeadline(time.Time{})

	// Handle initial handshake
	session, err := handleInitialHandshake(tlsConn)
	if err != nil {
		log.Printf("Initial handshake failed: %v", err)
		return
	}

	// Add session to server
	server.sessionsMu.Lock()
	server.sessions[session.configID] = session
	server.sessionsMu.Unlock()

	// Remove session when done
	defer func() {
		server.sessionsMu.Lock()
		delete(server.sessions, session.configID)
		server.sessionsMu.Unlock()
	}()

	log.Printf("New session for %s (Config: %s, Device: %s)", 
		tlsConn.RemoteAddr(), session.configID, session.deviceID)

	// Handle packet processing
	handlePacketProcessing(tlsConn, session)
}

func handleInitialHandshake(conn net.Conn) (*ClientSession, error) {
	// Read handshake data
	buffer := make([]byte, 1024)
	n, err := conn.Read(buffer)
	if err != nil {
		return nil, fmt.Errorf("failed to read handshake: %v", err)
	}

	// Parse handshake message
	var handshake HandshakeMessage
	if err := json.Unmarshal(buffer[:n], &handshake); err != nil {
		return nil, fmt.Errorf("failed to parse handshake: %v", err)
	}

	if handshake.ConfigID == "" || handshake.DeviceID == "" {
		return nil, fmt.Errorf("missing config_id or device_id")
	}

	// Check device binding
	if !checkAndBindDevice(handshake.ConfigID, handshake.DeviceID) {
		return nil, fmt.Errorf("config already bound to another device")
	}

	// Generate session key
	sessionKey := make([]byte, chacha20poly1305.KeySize)
	if _, err := rand.Read(sessionKey); err != nil {
		return nil, fmt.Errorf("failed to generate session key: %v", err)
	}

	// Send success response
	response := []byte("OK")
	if _, err := conn.Write(response); err != nil {
		return nil, fmt.Errorf("failed to send handshake response: %v", err)
	}

	return &ClientSession{
		conn:       conn,
		sessionKey: sessionKey,
		configID:   handshake.ConfigID,
		deviceID:   handshake.DeviceID,
		createdAt:  time.Now(),
	}, nil
}

func handlePacketProcessing(conn net.Conn, session *ClientSession) {
	buffer := make([]byte, 32768)

	for {
		select {
		case <-server.shutdown:
			return
		default:
			// Read packet from client
			n, err := conn.Read(buffer)
			if err != nil {
				if err != io.EOF {
					log.Printf("Read error: %v", err)
				}
				break
			}

			if n == 0 {
				continue
			}

			// Decrypt packet
			decrypted, err := decryptPacket(buffer[:n], session.sessionKey)
			if err != nil {
				log.Printf("Decrypt error: %v", err)
				continue
			}

			// Echo back (or process as needed)
			encrypted, err := encryptPacket(decrypted, session.sessionKey)
			if err != nil {
				log.Printf("Encrypt error: %v", err)
				continue
			}

			// Send response in fragments
			sendPacketFragmented(conn, encrypted)
		}
	}
}

func handleUDPPacket(conn net.PacketConn, clientAddr net.Addr, data []byte) {
	// For UDP, we need to handle sessions differently
	// This is a simplified implementation
	log.Printf("UDP packet from %s: %d bytes", clientAddr, len(data))
}

func encryptPacket(payload []byte, sessionKey []byte) ([]byte, error) {
	// Generate random padding (4-16 bytes)
	paddingLen := 4 + (int(sessionKey[0]) % 13)
	padding := make([]byte, paddingLen)
	if _, err := rand.Read(padding); err != nil {
		return nil, err
	}

	// Generate fake IP and port
	fakeIP := make([]byte, 4)
	fakePort := make([]byte, 2)
	if _, err := rand.Read(fakeIP); err != nil {
		return nil, err
	}
	if _, err := rand.Read(fakePort); err != nil {
		return nil, err
	}

	// Generate nonce
	nonce := make([]byte, chacha20poly1305.NonceSize)
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}

	// Encrypt payload
	aead, err := chacha20poly1305.New(sessionKey)
	if err != nil {
		return nil, err
	}

	encrypted := aead.Seal(nil, nonce, payload, nil)

	// Build packet: padding + fakeIP + fakePort + nonce + length + encrypted + MAC
	length := uint16(len(encrypted))
	lengthBytes := []byte{byte(length >> 8), byte(length & 0xFF)}
	mac := encrypted[len(encrypted)-8:] // Last 8 bytes as MAC

	packet := append(padding, fakeIP...)
	packet = append(packet, fakePort...)
	packet = append(packet, nonce...)
	packet = append(packet, lengthBytes...)
	packet = append(packet, encrypted...)
	packet = append(packet, mac...)

	return packet, nil
}

func decryptPacket(encryptedPacket []byte, sessionKey []byte) ([]byte, error) {
	if len(encryptedPacket) < 26 { // Minimum packet size
		return nil, fmt.Errorf("packet too short")
	}

	// Extract padding length
	paddingLen := int(encryptedPacket[0]%13) + 4

	// Extract nonce
	nonceStart := paddingLen + 6
	nonceEnd := nonceStart + chacha20poly1305.NonceSize
	if nonceEnd > len(encryptedPacket) {
		return nil, fmt.Errorf("invalid packet structure")
	}
	nonce := encryptedPacket[nonceStart:nonceEnd]

	// Extract length
	lengthStart := nonceEnd
	lengthEnd := lengthStart + 2
	if lengthEnd > len(encryptedPacket) {
		return nil, fmt.Errorf("invalid packet structure")
	}
	length := uint16(encryptedPacket[lengthStart])<<8 | uint16(encryptedPacket[lengthStart+1])

	// Extract encrypted data
	encryptedStart := lengthEnd
	encryptedEnd := encryptedStart + int(length)
	if encryptedEnd > len(encryptedPacket) {
		return nil, fmt.Errorf("invalid packet structure")
	}
	encrypted := encryptedPacket[encryptedStart:encryptedEnd]

	// Decrypt
	aead, err := chacha20poly1305.New(sessionKey)
	if err != nil {
		return nil, err
	}

	decrypted, err := aead.Open(nil, nonce, encrypted, nil)
	if err != nil {
		return nil, err
	}

	return decrypted, nil
}

func sendPacketFragmented(conn net.Conn, packet []byte) {
	size := len(packet)
	part := size / 3

	// Send in 3 fragments
	for i := 0; i < 3; i++ {
		start := i * part
		end := start + part
		if i == 2 {
			end = size
		}

		fragment := packet[start:end]
		if _, err := conn.Write(fragment); err != nil {
			log.Printf("Failed to send fragment: %v", err)
			return
		}

		// Small delay between fragments
		time.Sleep(25 * time.Millisecond)
	}
}

func checkAndBindDevice(configID, deviceID string) bool {
	deviceMapMu.Lock()
	defer deviceMapMu.Unlock()

	if existingDevice, exists := deviceMap[configID]; exists {
		return existingDevice == deviceID
	}

	deviceMap[configID] = deviceID
	saveDeviceMapping()
	return true
}

func loadDeviceMapping() DeviceMapping {
	data, err := os.ReadFile("config_device_map.json")
	if err != nil {
		return make(DeviceMapping)
	}

	var mapping DeviceMapping
	if err := json.Unmarshal(data, &mapping); err != nil {
		return make(DeviceMapping)
	}

	return mapping
}

func saveDeviceMapping() {
	data, err := json.MarshalIndent(deviceMap, "", "  ")
	if err != nil {
		log.Printf("Failed to marshal device mapping: %v", err)
		return
	}

	if err := os.WriteFile("config_device_map.json", data, 0644); err != nil {
		log.Printf("Failed to save device mapping: %v", err)
	}
}

func generateConnectionCode(config *NovaGuardConfig) string {
	// Get certificate fingerprint
	fingerprint, err := getCertFingerprint(config.CertFile)
	if err != nil {
		log.Printf("Failed to get certificate fingerprint: %v", err)
		fingerprint = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
	}

	// Create connection info
	info := ConnectionInfo{
		Server:      config.Server,
		TCPPort:     config.TCPPort,
		UDPPort:     config.UDPPort,
		ConfigID:    config.ConfigID,
		SessionID:   config.SessionID,
		Protocol:    config.Protocol,
		Encryption:  config.Encryption,
		Version:     config.Version,
		Fingerprint: fingerprint,
	}

	// Convert to JSON
	jsonData, err := json.Marshal(info)
	if err != nil {
		log.Printf("Failed to marshal connection info: %v", err)
		return ""
	}

	// Encode to base64
	encoded := base64.URLEncoding.WithPadding(base64.NoPadding).EncodeToString(jsonData)

	return "ng://" + encoded
}

func getCertFingerprint(certFile string) (string, error) {
	data, err := os.ReadFile(certFile)
	if err != nil {
		return "", err
	}

	// Decode PEM
	block, _ := pem.Decode(data)
	if block == nil {
		return "", fmt.Errorf("failed to decode PEM block")
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return "", err
	}

	// Calculate SHA256 fingerprint manually
	hash := sha256.Sum256(cert.Raw)
	fingerprint := hash[:]
	if len(fingerprint) < 16 {
		return "", fmt.Errorf("invalid fingerprint length")
	}

	// Convert to hex string with colons
	var result string
	for i, b := range fingerprint[:16] {
		if i > 0 {
			result += ":"
		}
		result += fmt.Sprintf("%02X", b)
	}

	return result, nil
} 
