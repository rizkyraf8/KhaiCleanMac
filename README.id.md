<p align="center">
  <img src="docs/logo.png" width="128" alt="Logo KhaiCleanMac">
</p>

<h1 align="center">KhaiCleanMac</h1>

<p align="center">
  Aplikasi pembersih Mac source-available dengan tampilan pastel yang lembut.<br>
  Swift + SwiftUI native · macOS 15+ · Lisensi PolyForm Noncommercial
</p>

<p align="center"><a href="README.md">Read in English</a></p>

<p align="center">
  <img src="docs/screenshots/smartScan.png" width="820" alt="Smart Scan">
</p>

## Fitur

| Modul | Fungsi |
|---|---|
| **Smart Scan** | Mencari cache aplikasi (`~/Library/Caches`), log (`~/Library/Logs`), sampah Xcode (DerivedData, Device Support, cache simulator), dan installer `.dmg`/`.pkg` lama di Downloads. Cache Chrome dibersihkan per entri: hanya cache web lama dan Code Cache usang yang dibuang |
| **File Besar** | Mencari file di atas 50 MB, 100 MB, 500 MB, atau 1 GB di folder pribadi, dengan filter jenis file dan urutan |
| **Duplikat** | Mencari file yang isinya identik, dan secara default menyimpan salinan yang paling lama |
| **Developer** | Mencari dependensi proyek lama (`node_modules`, `Pods`, `.build`, `target`) dan arsip Xcode. Cache package manager (Gradle, npm, Yarn, Cargo, Maven, dll.) dibersihkan per entri: hanya library yang tidak dipakai 30, 60, atau 90 hari yang dihapus, jadi proyek aktif tetap cepat di-build. Juga menampilkan perintah Terminal untuk Homebrew, Docker, simulator, dan Go |
| **Space Lens** | Menampilkan peta treemap isi folder (default: Home). Klik dua kali untuk masuk ke folder, dan pakai breadcrumb untuk kembali |
| **Uninstaller** | Menghapus aplikasi dari `/Applications` dan `~/Applications` beserta file sisanya (Application Support, Caches, Preferences, Containers, Group Containers, LaunchAgents, dll.) |
| **Memori** | Menampilkan tekanan memori, rincian RAM, dan pemakaian swap, plus daftar app yang paling banyak memakai RAM (termasuk proses pembantunya) dengan tombol Keluar. Bisa juga melepas cache file dengan `purge`, yang butuh password admin |
| **Menu bar** | Menampilkan persentase CPU di menu bar, dengan panel berisi CPU, memori, disk, dan baterai. Aplikasi tetap berjalan di sana setelah jendela ditutup |
| **Pengingat** | Memeriksa sampah setiap hari, minggu, atau bulan, lalu mengirim notifikasi kalau sudah lebih dari 1, 5, atau 10 GB. Tidak pernah menghapus apa pun sendiri |
| **Pengaturan** | Bahasa (Bahasa Indonesia atau English), tampilan (Ikuti Sistem, Terang, atau Gelap), buka saat login, menu bar, dan pengingat. Buka dengan ⌘, atau dari bagian bawah sidebar |

Perubahan di setiap versi tercatat di [CHANGELOG.md](CHANGELOG.md). Versi yang sedang dipakai ditampilkan di bagian bawah sidebar dan di Pengaturan → Tentang.

<p align="center">
  <img src="docs/screenshots/smartScan-results.png" width="410" alt="Hasil Smart Scan">
  <img src="docs/screenshots/largeFiles-dark.png" width="410" alt="File Besar dalam mode gelap">
</p>
<p align="center">
  <img src="docs/screenshots/duplicates.png" width="410" alt="Duplikat">
  <img src="docs/screenshots/menubar.png" width="200" alt="Panel menu bar">
</p>

## Keamanan

- **Tidak ada yang dihapus permanen.** Semua item dipindahkan ke Trash, jadi masih bisa dikembalikan sebelum Trash dikosongkan.
- **Tidak ada yang dihapus tanpa persetujuan.** Setiap modul menampilkan apa saja yang ditemukan dan meminta konfirmasi dulu.
- **Aplikasi yang sedang terbuka dilindungi.** Smart Scan mengunci cache dan log milik aplikasi yang sedang berjalan, lalu mengeceknya lagi tepat sebelum membersihkan.
- **Cache Chrome yang aktif tetap aman.** Yang dibuang hanya entri cache web yang tidak dipakai lebih lama dari batas pilihanmu (7, 30, atau 90 hari) dan Code Cache dari versi Chrome sebelumnya, dan hanya saat Chrome tertutup. Versi Chrome lama di dalam Chrome.app tidak pernah disentuh: selama update menunggu relaunch, versi "lama" itulah yang sedang berjalan, dan Chrome menghapusnya sendiri setelah relaunch.
- **Uninstaller tidak menampilkan aplikasi bawaan Apple**, dan menolak menghapus aplikasi yang sedang berjalan.
- **Duplikat ditangani dengan hati-hati:**
  - Symlink dan hard link tidak dianggap salinan.
  - Folder proyek dan bundle (`node_modules`, `Pods`, `build`, `vendor`, `.app`, `.framework`, dll.) dilewati.
  - File iCloud yang belum diunduh tidak dibaca.
  - Minimal satu salinan di setiap grup selalu disimpan.

### Cara mendeteksi duplikat

File dibandingkan berdasarkan isinya, bukan namanya, dalam tiga tahap:

1. **Ukuran.** Hanya file yang ukurannya sama yang mungkin duplikat.
2. **64 KB pertama.** SHA-256 dari 64 KB pertama dengan cepat menyingkirkan sebagian besar file yang tersisa.
3. **Seluruh isi.** SHA-256 dari seluruh file memastikan isinya benar-benar sama.

Foto yang mirip atau lagu yang sama dengan format berbeda tidak terdeteksi. Di APFS, salinan dari Finder bisa berupa clone yang berbagi blok disk, jadi menghapusnya bisa membebaskan ruang yang lebih kecil daripada ukuran filenya.

## Kebutuhan

- macOS 15 Sequoia atau lebih baru
- Xcode 16 atau lebih baru (toolchain Swift 6)

## Build dan menjalankan

```bash
git clone https://github.com/rizkyraf8/KhaiCleanMac.git
cd KhaiCleanMac
./scripts/build-app.sh
open build/KhaiCleanMac.app
```

`build-app.sh` meng-compile versi release, membuat ikon aplikasi, dan menyusun `build/KhaiCleanMac.app`. Saat pengembangan, bisa juga memakai `swift run` atau membuka `Package.swift` di Xcode.

Kalau Anda memakai [swiftly](https://github.com/swiftlang/swiftly), file `.swift-version` membuat swiftly memakai toolchain Swift dari Xcode di folder ini.

### Akses Disk Penuh

Beberapa folder hanya bisa dipindai dengan Akses Disk Penuh. Izinnya bisa diberikan di **System Settings → Privacy & Security → Full Disk Access**, dan tombol di sidebar langsung membuka halaman itu.

Build lokal di-sign secara *ad-hoc*. Karena itu, macOS melupakan izin tersebut setiap kali aplikasi dibangun ulang. Agar izin tetap berlaku setelah build ulang, pilih salah satu cara berikut:
- Buat sertifikat code signing bernama `KhaiCleanMac Local` (Keychain Access → Certificate Assistant → Create a Certificate → tipe *Code Signing*).
- Isi `KHAI_SIGN_IDENTITY` dengan identitas signing yang sudah Anda punya.

`build-app.sh` akan memakai sertifikat atau identitas itu kalau ditemukan.

### Snapshot debug

Build debug bisa merender setiap layar ke PNG tanpa membuka jendela:

```bash
swift build && .build/debug/KhaiCleanMac --snapshot ./snapshots [--dark] [--results]
```

`--results` juga menjalankan pemindaian (hanya membaca file) agar layar hasil ikut dirender. Layar hasil memuat nama file asli dari folder pribadi Anda, jadi periksa dulu sebelum membagikannya.

## Struktur proyek

```
Sources/KhaiCleanMac/
  App/         entry point, pengaturan (bahasa, tampilan), snapshot debug
  Design/      tema (palet, background, kartu), komponen, gambar logo
  Models/      modul, kategori sampah, jenis file, hasil pemindaian
  Services/    pemindai (sampah, file besar, duplikat, aplikasi, ruang disk),
               pencocokan app yang berjalan, Trash, izin, monitor sistem
  ViewModels/  state @Observable untuk tiap modul
  Views/       sidebar dan satu view per modul, panel menu bar
scripts/       build-app.sh, make-icon/
Resources/     Info.plist, AppIcon.icns, logo
docs/          gambar untuk README
```

Logo digambar lewat kode di `Design/LogoArtwork.swift`. Ikon aplikasi dan logo di sidebar sama-sama berasal dari file itu. `build-app.sh` membuat ulang `AppIcon.icns` setiap kali file itu berubah.

## Rencana berikutnya

- Pengelola Login Items dan LaunchAgents
- Mengosongkan Trash dan membersihkan cache sistem lewat privileged helper
- Sign dengan Developer ID dan notarization untuk DMG yang bisa diunduh

## Kontribusi

Issue dan pull request sangat diterima. Mohon pertahankan aturan keamanan di atas: semua fitur yang menghapus file harus memindahkannya ke Trash dan harus dikonfirmasi pengguna.

## Lisensi

[PolyForm Noncommercial 1.0.0](LICENSE) © 2026 Rizky Aditya Fahreza

KhaiCleanMac adalah proyek independen. Proyek ini tidak berafiliasi dengan, dan tidak didukung oleh, MacPaw maupun CleanMyMac.
