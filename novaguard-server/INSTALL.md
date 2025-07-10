# NovaGuard Server Installation Guide

## نصب سریع (پیشنهادی)

```bash
# دانلود و اجرای اسکریپت نصب
curl -sSL https://raw.githubusercontent.com/amirmsoud16/novaguard/main/novaguard-server/install.sh | sudo bash
```

## نصب دستی

### پیش‌نیازها
- Linux (Ubuntu 20.04+, CentOS 8+, یا مشابه)
- Go 1.21 یا بالاتر
- OpenSSL
- Git

### مراحل نصب

1. **کلون کردن پروژه:**
```bash
git clone https://github.com/amirmsoud16/novaguard.git
cd novaguard/novaguard-server
```

2. **نصب پیش‌نیازها:**
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y git curl wget jq golang-go openssl

# CentOS/RHEL/Fedora
sudo yum install -y git curl wget jq golang openssl
```

3. **تولید گواهی SSL:**
```bash
chmod +x generate_cert.sh
./generate_cert.sh
```

4. **ساخت سرور:**
```bash
chmod +x build.sh
./build.sh
```

5. **اجرای سرور:**
```bash
./novaguard-server
```

## نصب با Docker

```bash
# ساخت و اجرای container
docker-compose up -d

# یا با Docker
docker build -t novaguard-server .
docker run -d --name novaguard-server -p 3077:3077 -p 3076:3076/udp novaguard-server
```

## مدیریت سرور

### با systemd (نصب خودکار)
```bash
# وضعیت سرویس
sudo systemctl status novaguard

# شروع/توقف
sudo systemctl start novaguard
sudo systemctl stop novaguard

# مشاهده لاگ‌ها
sudo journalctl -u novaguard -f
```

### با اسکریپت مدیریت
```bash
# شروع سرور
./manage.sh start

# توقف سرور
./manage.sh stop

# وضعیت سرور
./manage.sh status

# مشاهده لاگ‌ها
./manage.sh logs
```

### با منوی تعاملی
```bash
./nova.sh
```

## تنظیمات فایروال

### UFW (Ubuntu)
```bash
sudo ufw allow 3077/tcp
sudo ufw allow 3076/udp
```

### Firewalld (CentOS/RHEL)
```bash
sudo firewall-cmd --permanent --add-port=3077/tcp
sudo firewall-cmd --permanent --add-port=3076/udp
sudo firewall-cmd --reload
```

## عیب‌یابی

### مشکلات رایج

1. **خطای "Go not found":**
   - Go 1.21+ را نصب کنید

2. **خطای "Permission denied":**
   - فایل‌های .sh را executable کنید: `chmod +x *.sh`

3. **خطای "Port already in use":**
   - پورت‌های 3077 و 3076 را آزاد کنید

4. **خطای "Certificate not found":**
   - گواهی SSL را تولید کنید: `./generate_cert.sh`

### لاگ‌ها
```bash
# لاگ‌های systemd
sudo journalctl -u novaguard -f

# لاگ‌های فایل
tail -f novaguard-server.log
```

## پشتیبانی

برای گزارش مشکل یا درخواست ویژگی جدید:
- GitHub Issues: https://github.com/amirmsoud16/novaguard/issues
- Email: support@novaguard.com 