@echo off
rem Runs make_store_upload.ps1 (see the top of it) without changing the
rem PowerShell execution policy. Arguments are passed on, e.g.
rem   scripts\make_store_upload.cmd -IdentityName ... -Publisher "CN=..." -PublisherDisplayName "..."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0make_store_upload.ps1" %*
