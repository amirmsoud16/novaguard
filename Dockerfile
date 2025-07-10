# Build stage
FROM golang:1.21-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Set working directory
WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o novaguard-server .

# Final stage
FROM alpine:latest

# Install runtime dependencies
RUN apk --no-cache add ca-certificates tzdata openssl curl

# Create non-root user
RUN addgroup -g 1001 -S novaguard && \
    adduser -u 1001 -S novaguard -G novaguard

# Set working directory
WORKDIR /app

# Copy binary from builder stage
COPY --from=builder /app/novaguard-server .

# Copy scripts and config files
COPY --from=builder /app/*.sh ./
COPY --from=builder /app/Makefile ./
COPY --from=builder /app/config.json ./

# Set permissions
RUN chmod +x *.sh novaguard-server

# Create data directory and configs directory
RUN mkdir -p /app/data /app/configs && chown -R novaguard:novaguard /app

# Switch to non-root user
USER novaguard

# Expose ports
EXPOSE 3077/tcp 3076/udp

# Health check - check if server is listening on port 3077
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD netstat -tuln | grep :3077 || exit 1

# Default command
CMD ["./novaguard-server"] 