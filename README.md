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

## Update

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

Firmware macOS 27 mengunci key SMC untuk menghentikan pengisian (`CHTE`, `CH0B`, `CH0C`). Di sistem ini Baterai Safer otomatis memakai **Charge Limit bawaan macOS** (80, 85, 90, 95, 100%), yang tetap berlaku saat sleep dan saat aplikasi ditutup. Discharge, kalibrasi, dan heat protection memakai key `CHIE` (memutus daya charger), jadi selama itu Mac berjalan pakai baterai. Sailing tidak tersedia di mode ini.

Top up dan kalibrasi di macOS 27 membutuhkan aplikasi menu bar tetap berjalan.

## Menu bar

Panel menu bar punya 4 tab: **Baterai** (fitur di atas + grafik riwayat), **Sistem** (memori, CPU, disk, proses terberat yang bisa ditutup), **Cleaner** (bersihkan cache/log/DerivedData/DeviceSupport/npm/Trash, simulator tak terpakai, analisis disk per folder, file > 200 MB, uninstall aplikasi beserta file sisanya ke Trash), dan **Tools** (cegah sleep, file tersembunyi, ikon desktop, dark mode, screenshot area).

## Notch

Arahkan kursor ke notch (atau tengah atas layar tanpa notch) untuk membuka:

| Tab | Isi |
|---|---|
| Musik | Spotify / Apple Music: album art, kontrol, lirik berjalan (lrclib.net) |
| Fokus | Pomodoro 25/5, streak, grafik 7 hari |
| AI | Chat dengan CLI AI yang terpasang (Claude Code, Kiro), tanpa akses tool |
| Catatan | Quick notes multi-halaman, tersimpan otomatis, "Rapikan dengan AI" |
| Dev Utils | Tempel apa saja: JSON rapi/ringkas, decode JWT (+ cek kedaluwarsa), Base64, URL, timestamp, SHA-256/MD5, UUID — semua offline |
| Clipboard | Riwayat copy, pin, OCR teks di gambar; isi dari password manager diabaikan |
| Shelf | Seret file ke notch, seret keluar, atau AirDrop |
| Git | Status repo, fetch/pull/push, commit dengan pesan dari AI; review PR GitHub (`gh`) dan Bitbucket Server (HTTP access token di Keychain) dengan AI, kirim review & merge |
| Stats | Baterai, CPU, memori, disk |

Shortcut: ⌃⌥Space buka/tutup, ⌃⌥N Catatan, ⌃⌥D Dev Utils, ⌃⌥V Clipboard, ⌃⌥A AI, ⌃⌥F Fokus, ⌃⌥G Git, **⌃⌥T salin teks dari layar (OCR)**, Esc menutup.

Rapat berikutnya dari Kalender muncul di samping kamera 10 menit sebelum mulai, dengan tombol **Join** untuk Zoom/Meet/Teams/Webex (perlu izin Kalender).

Notch bisa dimatikan di tab Tools. Now Playing butuh izin Automation untuk Spotify/Music.

## CLI

```
baterai-safer                    # aplikasi menu bar
baterai-safer status             # info baterai
baterai-safer selftest           # cek logika
sudo baterai-safer install-daemon / uninstall-daemon
```

## Uninstall

```sh
sudo baterai-safer uninstall-daemon   # pengisian dikembalikan normal
brew services stop baterai-safer
brew uninstall baterai-safer
```

Di macOS 27, matikan juga Charge Limit di System Settings → Battery jika perlu.

## Catatan

Memakai API privat Apple (AppleSMC, PowerUI) yang bisa berubah di update macOS. Hanya Apple Silicon. Gunakan dengan risiko sendiri.
