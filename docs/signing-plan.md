# Rencana: Developer ID + notarisasi

Status: **kode siap, menunggu sertifikat Developer ID dan profil notarisasi** (langkah 1–3). Tanpa `SIGN_ID`, rilis tetap ad-hoc seperti sebelumnya. Setelah langkah 1–3 selesai, rilis bertanda tangan dibuat dengan:

```sh
SIGN_ID="Developer ID Application: <nama> (<TEAMID>)" scripts/dmg.sh X.Y.Z
```

## Kenapa

- Pengguna DMG harus lewat System Settings → Privacy & Security → **Open Anyway** setiap pemasangan pertama.
- Tanda tangan ad-hoc berubah tiap build, jadi macOS bisa meminta ulang izin (Automation, Kalender, Kamera, Keychain) setelah update.
- Dengan Developer ID + notarisasi, Gatekeeper langsung mengizinkan dan izin bertahan antar-update.

## Keputusan yang sudah diambil

- **Nama tetap "Poni".** Distribusi di luar App Store tidak mewajibkan nama unik; pencarian sekilas tidak menemukan aplikasi macOS bernama Poni. Merek dagang (DJKI/USPTO) belum dicek — perlu kalau dikomersialkan.
- **Bundle ID tetap `io.github.lshinkuro.BateraiSafer`.** Menggantinya menghapus pengaturan dan izin semua pengguna lama; pengguna tidak pernah melihatnya.
- **Akun Individual atas nama pribadi**, bukan akun kantor. Sertifikat *Apple Distribution: PT. Bank Rakyat Indonesia* yang ada di keychain **tidak boleh** dipakai; script harus memilih sertifikat Developer ID secara eksplisit.
- **Homebrew tetap build dari source.** Build lokal tidak terkena karantina Gatekeeper, jadi tidak perlu sertifikat. (Opsional nanti: pindah ke Cask yang mengunduh DMG bertanda tangan.)

## Langkah pemilik akun (manual, sekali)

1. Daftar [Apple Developer Program](https://developer.apple.com/programs/) sebagai **Individual** ($99/tahun). Nama pengembang yang tampil = nama legal.
2. Xcode → Settings → Accounts → Manage Certificates → **+ → Developer ID Application**.
   Cek: `security find-identity -v -p codesigning | grep "Developer ID Application"`.
3. Buat *app-specific password* di account.apple.com, lalu simpan kredensial notarisasi:
   ```sh
   xcrun notarytool store-credentials poni --apple-id <apple-id> --team-id <TEAMID>
   ```

`notarytool` dan `stapler` sudah ada di Mac ini (dari Xcode).

## Perubahan kode

Langkah 1–4 sudah dikerjakan. Updater hanya memeriksa tim kalau aplikasi yang terpasang sudah bertanda tangan Developer ID, jadi pengguna versi ad-hoc tetap bisa update. Langkah 5 menunggu rilis bertanda tangan pertama.

1. **`Resources/Poni.entitlements`** (hardened runtime butuh izin eksplisit untuk fitur yang dipakai):
   - `com.apple.security.automation.apple-events` — Spotify/Music, Apple Notes, dark mode, Finder
   - `com.apple.security.device.camera` — Kamera cermin
   - `com.apple.security.device.audio-input` — latihan suara Belajar Bahasa
   - `com.apple.security.personal-information.calendars` — Rapat
   - `com.apple.security.personal-information.location` — jadwal sholat (lokasi otomatis)
2. **`scripts/bundle.sh`**: kalau env `SIGN_ID` di-set, tanda tangani dengan
   `codesign --force --options runtime --timestamp --entitlements Resources/Poni.entitlements --sign "$SIGN_ID"`;
   kalau tidak, tetap ad-hoc seperti sekarang (Homebrew dan build lokal tidak berubah).
3. **`scripts/dmg.sh`**: setelah `hdiutil create`, kalau `SIGN_ID` ada:
   ```sh
   codesign --sign "$SIGN_ID" --timestamp .build/Poni.dmg
   xcrun notarytool submit .build/Poni.dmg --keychain-profile poni --wait
   xcrun stapler staple .build/Poni.dmg
   ```
4. **`Updater.swift`** (opsional, disarankan): selain SHA-256, verifikasi `codesign --verify --deep --strict` dan Team ID aplikasi baru sebelum menimpa `/Applications/Poni.app`.
5. **README**: hapus instruksi "Open Anyway" / `xattr -dr com.apple.quarantine` untuk DMG.

## Verifikasi sebelum rilis bertanda tangan pertama

- `codesign -dv --verbose=4 .build/Poni.app` → `Authority=Developer ID Application: <nama>`, `flags=0x10000(runtime)`.
- `spctl -a -vv .build/Poni.app` → `accepted, source=Notarized Developer ID`.
- `xcrun stapler validate .build/Poni.dmg` → berhasil.
- Uji di Mac bersih (atau user baru): DMG terbuka tanpa peringatan; Musik (Automation), Rapat (Kalender), Kamera cermin, dan Belajar Bahasa (mikrofon) masih minta izin dan berfungsi — kalau satu fitur diam saja, entitlement-nya kurang.
- Helper root (`install-daemon`) masih bisa dipasang dan menulis SMC.

## Catatan transisi

- Update bertanda tangan **pertama** tetap meminta izin ulang sekali (identitas berubah dari ad-hoc ke Developer ID). Sebutkan di catatan rilis.
- Updater versi lama hanya memeriksa SHA-256 dari digest GitHub, jadi tetap bisa memasang DMG bertanda tangan.
