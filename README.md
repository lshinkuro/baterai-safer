# Baterai Safer

Aplikasi menu bar macOS (Apple Silicon) untuk menjaga kesehatan baterai: charge limiter, discharge, heat protection, sailing, kalibrasi, dan top up.

## Install

```sh
brew tap lshinkuro/baterai-safer https://github.com/lshinkuro/baterai-safer
brew trust lshinkuro/baterai-safer   # Homebrew baru wajib trust tap pihak ketiga
brew install baterai-safer
brew services start baterai-safer   # jalankan di menu bar + otomatis saat login
ln -sf "$(brew --prefix)/opt/baterai-safer/Baterai Safer.app" /Applications/   # opsional: Launchpad/Spotlight
```

Klik ikon baterai di menu bar → **Install helper…** (minta password admin sekali). Helper adalah daemon root yang menulis ke SMC, jadi batas tetap berlaku saat aplikasi ditutup.

Atau lewat terminal: `sudo baterai-safer install-daemon`.

### Tanpa Homebrew (DMG)

Download `BateraiSafer.dmg` dari [Releases](https://github.com/lshinkuro/baterai-safer/releases/latest), buka, lalu seret **Baterai Safer** ke **Applications**. Aplikasi otomatis berjalan saat login (bisa dimatikan di System Settings → General → Login Items).

Aplikasi belum ditandatangani Developer ID, jadi saat pertama dibuka macOS akan memblokirnya. Buka System Settings → Privacy & Security → **Open Anyway**, atau jalankan:

```sh
xattr -dr com.apple.quarantine "/Applications/Baterai Safer.app"
```

Update: download DMG terbaru dan timpa aplikasi di Applications. Uninstall: `sudo "/Applications/Baterai Safer.app/Contents/MacOS/baterai-safer" uninstall-daemon`, lalu hapus aplikasinya.

Membuat DMG sendiri: `scripts/dmg.sh <versi>` → `.build/BateraiSafer.dmg`.

## Update

Aplikasi mengecek rilis baru saat dibuka dan setiap 6 jam, lalu memasangnya otomatis dan memulai ulang (bisa dimatikan di Tools → Update). Instalasi Homebrew diperbarui lewat `brew upgrade`; instalasi DMG mengunduh DMG dari GitHub Releases dan memverifikasi SHA-256-nya sebelum mengganti aplikasi. Update ditunda selama sesi Fokus berjalan.

Manual:

```sh
brew update                          # ambil versi terbaru dari tap
brew upgrade baterai-safer
brew services restart baterai-safer  # jalankan versi baru
```

Helper (root) tidak perlu dipasang ulang: ia menjalankan binary di `$(brew --prefix)/opt/baterai-safer`, yang otomatis menunjuk ke versi baru, dan dimulai ulang saat reboot. Pengaturan, riwayat, dan token di Keychain tetap tersimpan.

Aplikasi belum ditandatangani Developer ID Apple, jadi setelah update macOS bisa meminta ulang izin (Automation untuk Spotify/Music, akses Keychain untuk token). Pilih **Izinkan / Always Allow**.

Cek versi yang terpasang: `brew list --versions baterai-safer`.

Kalau `brew install`/`upgrade` gagal dengan error compile, pastikan Command Line Tools terbaru (`softwareupdate --list`) lalu coba lagi; laporkan di Issues bila masih gagal.

## Fitur

| Fitur | Keterangan |
|---|---|
| Charge limit | Berhenti mengisi di batas (mis. 80%), Mac jalan pakai daya charger |
| Sailing | Isi ulang hanya setelah turun ke `batas − sailing` |
| Auto discharge | Pakai baterai walau charger tercolok sampai turun ke batas |
| Heat protection | Berhenti mengisi saat suhu baterai ≥ batas suhu |
| Top up | Isi sementara ke 100% |
| Kalibrasi | 100% → 10% → 100%, lalu kembali ke batas |
| Stop saat sleep | Pengisian dibekukan sebelum Mac sleep |
| Info | % kesehatan (kapasitas maks/desain), siklus, suhu |

### macOS 27+

Firmware macOS 27 mengunci key SMC untuk menghentikan pengisian (`CHTE`, `CH0B`, `CH0C`). Di sistem ini Baterai Safer otomatis memakai **Charge Limit bawaan macOS** (80, 85, 90, 95, 100%), yang tetap berlaku saat sleep dan saat aplikasi ditutup. Discharge dan kalibrasi memakai key `CHIE` (memutus daya charger), jadi selama itu Mac berjalan pakai baterai. Sailing dan heat protection tidak tersedia di mode ini (heat protection dengan memutus charger membuat Mac tidak bisa dicas sama sekali).

Top up dan kalibrasi di macOS 27 membutuhkan aplikasi menu bar tetap berjalan.

## Menu bar

Panel menu bar punya 4 tab: **Baterai** (fitur di atas + grafik riwayat), **Sistem** (memori, CPU, disk, proses terberat yang bisa ditutup), **Cleaner** (bersihkan cache/log/DerivedData/DeviceSupport/npm/Trash, simulator tak terpakai, analisis disk per folder, file > 200 MB, uninstall aplikasi beserta file sisanya ke Trash), dan **Tools** (cegah sleep, file tersembunyi, ikon desktop, dark mode, screenshot area).

## Notch

Arahkan kursor ke notch (atau tengah atas layar tanpa notch) untuk membuka, atau pilih **Klik** di Tools → Fitur → Buka notch:

| Tab | Isi |
|---|---|
| Musik | Spotify / Apple Music: album art, kontrol, lirik berjalan (lrclib.net) |
| Rapat | Kalender bulanan: tambah rapat di tanggal & jam tertentu, atur pengingat per acara (tanpa pengingat, 5/10/15/30 menit, 1 jam sebelum). Tersimpan ke Kalender macOS, jadi ikut sinkron iCloud dan notifikasinya tetap muncul walau aplikasi ditutup |
| Fokus | Pomodoro 25/50/90 menit, niat sesi ("Mau mengerjakan apa?"), blokir aplikasi pengganggu selama fokus (Slack, WhatsApp, Discord, … bisa diatur), refleksi setelah sesi yang tersimpan ke catatan **Jurnal Fokus**, otomatis dijeda saat rapat di Kalender dimulai, niat sesi tampil di notch yang tertutup, streak, grafik 7 hari |
| AI | Chat dengan CLI AI yang terpasang (Claude Code, Kiro), tanpa akses tool. **Pemakaian AI (eksperimental):** halaman Pemakaian berisi token Claude Code hari ini, 7 hari, per model, dan berapa yang dipakai chat aplikasi ini. Bisa dimatikan di Tools → Fitur → Pemakaian AI β |
| Catatan | Quick notes multi-halaman, tersinkron ke folder **"Baterai Safer"** di Apple Notes (muncul juga di iPhone / iCloud), "Rapikan dengan AI". Catatan dengan gambar atau tabel hanya bisa dibaca di notch (edit di Notes). Tanpa izin Automation → Notes, catatan tetap tersimpan lokal |
| Dev Utils | Tempel apa saja: JSON rapi/ringkas, decode JWT (+ cek kedaluwarsa), Base64, URL, timestamp, SHA-256/MD5, UUID — semua offline |
| Clipboard | Riwayat copy, pin, OCR teks di gambar; isi dari password manager diabaikan |
| Shelf | Seret file ke notch, seret keluar, atau AirDrop |
| Git | Status repo, fetch/pull/push, commit dengan pesan dari AI; review PR GitHub (`gh`) dan Bitbucket Server (HTTP access token di Keychain) dengan AI, kirim review & merge |
| Stats | Baterai, CPU, memori, disk |
| Lainnya | **Notif baterai penuh** ("boleh cabut charger" saat mencapai batas), **Mic Mute** untuk semua aplikasi (⌃⌥M), **Kamera cermin** sebelum rapat, **Color picker** (hex langsung tersalin), **Tetap menyala** 30 menit / 1 jam / 2 jam / sampai jam tertentu, **Download** (notif saat selesai + Tampilkan di Finder), **Eject USB**, **Belajar Bahasa** (Inggris, Spanyol & Jepang: target kata harian + streak, flashcard dengan jadwal hafalan, kuis arti kata, **latihan soal TOEFL / DELE / JLPT** dengan pembahasan, ngobrol lewat teks atau **suara dengan orb** yang mengoreksi kalimatmu, **Progres** (kata hafal, akurasi 7 hari, riwayat skor tes), pilihan AI **Apple Intelligence** (di Mac) atau **Claude** (lewat Claude Code), dan pilihan suara) |

Shortcut: ⌃⌥Space buka/tutup, ⌃⌥N Catatan, ⌃⌥D Dev Utils, ⌃⌥V Clipboard, ⌃⌥A AI, ⌃⌥F Fokus, ⌃⌥G Git, ⌃⌥R Rapat, ⌃⌥S mulai/jeda fokus, ⌃⌥M bisukan mic, **⌃⌥T salin teks dari layar (OCR)**, Esc menutup.

Rapat berikutnya dari Kalender muncul di samping kamera 10 menit sebelum mulai, dengan tombol **Join** untuk Zoom/Meet/Teams/Webex (perlu izin Kalender).

Notch bisa dimatikan di tab Tools, begitu juga tiap fitur (tab notch, Rapat, tab Sistem/Cleaner): fitur yang dimatikan hilang dan proses latarnya berhenti. Now Playing butuh izin Automation untuk Spotify/Music.

## CLI

```
baterai-safer                    # aplikasi menu bar
baterai-safer status             # info baterai
baterai-safer ai-usage           # pemakaian token Claude Code 7 hari
baterai-safer selftest           # cek logika
sudo baterai-safer install-daemon / uninstall-daemon
```

## Uninstall

```sh
sudo baterai-safer uninstall-daemon   # pengisian dikembalikan normal
brew services stop baterai-safer
brew uninstall baterai-safer
```

**macOS 27:** uninstall tidak mengembalikan Charge Limit bawaan macOS. Batas terakhir (mis. 80%) tetap aktif, jadi baterai berhenti mengisi di situ. Kembalikan ke 100% di System Settings → Battery → Charge Limit.

Kalau sudah terlanjur `brew uninstall` tanpa `uninstall-daemon` dan charger tidak mau mengisi, jalankan:

```sh
sudo launchctl bootout system/io.github.lshinkuro.baterai-safer
sudo rm /Library/LaunchDaemons/io.github.lshinkuro.baterai-safer.plist
```

Sejak v0.6.2 daemon membersihkan dirinya sendiri dalam beberapa detik setelah aplikasinya dihapus.

## Catatan

Memakai API privat Apple (AppleSMC, PowerUI) yang bisa berubah di update macOS. Hanya Apple Silicon. Gunakan dengan risiko sendiri.
