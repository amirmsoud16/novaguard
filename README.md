# NovaGuard Server (Go Version)

سرور NovaGuard با زبان Go برای لینوکس

## ویژگی‌ها

- پیاده‌سازی کامل پروتکل NovaGuard با Go
- رمزنگاری ChaCha20Poly1305
- پشتیبانی از TLS/SSL
- مدیریت session key برای هر کلاینت
- محدودیت هر کانفیگ به یک دستگاه
- تولید کانفیگ ng://
- پشتیبانی از TCP و UDP
- کاملاً سازگار با کلاینت‌های اندروید، لینوکس و ویندوز

## پیش‌نیازها

- Go 1.21 یا بالاتر
- OpenSSL (برای تولید گواهی)

## نصب و راه‌اندازی
*نصب آسان
```bash
bash <(curl -Ls https://raw.githubusercontent.com/amirmsoud16/novaguard/main/install.sh)
```
1. **تولید گواهی SSL:**
```bash
chmod +x generate_cert.sh
./generate_cert.sh
```

2. **کامپایل سرور:**
```bash
chmod +x build.sh
./build.sh
```

3. **اجرای سرور:**
```bash
./novaguard-server
```

## تنظیمات

فایل `config.json` را ویرایش کنید:

```json
{
  "server": "0.0.0.0",
  "tcp_port": 3077,
  "udp_port": 3076,
  "config_id": "novaguard-config-001",
  "session_id": "session-001",
  "protocol": "novaguard-v1",
  "encryption": "chacha20-poly1305",
  "version": "1.0.0",
  "certfile": "novaguard.crt",
  "keyfile": "novaguard.key"
}
```

## فرمت کانفیگ استاندارد

### JSON Configuration
```json
{
  "server": "example.com",
  "tcp_port": 3077,
  "udp_port": 3076,
  "config_id": "unique-config-id",
  "session_id": "unique-session-id",
  "protocol": "novaguard-v1",
  "encryption": "chacha20-poly1305",
  "version": "1.0.0",
  "fingerprint": "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
}
```

### URL Format
```
ng://base64-encoded-config
```

## استفاده با کلاینت‌ها

1. سرور را اجرا کنید
2. کد ng:// نمایش داده شده را کپی کنید
3. در کلاینت مورد نظر، کد را وارد یا QR Code را اسکن کنید
4. دکمه Connect را بزنید

## امنیت

- هر کانفیگ فقط برای یک دستگاه قابل استفاده است
- رمزنگاری ChaCha20Poly1305 برای تمام ترافیک
- TLS/SSL برای اتصال اولیه
- Session key تصادفی برای هر اتصال
- Certificate fingerprint verification

## رفع خطا

- مطمئن شوید پورت‌ها روی فایروال باز هستند
- گواهی SSL را بررسی کنید
- لاگ‌ها را برای تشخیص مشکل بررسی کنید

## توسعه

برای اضافه کردن قابلیت‌های جدید:

1. کد را در `main.go` ویرایش کنید
2. دوباره کامپایل کنید: `./build.sh`
3. سرور را ری‌استارت کنید

## لایسنس

این پروژه تحت لایسنس MIT منتشر شده است. 
