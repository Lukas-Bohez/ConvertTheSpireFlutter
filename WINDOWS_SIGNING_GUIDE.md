# Windows Code Signing & MSIX Distribution Guide for Oroka Conner

To remove the "Unknown Publisher" warning and ensure Windows recognizes "Convert the Spire Reborn" as a safe app, you must sign the MSIX with a certificate issued by a trusted Certificate Authority (CA).

## ⚠️ The "AI Agent" Limitation
I cannot "buy" or "get" a trusted certificate for you because it requires **identity verification** (submitting your ID/Business documents to a vendor like DigiCert or Sectigo) and a **monetary payment**.

---

## Step 1: Purchasing a Certificate (The Only Way to Stop Warnings)
You need to buy a **Windows Code Signing Certificate**.

1.  **Choose a Vendor:** Recommended options are [DigiCert](https://www.digicert.com/), [Sectigo](https://sectigo.com/), or [SSL.com](https://www.ssl.com/).
2.  **Choose Type:** 
    *   **EV (Extended Validation):** ~$400-600/year. Removes warnings **immediately**. Recommended.
    *   **OV (Organization Validation):** ~$200-300/year. Warnings stay for the first few hundred downloads until "reputation" is built.
3.  **Complete Validation:** They will call you or email you to verify you are "Oroka Conner."
4.  **Download the PFX file:** Once approved, they will give you a `.pfx` file and a password.

---

## Step 2: Configure Your App
Once you have the `.pfx` file:

1.  **Place the file:** Put it in `windows/certificates/codesign.pfx`.
2.  **Update settings:** I have already set up your `pubspec.yaml` with:
    ```yaml
    msix_config:
      publisher: CN=Oroka Conner  # <--- THIS MUST MATCH THE CERTIFICATE NAME EXACTLY
    ```
    If the name on your certificate is slightly different (e.g., `CN="Oroka Conner, Inc."`), we must change it in `pubspec.yaml`.

---

## Step 3: Build the MSIX (Final Command)
With the PFX file in place, run this command in your terminal:

```powershell
.\scripts\build_msix.ps1
```

It will ask for your password, build the app, sign it, and put the final file here:
`build\windows\runner\Release\Convert the Spire Reborn.msix`

---

## Step 4: For GitHub / CI/CD (Cloud Building)
To make GitHub build the signed files for you:

1.  **Convert PFX to Base64:**
    Run this in your local PowerShell:
    ```powershell
    [Convert]::ToBase64String([IO.File]::ReadAllBytes("windows/certificates/codesign.pfx"))
    ```
2.  **Add to GitHub:** 
    *   Go to your GitHub repo -> **Settings** -> **Secrets and variables** -> **Actions**.
    *   Create `MSIX_PFX_BASE64`: Paste the long string from step 1.
    *   Create `MSIX_PFX_PASSWORD`: Your certificate password.

---

## Summary of Files I Prepared
*   [scripts/build_msix.ps1](scripts/build_msix.ps1): Your local build tool.
*   [.github/workflows/build-msix.yml](.github/workflows/build-msix.yml): Your automated cloud builder.
*   [pubspec.yaml](pubspec.yaml): Pre-configured with your app name and publisher ID.

**Would you like me to help you verify if a specific certificate vendor's requirements match your setup?**
