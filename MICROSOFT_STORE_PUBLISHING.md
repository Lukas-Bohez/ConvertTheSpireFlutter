# Publishing "Convert the Spire Reborn" to Microsoft Store

Good news: **Microsoft handles all the signing for you**. You just upload the unsigned MSIX, and they will sign it and distribute it.

---

## Quick Start

### 1. Build the unsigned MSIX (1 min)
```powershell
.\scripts\build_msix.ps1
```

This creates:
```
build/windows/runner/Release/Convert the Spire Reborn.msix
```

### 2. Register as a Microsoft App Developer (one-time)
Go to https://partner.microsoft.com/en-us/dashboard

- Click **Sign in** → accept Microsoft's terms.
- Pay the registration fee (~$19 USD, one-time).
- Verify your Microsoft Account or create one.

### 3. Create Your App Namespace
In Partner Center:

1. Click **Create a new app**
2. Enter your app name: **Convert the Spire Reborn**
3. Click **Reserve app name**
4. Once reserved, note your **Package/Identity/Name** (looks like: `OrokaConner.ConvertTheSpireReborn`)

(This matches your `identity_name` in `pubspec.yaml` ✓)

### 4. Fill in Your App Metadata
Still in Partner Center:

- **Description:** What your app does
- **Category:** Choose appropriate category (e.g., Utilities, Multimedia, etc.)
- **Publisher Name:** Oroka Conner (already set)
- **Website:** Your website (or omit if you don't have one)
- **Support Email:** Contact email for users
- **Logo:** Use your app icon (512×512 PNG preferred)

### 5. Upload the MSIX
1. Go to **Submission** → **Packages**
2. Drag and drop your `.msix` file
3. Microsoft validates it (~5–30 minutes)

### 6. Add Pricing & Availability
- **Price:** Free (recommended for initial release)
- **Markets:** Select which countries to list in
- **Age Rating:** Answer the Microsoft Content Rating System questions

### 7. Submit for Review
Click **Submit for review** → Microsoft reviews for ~24–48 hours.

**Automated checks:**
- No malware (VirusTotal scan)
- Follows Store policies
- App works on Windows 10/11

---

## After Approval

Once approved:

- ✓ Your app appears in Microsoft Store
- ✓ Windows will fully trust it (no "Unknown Publisher" warnings)
- ✓ Users can install with one click
- ✓ Automatic updates via Store
- ✓ Age-appropriate filters applied

---

## Updating Your App

To push a new version:

1. Increase version in `pubspec.yaml`:
   ```yaml
   version: 1.0.1+2  # Bump the build number
   ```
2. Run `.\scripts\build_msix.ps1`
3. Upload the new MSIX in Partner Center
4. Resubmit for review

---

## Troubleshooting

### "App name already taken"
The `identity_name` (`OrokaConner.ConvertTheSpireReborn`) must be unique globally. If it's taken, change it in `pubspec.yaml` and rebuild.

### "MSIX validation failed"
Check Partner Center → Packages → Error messages. Common issues:
- Missing app icon or icon in wrong format
- Logo size incorrect
- App crashes on startup (test it first!)

### "Microsoft rejected my app"
Review the policy violation details in Partner Center. Most common rejections:
- Misleading description
- Privacy policy not linked
- App doesn't match the description

---

## Costs

- **Developer Account:** $19 (one-time, lasts 1 year; auto-renews)
- **Uploading/Listing:** Free
- **Revenue Share:** 0% (you keep 100% if you monetize later)

---

## Need Help?

- [Microsoft Partner Center Docs](https://docs.microsoft.com/en-us/windows/msix/overview)
- [App Provider Agreement](https://docs.microsoft.com/en-us/windows/msix/app-installer/app-installer-overview)
- Microsoft Support: partner.microsoft.com → Help & Support
