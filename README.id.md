<p align="center">
  <img src="docs/logo.png" width="128" alt="Logo KhaiCleanMac">
</p>

<h1 align="center">KhaiCleanMac</h1>

<p align="center">
  Aplikasi pembersih Mac source-available dengan tampilan pastel yang lembut.<br>
  Swift + SwiftUI native · macOS 15+ · Lisensi PolyForm Noncommercial
</p>

<p align="center">
  <a href="CHANGELOG.md"><img src="https://img.shields.io/github/v/tag/rizkyraf8/KhaiCleanMac?label=latest%20version&color=5edcc0" alt="Latest version"></a>
</p>

<p align="center"><a href="README.md">Read in English</a></p>

<p align="center">
  <img src="docs/screenshots/smartScan.png" width="820" alt="Smart Scan">
</p>

## Download

<p align="center">
  <a href="https://rizkyraf.id/projects/khaicleanmac"><img src="https://img.shields.io/badge/Download-KhaiCleanMac-8b7cf6?style=for-the-badge&logo=apple&logoColor=white" alt="Download KhaiCleanMac"></a>
</p>

Unduh versi terbaru KhaiCleanMac di **[rizkyraf.id/projects/khaicleanmac](https://rizkyraf.id/projects/khaicleanmac)**, lalu seret aplikasinya ke folder Applications. Lihat apa yang baru di [changelog](CHANGELOG.md).

- Butuh macOS 15 Sequoia atau lebih baru, di Mac dengan Apple silicon atau prosesor Intel (mulai 0.7.0; versi 0.6.1 ke bawah hanya untuk Apple silicon).
- Aplikasi ini belum di-notarize Apple, jadi macOS mungkin menahannya saat pertama kali dibuka. Buka **Pengaturan Sistem › Privasi & Keamanan**, lalu klik **Buka Saja**. Ini hanya perlu sekali.
- Saat pertama dibuka, panduan awal akan memandu pengaturan Akses Disk Penuh. Izin ini opsional, tapi beberapa pemindaian membutuhkannya.
- **Pembaruan:** sekali sehari aplikasi menanyakan versi terbaru ke `rizkyraf.id/api/projects/khaicleanmac/latest`. Kalau ada versi lebih baru, Beranda, sidebar, dan Pengaturan → Tentang menampilkan tombol **Perbarui**: aplikasi mengunduh DMG baru, mengecek checksum SHA-256, versi, dan tanda tangan kodenya, menggantikan dirinya, lalu terbuka lagi. Kalau ada pengecekan yang gagal, tidak ada yang diganti dan kamu bisa mengunduh manual. Yang dikirim hanya versi aplikasi, dan pengecekan ini bisa dimatikan di Pengaturan → Tentang. (Update di dalam aplikasi berlaku mulai 0.5.0; versi 0.4.0 ke bawah perlu satu kali unduh manual.)

## Fitur

| Modul | Fungsi |
|---|---|
| **Beranda** | Titik awal: kondisi disk dan memori, kesehatan baterai dan SSD, Smart Scan sekali klik, status Akses Disk Penuh, dan kartu untuk setiap fitur |
| **Smart Scan** | Mencari cache aplikasi (`~/Library/Caches`), log (`~/Library/Logs`), sampah Xcode (DerivedData, Device Support, cache simulator), installer `.dmg`/`.pkg` lama, Downloads lama, salinan lampiran Mail, backup iPhone/iPad dan file `.ipsw`, serta isi Trash. Cache browser (Chrome, Brave, Edge, Arc, Vivaldi, Firefox, Safari) dibersihkan per entri: hanya cache web lama dan Code Cache usang yang dibuang |
| **File Besar** | Mencari file di atas 50 MB, 100 MB, 500 MB, atau 1 GB di folder pribadi atau di disk lain, dengan filter jenis file dan urutan |
| **Duplikat** | Mencari file yang isinya identik, di folder pribadi atau di disk lain, dan secara default menyimpan salinan yang paling lama |
| **Developer** | Mencari dependensi proyek lama (`node_modules`, `Pods`, `.build`, `target`) arsip Xcode, serta runtime dan perangkat simulator Xcode (sering puluhan GB; dihapus lewat `simctl` milik Xcode sendiri). Cache package manager (Gradle, npm, Yarn, Cargo, Maven, dll.) dibersihkan per entri: hanya library yang tidak dipakai 30, 60, atau 90 hari yang dihapus, jadi proyek aktif tetap cepat di-build. Juga menampilkan perintah Terminal untuk Homebrew, Docker, dan Go |
| **Privasi** | Menghapus riwayat, cookie, dan isian formulir per browser (Chrome, Brave, Edge, Arc, Vivaldi, Firefox, Safari), hanya yang kamu centang dan hanya saat browser itu tertutup. Password, bookmark, alamat, dan kartu tidak pernah disentuh |
| **Space Lens** | Menampilkan peta treemap isi folder atau disk (default: Home). Klik dua kali untuk masuk ke folder, dan pakai breadcrumb untuk kembali |
| **Uninstaller** | Menghapus aplikasi dari `/Applications` dan `~/Applications` beserta file sisanya (Application Support, Caches, Preferences, Containers, Group Containers, LaunchAgents, dll.) |
| **Pembaruan App** | Mencari app yang punya versi lebih baru dengan membaca feed pembaruan Sparkle milik app itu sendiri, lalu membuka app-nya supaya app memasang pembaruannya sendiri. App dari App Store ditampilkan dengan pintasan ke halaman pembaruan App Store |
| **Ekstensi** | Menyalakan atau mematikan ekstensi aplikasi pihak ketiga (Safari, Finder Sync, menu Bagikan, Quick Look, widget, dll.), dan menghapus plug-in lama, Quick Action, dan screen saver dari `~/Library`. Plug-in di `/Library` hanya ditampilkan |
| **Riwayat** | Setiap pembersihan dicatat: apa yang dihapus, ukurannya, dan ke mana perginya. Yang masih ada di Trash bisa dikembalikan dengan **Kembalikan**, satu per satu atau satu sesi sekaligus, dan tidak pernah menimpa file baru di lokasi asal |
| **Login Items** | Menampilkan Login Items, LaunchAgents milikmu (bisa dimatikan atau dihapus), serta agent dan daemon sistem (hanya dilihat), dan menandai yang yatim karena app-nya sudah tidak ada |
| **Memori** | Menampilkan tekanan memori, rincian RAM, dan pemakaian swap, plus daftar app yang paling banyak memakai RAM (termasuk proses pembantunya) dengan tombol Keluar. Bisa juga melepas cache file dengan `purge`, yang butuh password admin |
| **Menu bar** | Menampilkan persentase CPU di menu bar, dengan panel berisi CPU, memori, disk, baterai, serta kesehatan baterai dan SSD. Aplikasi tetap berjalan di sana setelah jendela ditutup |
| **Pengingat** | Memeriksa sampah setiap hari, minggu, atau bulan, lalu mengirim notifikasi kalau sudah lebih dari 1, 5, atau 10 GB. Tidak pernah menghapus apa pun sendiri |
| **Pengaturan** | Bahasa (Bahasa Indonesia atau English), tampilan (Ikuti Sistem, Terang, atau Gelap), buka saat login, menu bar, pengingat, batas umur cache dan Downloads, serta mode "hapus permanen" yang opsional. Buka dengan ⌘, atau dari bagian bawah sidebar |
| **Panduan awal** | Muncul saat pertama kali dibuka: janji keamanan aplikasi, dan tutorial Akses Disk Penuh langkah demi langkah yang otomatis berubah hijau begitu izin diberikan. Bisa dibuka lagi dari Pengaturan → Tentang |

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

- **Trash adalah default.** Semua yang dibersihkan masuk Trash, jadi masih bisa dikembalikan sebelum Trash dikosongkan. Hapus permanen adalah pengaturan opsional yang harus dikonfirmasi dulu sebelum aktif, dan setiap konfirmasi pembersihan akan menyebutkannya. Item yang sudah ada di Trash hanya bisa dihapus permanen.
- **Tidak ada yang dihapus tanpa persetujuan.** Setiap modul menampilkan apa saja yang ditemukan dan meminta konfirmasi dulu.
- **Aplikasi yang sedang terbuka dilindungi.** Smart Scan mengunci cache dan log milik aplikasi yang sedang berjalan, lalu mengeceknya lagi tepat sebelum membersihkan.
- **Cache browser yang aktif tetap aman.** Yang dibuang hanya entri cache web yang tidak dipakai lebih lama dari batas pilihanmu (7, 30, atau 90 hari) dan Code Cache dari versi browser sebelumnya, dan hanya saat browser itu tertutup. Versi Chrome lama di dalam Chrome.app tidak pernah disentuh: selama update menunggu relaunch, versi "lama" itulah yang sedang berjalan, dan Chrome menghapusnya sendiri setelah relaunch.
- **Uninstaller tidak menampilkan aplikasi bawaan Apple**, dan menolak menghapus aplikasi yang sedang berjalan.
- **Login Items hanya mengubah milikmu.** Mematikan agent bisa dibatalkan. Agent dan daemon sistem hanya ditampilkan, tidak pernah diubah.
- **File pribadi tidak pernah dipilih otomatis.** Downloads lama, backup perangkat, installer, dan isi Trash tetap tidak terpilih sampai kamu memilihnya.
- **Pembersihan privasi harus dipilih sendiri.** Tidak ada yang dicentang otomatis, browser yang sedang terbuka dikunci, dan konfirmasi menyebutkan setiap browser dan jenis datanya. File masuk Trash (bisa dikembalikan dari Riwayat). Isian formulir Chromium dihapus dari dalam database-nya, dan konfirmasinya menyebutkan bahwa itu tidak bisa dikembalikan. Riwayat Firefox satu file dengan bookmark, jadi diserahkan ke Firefox.
- **Pembaruan App tidak pernah memasang apa pun sendiri.** Fitur ini hanya membaca feed pembaruan publik setiap app (tidak ada data tentang kamu atau app lain yang dikirim), lalu membuka app-nya. Updater milik app itulah yang mengecek tanda tangan unduhannya.
- **Disk lain dijaga dengan aturan yang sama.** Indeks Spotlight, Trash, backup Time Machine, dan folder sistem di disk itu dilewati dan tidak bisa dihapus. Disk dan disk image yang read-only tidak ditawarkan.
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

`build-app.sh` meng-compile versi release universal (Apple silicon dan Intel dalam satu app), membuat ikon aplikasi, dan menyusun `build/KhaiCleanMac.app`. Pakai `KHAI_ARCH=arm64` (atau `x86_64`) untuk build satu arsitektur yang lebih cepat. Saat pengembangan, bisa juga memakai `swift run` atau membuka `Package.swift` di Xcode.

Kalau Anda memakai [swiftly](https://github.com/swiftlang/swiftly), file `.swift-version` membuat swiftly memakai toolchain Swift dari Xcode di folder ini.

### Membuat DMG

```bash
./scripts/make-dmg.sh            # build aplikasinya dulu
./scripts/make-dmg.sh --skip-build   # memakai build/KhaiCleanMac.app yang sudah ada
```

Hasilnya `build/KhaiCleanMac-<versi>.dmg`, plus file checksum `.sha256` di sebelahnya. Saat DMG dibuka, tampil aplikasi, shortcut **Applications** untuk tempat menyeretnya, dan gambar latar berisi panah serta petunjuk instalasi.

Untuk menata jendela itu, skrip butuh izin mengontrol Finder. Jalankan skrip dari Terminal dan izinkan saat macOS bertanya, atau nyalakan di **Pengaturan Sistem › Privasi & Keamanan › Otomatisasi**. Tanpa izin itu DMG tetap berfungsi, hanya tata letaknya memakai bawaan Finder.

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

### Test

```bash
swift test
```

Test membuat folder palsu di direktori sementara dan tidak pernah menyentuh file asli atau Trash. Yang diuji: apa yang dipilih untuk dihapus (entri cache browser dan umurnya, Code Cache dari versi lama, duplikat vs link, folder vendor, kunci app yang berjalan, agent yatim) dan cara penghapusannya (folder Trash per kelompok, pengembalian file kalau Trash menolak, mode permanen). GitHub Actions menjalankannya di setiap push.

## Struktur proyek

```
Sources/KhaiCleanMac/
  App/         entry point, pengaturan (bahasa, tampilan), snapshot debug
  Design/      tema (palet, background, kartu), komponen, gambar logo
  Models/      modul, kategori sampah, jenis file, hasil pemindaian
  Services/    pemindai (sampah, file besar, duplikat, aplikasi, ruang disk, privasi browser),
               feed pembaruan app, kesehatan baterai dan disk, disk yang ter-mount,
               pencocokan app yang berjalan, Trash, izin, monitor sistem
  ViewModels/  state @Observable untuk tiap modul
  Views/       sidebar dan satu view per modul, panel menu bar
scripts/       build-app.sh, make-icon/
Resources/     Info.plist, AppIcon.icns, logo
docs/          gambar untuk README
```

Logo digambar lewat kode di `Design/LogoArtwork.swift`. Ikon aplikasi dan logo di sidebar sama-sama berasal dari file itu. `build-app.sh` membuat ulang `AppIcon.icns` setiap kali file itu berubah.

## Rencana berikutnya

- Membersihkan cache sistem, log sistem, dan agent sistem yang yatim lewat privileged helper
- Sign dengan Developer ID dan notarization untuk DMG yang bisa diunduh

## Kontribusi

Issue dan pull request sangat diterima! Baca dulu [CONTRIBUTING.md](CONTRIBUTING.md). Singkatnya:

- Pertahankan aturan keamanan di atas: semua penghapusan lewat `Trasher` dan dikonfirmasi pengguna, dan logika penghapusan baru harus punya test.
- Sebelum pull request pertamamu di-merge, kamu menyetujui [Contributor License Agreement](CLA.md). Bot akan memintanya di pull request, cukup dengan satu komentar.

## Lisensi

[PolyForm Noncommercial 1.0.0](LICENSE) © 2026 Rizky Aditya Fahreza

KhaiCleanMac bersifat **source-available**, bukan open source:

- ✅ Boleh dipakai, dipelajari, diubah, dan dibagikan untuk keperluan **non-komersial**: pemakaian pribadi, belajar, riset, proyek hobi, serta organisasi nirlaba, pendidikan, atau pemerintah.
- ❌ Tidak boleh dipakai untuk tujuan **komersial**, misalnya dijual, digabung ke produk berbayar, atau dipakai untuk layanan berbayar.
- Untuk pemakaian komersial, hubungi pemilik lewat [GitHub](https://github.com/rizkyraf8).

KhaiCleanMac adalah proyek independen. Proyek ini tidak berafiliasi dengan, dan tidak didukung oleh, MacPaw maupun CleanMyMac.
