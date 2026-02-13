# Windows MSIX Distribution Options

You have two main options for distributing "Convert the Spire Reborn":

## Option 1: Microsoft Store (Recommended for Users) ✓ YOU CHOSE THIS
**Microsoft handles signing for you. No certificate purchase needed.**

- **Cost:** $19 USD (developer account, one-time).
- **First-run warning:** No — Microsoft's trust chain removes it immediately.
- **Distribution:** Automatic via Windows Store app.
- **Updates:** Handled automatically.

**See:** [MICROSOFT_STORE_PUBLISHING.md](MICROSOFT_STORE_PUBLISHING.md)

---

## Option 2: Direct Distribution (Self-Hosted/Website)
**You sign the MSIX yourself and distribute the file directly.**

- **Cost:** $200–600 USD (code-signing certificate per year).
- **First-run warning:** Appears initially; reputation builds over time (100s–1000s of downloads).
- **Distribution:** Host `.msix` on your website; users download and install.
- **Updates:** You manage versioning and re-uploads.

This requires:
1. Buying a Code Signing Certificate from DigiCert, Sectigo, or SSL.com
2. Placing the `.pfx` file in `windows/certificates/codesign.pfx`
3. Running `.\scripts\build_msix.ps1` locally

**Not chosen** — You elected to use Microsoft Store instead.

---

## Summary of Setup
*   [scripts/build_msix.ps1](scripts/build_msix.ps1): Builds unsigned MSIX for Store submission.
*   [.github/workflows/build-msix.yml](.github/workflows/build-msix.yml): CI/CD to auto-build MSIX.
*   [pubspec.yaml](pubspec.yaml): Pre-configured with your identity and publisher info.
*   [MICROSOFT_STORE_PUBLISHING.md](MICROSOFT_STORE_PUBLISHING.md): Complete Store publishing guide.

**Ready to go – proceed with [MICROSOFT_STORE_PUBLISHING.md](MICROSOFT_STORE_PUBLISHING.md).**
