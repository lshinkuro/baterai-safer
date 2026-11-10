# CI/CD Poni Lite ke App Store

Status: **pipeline siap, belum pernah upload sungguhan.** Penghalang terakhir: private key sertifikat Mac Installer Distribution belum ada di Mac pengembang. Build Lite juga belum diuji di dalam sandbox.

Pipeline ini dijalankan dari Mac pengembang. `Makefile` dan `.env.appstore` sengaja hanya ada di Mac itu (lewat `.git/info/exclude`), tidak ikut ter-commit. Versi DMG dan Homebrew tetap memakai alur rilis biasa dan tidak terpengaruh.

## Kenapa ada Poni Lite

Versi penuh tidak bisa masuk App Store: helper root dan SMC, API privat `PowerUI`, proses di luar sandbox, kontrol aplikasi lain lewat AppleScript, dan updater sendiri. Lite adalah build yang sama dengan flag `LITE`.

| Ikut di Lite | Dibuang |
|---|---|
| Home, Fokus, Rapat, Catatan lokal, Dev Utils, Ibadah | Batas pengisian dan helper root |
| Pemilih warna, Tetap menyala, Belajar Bahasa, Todo, Gabut, Self-care | Musik, AI, Clipboard, Shelf, Git, Stats |
| Kamera cermin, panel pengaturan | Cleaner, Sistem, updater, sinkron Apple Notes, OCR, login otomatis |

Daftarnya ada di `enum Lite` (`Sources/baterai-safer/UI.swift`). Fitur baru yang butuh akses di luar sandbox harus ditambahkan ke `Lite.cutTabs` atau `Lite.cutTools`, atau dibungkus `#if !LITE`.

## Yang dibutuhkan untuk upload

| Komponen | Fungsi | Disimpan di |
|---|---|---|
| Sertifikat **Apple Distribution** | Menandatangani `Poni.app` | Keychain, lengkap dengan private key |
| Sertifikat **Mac Installer Distribution** | Menandatangani `Poni.pkg` | Keychain, lengkap dengan private key |
| Provisioning profile **Mac App Store** | Mengikat App ID, tim, dan sertifikat Apple Distribution. Ditanam ke dalam app | File, path-nya di `PROVISION_PROFILE` |
| API key App Store Connect | Izin `altool` untuk validasi dan upload | `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` |

Jangan tertukar dengan Mac Development (hanya untuk development) atau Developer ID Installer (untuk distribusi di luar App Store).

### Jenis file

| File | Isi | Asal |
|---|---|---|
| `.certSigningRequest` (CSR) | Permintaan sertifikat. Private key-nya tetap di Mac pembuat CSR | Keychain Access → Certificate Assistant |
| `.cer` | Sertifikat saja, **tanpa private key** | Diunduh dari portal Apple |
| `.p12` | Sertifikat **dan** private key, dilindungi password | Diekspor dari Keychain Access di Mac pembuat sertifikat |
| `.p8` | Private key API. Hanya untuk login ke App Store Connect, tidak bisa menandatangani | Dibuat di App Store Connect, hanya bisa diunduh sekali |

Apple tidak menyimpan private key, jadi `.p12` tidak bisa diunduh dari portal dan tidak bisa dibuat ulang dari `.cer`. Sertifikat hanya bisa dipakai menandatangani di Mac yang punya private key-nya.

## Persiapan (sekali)

1. Pakai tim Apple yang memegang app record di App Store Connect. Pastikan nama tim di kanan atas portal sudah benar sebelum membuat apa pun, dan jangan pakai sertifikat kantor.
2. Di portal developer, buat App ID dan provisioning profile **Mac App Store** yang memuat sertifikat Apple Distribution.
3. Siapkan sertifikat Apple Distribution dan Mac Installer Distribution dengan salah satu cara di bawah.
4. Di App Store Connect, buat aplikasi dengan App ID tadi. Nama harus unik; kalau "Poni" sudah dipakai, gunakan variasi seperti "Poni Notch".
5. Di App Store Connect → Users and Access → Integrations, buat API key, lalu simpan di `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`.
6. Isi `.env.appstore`, dan ganti semua nilai berawalan `ISI_`.

### Mendapatkan sertifikat

**Kalau slot masih kosong**, buat dari Mac ini:

1. Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority, pilih **Saved to disk**.
2. Di portal, klik **+**, pilih jenis sertifikat, lalu unggah CSR tadi.
3. Unduh `.cer` dan klik dua kali untuk memasangnya.
4. Ekspor `.p12` dari Keychain Access sebagai cadangan.

**Kalau slot penuh** (pilihannya abu-abu di portal), ada dua cara:

- Minta `.p12` dari pembuat sertifikat yang ada, lalu impor lewat Keychain Access → File → Import Items. Pembuatnya terlihat di halaman detail sertifikat. Mengunduh `.cer`-nya saja tidak cukup.
- Kalau pembuatnya tidak bisa dihubungi, minta admin tim me-revoke sertifikat itu, lalu buat yang baru. Setelah di-revoke, pemakai lain tidak bisa lagi menandatangani dengan sertifikat itu. Kuota tiap jenis sertifikat terpisah, jadi me-revoke jenis lain tidak menambah slot.

### Mengecek sertifikat

```
security find-identity -v | grep -i installer
```

Baris yang muncul adalah nilai untuk `INSTALLER_SIGN_ID`. Jangan tambahkan `-p codesigning`, karena opsi itu menyembunyikan sertifikat installer. Kalau kosong padahal sertifikatnya terlihat di Keychain Access, berarti private key-nya tidak ada di Mac ini.

### Mengatur API key (`.p8`)

1. Di App Store Connect → Users and Access → Integrations → App Store Connect API, buka **Team Keys** dan klik **+**. Beri peran **App Manager**.
2. Klik **Download API Key**. File `AuthKey_<KEY_ID>.p8` hanya bisa diunduh sekali.
3. Pindahkan file-nya ke tempat yang dicari `altool`, lalu batasi izinnya:

   ```
   mkdir -p ~/.appstoreconnect/private_keys
   mv ~/Downloads/AuthKey_<KEY_ID>.p8 ~/.appstoreconnect/private_keys/
   chmod 600 ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
   ```

4. Salin **Key ID** dan **Issuer ID** dari halaman yang sama ke `.env.appstore`:

   ```
   ASC_KEY_ID=<KEY_ID>
   ASC_ISSUER_ID=<ISSUER_ID>
   ```

5. Uji dengan `make appstore-validate`, setelah sertifikat installer juga siap.

Kalau file `.p8` hilang, revoke key itu di halaman yang sama lalu buat key baru. Jangan pernah menaruh `.p8` di dalam repo.

### Mengatur sertifikat dari `.p12`

Di Mac pembuat sertifikat:

1. Buka Keychain Access, pilih keychain **login**, lalu tab **My Certificates**.
2. Pastikan sertifikatnya punya panah yang berisi private key. Kalau tidak ada, Mac itu bukan pemegang key-nya.
3. Klik kanan sertifikat, pilih **Export**, simpan sebagai `.p12`, lalu buat password.
4. Kirim file dan password-nya lewat jalur terpisah.

Di Mac yang akan menandatangani:

1. Impor file-nya, lalu masukkan password `.p12` saat diminta:

   ```
   security import ~/Downloads/<NAMA>.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -T /usr/bin/productbuild
   ```

2. Cek dengan `security find-identity -v`, lalu salin namanya ke `.env.appstore`:

   ```
   APPSTORE_SIGN_ID=<nama atau SHA-1 sertifikat Apple Distribution>
   INSTALLER_SIGN_ID=<nama sertifikat installer>
   ```

3. Kalau ada dua sertifikat Apple Distribution bernama sama, isi `APPSTORE_SIGN_ID` dengan SHA-1 sertifikat yang tercantum di provisioning profile.
4. Kalau macOS meminta izin Keychain saat tanda tangan pertama, pilih **Always Allow**.
5. Hapus `.p12` dari Downloads setelah diimpor, atau simpan di password manager. Jangan pernah menaruhnya di dalam repo.

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

`VERSION` diambil dari tag git terakhir dan `BUILD_NUMBER` dari jumlah commit. Untuk upload ulang dari commit yang sama, naikkan nomor build: `make appstore-upload BUILD_NUMBER=100`.

`make appstore-upload` menjalankan semuanya berurutan, jadi untuk rilis cukup satu perintah ini:

1. Memastikan git bersih dan semua nilai `.env.appstore` terisi.
2. Build debug dan selftest versi penuh.
3. Build Lite, lalu gagal kalau binary memuat kode terlarang.
4. Menambahkan bundle ID, nomor build, profile, dan entitlement sandbox, lalu menandatangani `Poni.app`.
5. Membungkus jadi `.build/appstore/Poni.pkg` dan menandatanganinya dengan sertifikat installer.
6. Validasi ke App Store Connect, lalu upload.

Kalau baru ingin mengecek tanpa mengirim build, pakai `make appstore-validate`.

### Cara memakai perintah `make`

Jalankan dari root repo. `make` tanpa argumen menampilkan daftar perintah. Kalau muncul `No rule to make target`, berarti `Makefile` belum ada di Mac itu, karena file ini tidak ikut ter-commit.

Tiap perintah `appstore-*` otomatis menjalankan tahap sebelumnya, jadi tidak perlu dijalankan satu per satu.

| Perintah | Kapan dipakai | Butuh | Hasil |
|---|---|---|---|
| `make check` | Memastikan versi penuh masih lolos build dan selftest | Tidak ada | Build debug di `.build/debug` |
| `make lite` | Mencoba Lite di Mac sendiri | Tidak ada | `.build/Poni.app`, belum sandbox dan belum ditandatangani untuk App Store |
| `make appstore-app` | Mengecek sandbox dan tanda tangan app tanpa `.pkg` | `BUNDLE_ID`, `TEAM_ID`, `APPSTORE_SIGN_ID`, `PROVISION_PROFILE` | `.build/appstore/Poni.app` |
| `make appstore-pkg` | Membuat installer tanpa menghubungi Apple | Semua di atas, `INSTALLER_SIGN_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID` | `.build/appstore/Poni.pkg` |
| `make appstore-validate` | Bertanya ke Apple apakah build akan diterima, tanpa mengirimnya | Semua di atas, file `.p8`, internet | Hasil validasi di terminal |
| `make appstore-upload` | Mengirim build ke App Store Connect | Semua di atas, git bersih | Build masuk ke App Store Connect |

Urutan yang disarankan untuk rilis:

```
make check
make lite && open .build/Poni.app
make appstore-validate
make appstore-upload
```

Tutup Poni yang terpasang sebelum membuka hasil `make lite`.

Nilai `VERSION` dan `BUILD_NUMBER` bisa ditimpa untuk satu kali jalan:

```
make appstore-upload VERSION=0.18.2 BUILD_NUMBER=100
```

`make appstore-app` selalu menghapus isi `.build/appstore` lebih dulu, jadi salin `Poni.pkg` ke tempat lain kalau ingin menyimpannya.

## Kalau gagal

| Pesan | Penyebab dan solusi |
|---|---|
| `git tree is not clean` | Commit perubahan, atau tambahkan file lokal ke `.git/info/exclude` |
| `isi <NAMA> di .env.appstore` | Nilainya kosong atau masih berawalan `ISI_` |
| `PROVISION_PROFILE not found` | Path profile salah atau file-nya sudah dipindah |
| `forbidden code in the Lite binary` | Ada kode terlarang yang belum dibungkus `#if !LITE` |
| `refusing: signed with the company certificate` | Nilai sign ID menunjuk sertifikat kantor. Ganti ke sertifikat tim yang benar |
| `productbuild` tidak menemukan identity | Sertifikat installer belum terpasang, private key-nya tidak ada, atau `INSTALLER_SIGN_ID` tidak persis sama |
| Nomor build sudah pernah dipakai | Naikkan nomornya, misalnya `make appstore-upload BUILD_NUMBER=100` |

## Setelah upload

Upload tidak langsung tampil ke publik. Tunggu build selesai diproses di App Store Connect.

- **TestFlight:** buka tab TestFlight, jawab pertanyaan enkripsi kalau diminta, lalu tambahkan build ke grup penguji.
- **App Store:** isi deskripsi, screenshot, dan label privasi, pilih build-nya, dan klik Submit for Review.

## Mencoba Lite di Mac sendiri

`make lite && open .build/Poni.app`, setelah menutup Poni yang terpasang. Build ini belum memakai sandbox dan memakai pengaturan yang sama dengan Poni utama.

Sebelum merilis versi penuh, tidak perlu membersihkan apa pun: `scripts/dmg.sh` membangun ulang `.build/Poni.app` dari versi penuh.
