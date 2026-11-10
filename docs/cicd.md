# CI/CD Poni Lite ke App Store

Status: **pipeline siap, belum pernah upload sungguhan** (menunggu akun Apple Developer). Build Lite juga belum diuji di dalam sandbox.

Pipeline ini dijalankan dari Mac pengembang. `Makefile` dan `.env.appstore` sengaja hanya ada di Mac itu (lewat `.git/info/exclude`), tidak ikut ter-commit. Versi DMG dan Homebrew tetap memakai alur rilis biasa dan tidak terpengaruh.

## Kenapa ada Poni Lite

Versi penuh tidak bisa masuk App Store: helper root dan SMC, API privat `PowerUI`, proses di luar sandbox, kontrol aplikasi lain lewat AppleScript, dan updater sendiri. Lite adalah build yang sama dengan flag `LITE`.

| Ikut di Lite | Dibuang |
|---|---|
| Home, Fokus, Rapat, Catatan lokal, Dev Utils, Ibadah | Batas pengisian dan helper root |
| Pemilih warna, Tetap menyala, Belajar Bahasa, Todo, Gabut, Self-care | Musik, AI, Clipboard, Shelf, Git, Stats |
| Kamera cermin, panel pengaturan | Cleaner, Sistem, updater, sinkron Apple Notes, OCR, login otomatis |

Daftarnya ada di `enum Lite` (`Sources/baterai-safer/UI.swift`). Fitur baru yang butuh akses di luar sandbox harus ditambahkan ke `Lite.cutTabs` atau `Lite.cutTools`, atau dibungkus `#if !LITE`.

## Persiapan (sekali)

1. Daftar Apple Developer Program sebagai Individual.
2. Di portal developer, buat App ID, sertifikat **Apple Distribution** dan **Mac Installer Distribution**, lalu unduh provisioning profile **Mac App Store**.
3. Di App Store Connect, buat aplikasi dengan App ID tadi. Nama harus unik; kalau "Poni" sudah dipakai, gunakan variasi seperti "Poni Notch".
4. Di App Store Connect → Users and Access → Integrations, buat API key, lalu simpan di `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`.
5. Isi `.env.appstore`, dan ganti semua nilai berawalan `ISI_`. Pakai sertifikat atas nama pribadi, bukan sertifikat kantor.

| Variabel | Isi |
|---|---|
| `BUNDLE_ID` | App ID, harus sama dengan di App Store Connect |
| `TEAM_ID` | Team ID 10 karakter |
| `APPSTORE_SIGN_ID` | Nama sertifikat Apple Distribution dari `security find-identity -v` |
| `INSTALLER_SIGN_ID` | Nama sertifikat installer dari `security find-identity -v` |
| `PROVISION_PROFILE` | Path file provisioning profile |
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | Dari halaman API key |

## Perintah

| Perintah | Fungsi |
|---|---|
| `make check` | Build debug dan selftest versi penuh |
| `make lite` | Build Lite, gagal kalau ada kode terlarang di binary, lalu bungkus ke `.build/Poni.app` |
| `make appstore-app` | `Poni.app` versi sandbox yang ditandatangani |
| `make appstore-pkg` | Installer `.pkg` |
| `make appstore-validate` | Validasi ke App Store Connect |
| `make appstore-upload` | Validasi lalu upload, hanya kalau git bersih |

`VERSION` diambil dari tag git terakhir dan `BUILD_NUMBER` dari jumlah commit. Untuk upload ulang dari commit yang sama, naikkan nomor build: `make appstore-upload BUILD_NUMBER=90`.

## Setelah upload

Upload tidak langsung tampil ke publik. Build masuk ke App Store Connect, lalu isi deskripsi, screenshot, dan label privasi, pilih build-nya, dan klik Submit for Review.

## Mencoba Lite di Mac sendiri

`make lite && open .build/Poni.app`, setelah menutup Poni yang terpasang. Build ini belum memakai sandbox dan memakai pengaturan yang sama dengan Poni utama.

Sebelum merilis versi penuh, tidak perlu membersihkan apa pun: `scripts/dmg.sh` membangun ulang `.build/Poni.app` dari versi penuh.
