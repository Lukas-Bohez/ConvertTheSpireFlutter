# Split-per-ABI Guidance

Use split APKs only when you need direct-install APKs. For Play, prefer the AAB.

```bash
flutter build apk --split-per-abi --release
```

If you need native-library-heavy testing packages, keep ABI-specific artifacts separate and avoid mixing them with the Play bundle output.
