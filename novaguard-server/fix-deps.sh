#!/bin/bash

echo "Fixing NovaGuard dependencies..."

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo "Error: Go is not installed. Please install Go 1.21 or later."
    exit 1
fi

# Clean go mod cache if needed
echo "Cleaning Go module cache..."
go clean -modcache

# Download and tidy dependencies
echo "Downloading dependencies..."
go mod download
go mod tidy

# Verify dependencies
echo "Verifying dependencies..."
go mod verify

echo "Dependencies fixed successfully!"
echo "Now you can run: ./build.sh" 