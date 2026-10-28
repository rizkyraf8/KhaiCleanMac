# Contributing to KhaiCleanMac

Thanks for wanting to help! Bug reports, ideas, translations and fixes are all welcome.

_Ringkasan dalam Bahasa Indonesia ada di [bagian bawah](#bahasa-indonesia)._

## Before you start

- **License:** KhaiCleanMac is source-available under the
  [PolyForm Noncommercial License 1.0.0](LICENSE). You can use, study, change and share it for
  noncommercial purposes. Commercial use is not allowed.
- **Contributor License Agreement:** before your first pull request can be merged, you sign
  the [CLA](CLA.md). The CLA Assistant bot asks you on the pull request, and signing takes one
  comment. In short, you keep your rights, and the project owner may use your contribution in
  any version of KhaiCleanMac, including a commercial one.
- **Bigger changes:** please open an issue first, so we can agree on the approach before you
  spend time on it.

## Setting up

You need macOS 15 or later and Xcode 16 or later.

```bash
git clone https://github.com/rizkyraf8/KhaiCleanMac.git
cd KhaiCleanMac
swift build
swift test
./scripts/build-app.sh   # builds build/KhaiCleanMac.app
```

Debug builds can render every screen to PNG without opening a window:

```bash
swift build && .build/debug/KhaiCleanMac --snapshot ./snapshots
```

## Safety rules

KhaiCleanMac removes files, so these rules are not optional:

1. **Everything that removes files goes through `Trasher`.** That keeps the Trash as the
   default and respects the "delete permanently" setting. Never call `removeItem` or
   `trashItem` directly from a feature.
2. **Nothing is removed without the user confirming it,** and the confirmation says what will
   happen (Trash or permanent).
3. **Data of running apps stays locked.** Use `RunningAppMatcher` for anything an open app may
   be using.
4. **Personal files are never preselected:** downloads, backups, documents and the Trash.
5. **When unsure, keep it.** Leaving junk behind is better than removing something the user
   needs.
6. **New removal logic needs tests.** Tests must use `TempFolder` and never touch real files
   or the real Trash. See `Tests/KhaiCleanMacTests`.

## Code style

- Match the surrounding code: SwiftUI, `@Observable` models, Swift 6 concurrency.
- Every user-facing string uses `L("Bahasa Indonesia", "English")`.
- Use the shared design pieces (`softCard`, `GradientIcon`, `GradientButtonStyle`, `Palette`)
  so screens stay consistent.
- Keep comments short and about *why*, not *what*.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Make your change, with tests where it matters.
3. Run `swift build` and `swift test`. CI runs both on every pull request.
4. Add a line to `CHANGELOG.md` under **Unreleased**.
5. Open the pull request and fill in the checklist.

## Bahasa Indonesia

- KhaiCleanMac memakai lisensi **PolyForm Noncommercial 1.0.0**: boleh dipakai, dipelajari,
  diubah, dan dibagikan untuk keperluan **non-komersial**. Pemakaian komersial tidak diizinkan.
- Sebelum pull request pertamamu bisa di-merge, kamu menyetujui [CLA](CLA.md) lewat bot CLA
  Assistant, cukup dengan satu komentar. Intinya: hak atas kodemu tetap milikmu, dan pemilik
  proyek boleh memakai kontribusimu di versi KhaiCleanMac mana pun, termasuk versi komersial.
- Aturan keamanan di atas wajib diikuti. Yang terpenting: semua penghapusan lewat `Trasher`,
  selalu ada konfirmasi pengguna, dan logika penghapusan baru harus punya test.
- Alurnya: fork → buat branch → ubah dan tambah test → `swift build` dan `swift test` →
  catat di CHANGELOG → buka pull request.
