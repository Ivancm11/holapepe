<#
  Builds Poodle Home without Gradle, using the Android SDK's own tools.
  Output: launcher\build\poodle-home.apk
#>
$ErrorActionPreference = 'Stop'
$Here  = $PSScriptRoot
$Sdk   = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$Tools = "$Sdk\build-tools\35.0.0"
$Jar   = "$Sdk\platforms\android-35\android.jar"
$Out   = Join-Path $Here 'build'
$Ks    = Join-Path $Here 'debug.keystore'

foreach ($p in $Tools, $Jar) { if (-not (Test-Path $p)) { throw "Missing $p (install it with Android Studio's SDK Manager)." } }

function Run([string]$exe) {
    & $exe @args
    if ($LASTEXITCODE -ne 0) { throw "$(Split-Path $exe -Leaf) failed (exit $LASTEXITCODE)" }
}

if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory -Force "$Out\gen", "$Out\classes", "$Out\dex" | Out-Null

# 1. Resources + manifest -> base apk and R.java
Run "$Tools\aapt2.exe" compile --dir "$Here\res" -o "$Out\res.zip"
$version = [int]((Get-Date).ToUniversalTime() - [datetime]'2026-01-01').TotalMinutes
Run "$Tools\aapt2.exe" link -o "$Out\base.apk" -I $Jar --manifest "$Here\AndroidManifest.xml" `
    --java "$Out\gen" --min-sdk-version 30 --target-sdk-version 30 `
    --version-code $version --version-name "1.0.$version" "$Out\res.zip"

# 2. Java -> classes -> dex
$sources = @(Get-ChildItem -Recurse "$Here\src", "$Out\gen" -Filter *.java | ForEach-Object FullName)
Run javac --release 11 -encoding UTF-8 -classpath $Jar -d "$Out\classes" @sources
$classes = @(Get-ChildItem -Recurse "$Out\classes" -Filter *.class | ForEach-Object FullName)
Run "$Tools\d8.bat" --release --min-api 30 --lib $Jar --output "$Out\dex" @classes

# 3. Add classes.dex to the apk, align, sign
Add-Type -AssemblyName System.IO.Compression.FileSystem
Copy-Item "$Out\base.apk" "$Out\unsigned.apk"
$zip = [System.IO.Compression.ZipFile]::Open("$Out\unsigned.apk", 'Update')
try {
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, "$Out\dex\classes.dex", 'classes.dex') | Out-Null
} finally { $zip.Dispose() }
Run "$Tools\zipalign.exe" -f 4 "$Out\unsigned.apk" "$Out\aligned.apk"

if (-not (Test-Path $Ks)) {
    Run keytool -genkeypair -keystore $Ks -storepass android -keypass android -alias poodle `
        -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Poodle Home' | Out-Null
}
Run "$Tools\apksigner.bat" sign --ks $Ks --ks-pass pass:android --key-pass pass:android `
    --out "$Out\poodle-home.apk" "$Out\aligned.apk"

# Prebuilt copy kept next to the sources, so others can install without the SDK.
Copy-Item "$Out\poodle-home.apk" (Join-Path $Here 'poodle-home.apk') -Force
"Built $Here\poodle-home.apk (version $version)"
