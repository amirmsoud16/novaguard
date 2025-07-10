.PHONY: all build clean install cert run stop status logs

# Default target
all: build

# Build the server
build:
	@echo "Building NovaGuard Server..."
	@chmod +x build.sh
	@./build.sh

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -f novaguard-server
	@rm -f *.pid
	@rm -f *.log

# Install dependencies
install:
	@echo "Installing Go dependencies..."
	@go mod tidy
	@go mod download

# Generate SSL certificate
cert:
	@echo "Generating SSL certificate..."
	@chmod +x generate_cert.sh
	@./generate_cert.sh

# Run the server
run: build
	@echo "Running NovaGuard Server..."
	@./novaguard-server

# Start server in background
start: build
	@echo "Starting NovaGuard Server in background..."
	@chmod +x manage.sh
	@./manage.sh start

# Stop server
stop:
	@echo "Stopping NovaGuard Server..."
	@chmod +x manage.sh
	@./manage.sh stop

# Show server status
status:
	@chmod +x manage.sh
	@./manage.sh status

# Show logs
logs:
	@chmod +x manage.sh
	@./manage.sh logs

# Generate new config
config:
	@chmod +x manage.sh
	@./manage.sh generate-config

# Show connection code
code:
	@chmod +x manage.sh
	@./manage.sh show-code

# Setup everything
setup: install cert config build
	@echo "Setup complete! Run 'make start' to start the server."

# Help
help:
	@echo "Available targets:"
	@echo "  build    - Build the server"
	@echo "  clean    - Clean build artifacts"
	@echo "  install  - Install Go dependencies"
	@echo "  cert     - Generate SSL certificate"
	@echo "  run      - Build and run server"
	@echo "  start    - Start server in background"
	@echo "  stop     - Stop server"
	@echo "  status   - Show server status"
	@echo "  logs     - Show server logs"
	@echo "  config   - Generate new config"
	@echo "  code     - Show connection code"
	@echo "  setup    - Complete setup (install + cert + config + build)" 