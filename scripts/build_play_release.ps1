$ErrorActionPreference = 'Continue'
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\\bin;$env:PATH"
Write-Host "JAVA_HOME = $env:JAVA_HOME"
try {
	java -version 2>&1 | Write-Host
} catch {
	Write-Host "java -version failed but continuing"
}
try {
	flutter --version 2>&1 | Write-Host
} catch {
	Write-Host "flutter --version failed but continuing"
}
try {
	flutter build appbundle --flavor play --release -v 2>&1 | Tee-Object -FilePath build_play_verbose.log
} catch {
	Write-Host "flutter build failed (see build_play_verbose.log)"
	exit 1
}
