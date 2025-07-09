#!/bin/bash

echo "Building NovaGuard Server..."

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo "Error: Go is not installed. Please install Go 1.21 or later."
    exit 1
fi

# Download and tidy dependencies
echo "Downloading dependencies..."
go mod download
go mod tidy

# Build the server
echo "Building server..."
go build -o novaguard-server main.go

if [ $? -eq 0 ]; then
    echo "Build successful!"
    echo "Executable: novaguard-server"
    echo ""
    echo "To run the server:"
    echo "  ./novaguard-server"
else
    echo "Build failed!"
    exit 1
fi 
