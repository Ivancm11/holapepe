<#
  mitv-tuner - speed up a Xiaomi Android TV 11 (MiTV-MOOQ0) over Wi-Fi ADB.

  Usage (PowerShell, from this folder):
    .\mitv.ps1 scan -Tv 1.2.3.4  # read-only: what is installed / disabled / using RAM
                                 # (-Tv is remembered in tv.txt, so later commands can omit it)
    .\mitv.ps1 home              # install Poodle Home (launcher\poodle-home.apk), push apps + photos, make it the home screen
    .\mitv.ps1 home -Build       # same, but rebuild the apk from source first (needs Android SDK + JDK)
    .\mitv.ps1 apps              # push apps.txt (favourite apps, in order) to Poodle Home
    .\mitv.ps1 wallpaper         # turn assets\photos\* into wallpapers and push them to Poodle Home
    .\mitv.ps1 launcher          # open Projectivy Launcher in the TV's Play Store
    .\mitv.ps1 clean -DryRun     # show what clean would do, change nothing
    .\mitv.ps1 clean             # disable bloat (never uninstalls, never clears data)
    .\mitv.ps1 restore           # re-enable everything clean/home disabled

  Account safety: apps are only disabled with `pm disable-user`, which keeps their
  data, so no logins are lost. Nothing is ever cleared or uninstalled. Packages in
  $Protected and every app you installed yourself are refused outright.
#>
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('scan', 'home', 'apps', 'wallpaper', 'launcher', 'clean', 'restore')]
    [string]$Action,
    [string]$Tv,
    [switch]$DryRun,
    [switch]$Build
)

$ErrorActionPreference = 'Stop'
$Here       = $PSScriptRoot

# The TV's IP is remembered in tv.txt after the first run with -Tv.
$TvFile = Join-Path $Here 'tv.txt'
if ($Tv) {
    Set-Content -Encoding ascii $TvFile $Tv.Trim()
} elseif (Test-Path $TvFile) {
    $Tv = (Get-Content $TvFile -Raw).Trim()
} else {
    throw "Tell me the TV's IP once, e.g.  .\mitv.ps1 $Action -Tv 192.168.1.50  (TV: Settings > Network > your Wi-Fi)."
}
$Serial     = "${Tv}:5555"
$BackupFile = Join-Path $Here 'backup.json'
$Projectivy = 'com.spocky.projengmenu'
$PoodleHome = 'com.poodlehome'
$PoodleDir  = "/sdcard/Android/data/$PoodleHome/files"

# Disabled by `clean`. Each line: package = reason.
$Bloat = [ordered]@{
    'com.mitv.tvhome.atv'                         = 'PatchWall home (biggest RAM user)'
    'com.mitv.tvhome.michannel'                   = 'PatchWall channels'
    'com.xm.webcontent'                           = 'Xiaomi web content / promos'
    'com.xiaomi.android.tvsetup.partnercustomizer' = 'Xiaomi launcher rows / promos'
    'com.miui.tv.analytics'                       = 'Xiaomi analytics'
    'com.xiaomi.statistic'                        = 'Xiaomi statistics'
    'com.xiaomi.floatingframe'                    = 'Store demo mode'
    'fusion.android.tv.demo'                      = 'Retail display demo'
    'com.xiaomi.mimusic2'                         = 'Xiaomi music'
    'com.mitv.gallery'                            = 'Xiaomi gallery'
    'com.xiaomi.mitv.manualhelp'                  = 'Xiaomi manual'
    'com.xiaomi.amazon.alexa'                     = 'Alexa'
    'com.mediatek.wwtv.setupwizard'               = 'Antenna channel scan wizard'
    'com.mitv.livetv.ci_mediatek'                 = 'Antenna CI card'
    'com.google.android.backdrop'                 = 'Google ambient screensaver'
    'com.google.android.katniss'                  = 'Google Assistant / voice search'
}

# Only disabled once Projectivy is installed, so the TV always has a home screen.
$StockLauncher = [ordered]@{
    'com.google.android.tvlauncher'       = 'Stock Google TV home'
    'com.google.android.tvrecommendations' = 'Stock home recommendations'
}

# Kept installed but not allowed to run in the background.
$NoBackground = @('com.mitv.tvhome.mitvplus')   # Mi TV+ free channels

# Never disabled, whatever the lists above say.
$Protected = @(
    'android', 'com.android.systemui', 'com.android.vending', 'com.android.tv.settings',
    'com.google.android.gms', 'com.google.android.gsf', 'com.google.android.sss.authbridge',
    'com.google.android.webview', 'com.google.android.apps.mediashell',
    'com.mediatek.wwtv.tvcenter', 'com.mediatek.tv.service', 'com.mediatek.tvinput',
    'com.xiaomi.tvqs.overseas', 'com.xiaomi.mitv.updateservice',
    'com.netflix.ninja', 'tv.twitch.android.app', 'com.apple.atve.androidtv.appletv',
    'com.spotify.tv.android', 'com.amazon.amazonvideo.livingroom', 'com.wbd.stream',
    'com.disney.disneyplus', $Projectivy, $PoodleHome
)

function Invoke-Adb {
    # PS 5.1 turns native stderr into errors under 'Stop'; rely on the exit code instead.
    $ErrorActionPreference = 'Continue'
    $out = & adb -s $Serial @args 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { throw "adb $($args -join ' ') failed: $out" }
    $out
}

function Connect-Tv {
    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        throw "adb not found. Install it with:  winget install Google.PlatformTools  then open a new PowerShell window."
    }
    $ErrorActionPreference = 'Continue'
    & adb connect $Serial 2>&1 | Out-Null
    $state = (& adb -s $Serial get-state 2>&1) -join ''
    if ($state -ne 'device') {
        throw "TV at $Serial is '$state'. Check it is on, on the same Wi-Fi, and accept the debugging prompt on screen."
    }
}

function Get-Packages([string]$Flag) {
    Invoke-Adb shell pm list packages $Flag | ForEach-Object { ($_ -replace '^package:', '').Trim() } | Where-Object { $_ }
}

function Get-AnimationScales {
    [ordered]@{
        window_animation_scale     = (Invoke-Adb shell settings get global window_animation_scale) -join ''
        transition_animation_scale = (Invoke-Adb shell settings get global transition_animation_scale) -join ''
        animator_duration_scale    = (Invoke-Adb shell settings get global animator_duration_scale) -join ''
    }
}

function Invoke-Scan {
    $all      = Get-Packages '-u'
    $disabled = Get-Packages '-d'
    $user     = Get-Packages '-3'
    $homeApp  = Invoke-Adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME
    $mem      = Invoke-Adb shell cat /proc/meminfo | Select-Object -First 3

    "Home screen:        $($homeApp | Select-Object -Last 1)"
    "Projectivy:         $(if ($all -contains $Projectivy) { 'installed' } else { 'not installed' })"
    $mem
    ''
    'Cleanup targets:'
    foreach ($p in @($Bloat.Keys) + @($StockLauncher.Keys)) {
        $s = if ($all -notcontains $p) { 'absent  ' } elseif ($disabled -contains $p) { 'disabled' } else { 'ENABLED ' }
        "  $s $p"
    }
    ''
    'Apps you installed (never touched):'
    $user | Sort-Object | ForEach-Object { "  $_" }
    ''
    'Top memory users:'
    $o = Invoke-Adb shell dumpsys meminfo
    $i = ($o | Select-String 'Total PSS by process').LineNumber
    $o[$i..($i + 14)]
}

function Invoke-Clean {
    $all      = Get-Packages '-u'
    $disabled = Get-Packages '-d'
    $user     = Get-Packages '-3'

    $targets = [ordered]@{}
    foreach ($k in $Bloat.Keys) { $targets[$k] = $Bloat[$k] }
    if ($all -contains $PoodleHome -or $all -contains $Projectivy) {
        foreach ($k in $StockLauncher.Keys) { $targets[$k] = $StockLauncher[$k] }
    } else {
        Write-Warning "No replacement home screen installed: keeping the stock one. Run '.\mitv.ps1 home' first."
    }

    # Keep the first backup: it records the TV as it was before any clean.
    $backup = if (Test-Path $BackupFile) { Get-Content $BackupFile -Raw | ConvertFrom-Json } else { $null }
    $changed = @(if ($backup) { $backup.disabledByUs })

    foreach ($p in $targets.Keys) {
        $why = $targets[$p]
        if ($Protected -contains $p -or ($user -contains $p -and $p -ne 'com.xiaomi.mitv.manualhelp')) {
            Write-Warning "refusing protected package $p"; continue
        }
        if ($all -notcontains $p)      { "  skip     $p (not on this TV)"; continue }
        if ($disabled -contains $p)    { "  already  $p"; continue }
        if ($DryRun)                   { "  would disable $p  - $why"; continue }
        Invoke-Adb shell am force-stop $p | Out-Null
        Invoke-Adb shell pm disable-user --user 0 $p | Out-Null
        "  disabled $p  - $why"
        $changed += $p
    }

    foreach ($p in $NoBackground) {
        if ($all -notcontains $p) { continue }
        if ($DryRun) { "  would stop background for $p"; continue }
        Invoke-Adb shell cmd appops set $p RUN_ANY_IN_BACKGROUND ignore | Out-Null
        Invoke-Adb shell am force-stop $p | Out-Null
        "  no-background $p"
    }

    if ($DryRun) { 'Dry run: nothing changed.'; return }

    $state = [ordered]@{
        tv              = $Serial
        firstCleanedAt  = if ($backup) { $backup.firstCleanedAt } else { (Get-Date).ToString('s') }
        disabledBefore  = if ($backup) { $backup.disabledBefore } else { @($disabled) }
        animationScales = if ($backup) { $backup.animationScales } else { Get-AnimationScales }
        disabledByUs    = @($changed | Select-Object -Unique)
        noBackground    = $NoBackground
    }
    $state | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $BackupFile
    "Backup written to $BackupFile. Undo with '.\mitv.ps1 restore'."
}

function Invoke-Restore {
    if (-not (Test-Path $BackupFile)) { throw "No $BackupFile - nothing to restore." }
    $backup = Get-Content $BackupFile -Raw | ConvertFrom-Json
    foreach ($p in $backup.disabledByUs) {
        Invoke-Adb shell pm enable $p | Out-Null
        "  enabled $p"
    }
    foreach ($p in $backup.noBackground) {
        Invoke-Adb shell cmd appops set $p RUN_ANY_IN_BACKGROUND allow | Out-Null
        "  background allowed $p"
    }
    foreach ($s in $backup.animationScales.PSObject.Properties) {
        if ($s.Value -and $s.Value -ne 'null') { Invoke-Adb shell settings put global $s.Name $s.Value | Out-Null }
    }
    Rename-Item $BackupFile ("backup-restored-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
    'Restored. Restart the TV to be sure every service is back.'
}

function Add-ToBackup([string[]]$Packages) {
    $backup = if (Test-Path $BackupFile) { Get-Content $BackupFile -Raw | ConvertFrom-Json } else {
        [pscustomobject]@{ tv = $Serial; firstCleanedAt = (Get-Date).ToString('s'); disabledBefore = @()
                           animationScales = Get-AnimationScales; disabledByUs = @(); noBackground = @() }
    }
    $backup.disabledByUs = @(@($backup.disabledByUs) + $Packages | Select-Object -Unique)
    $backup | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $BackupFile
}

function Push-Apps {
    $file = Join-Path $Here 'apps.txt'
    if (-not (Test-Path $file)) { throw "Missing $file" }
    Invoke-Adb shell mkdir -p $PoodleDir | Out-Null
    Invoke-Adb push $file "$PoodleDir/apps.txt" | Out-Null
    'Pushed apps.txt. Press Home on the remote to see it.'
}

function Push-Wallpapers {
    $photos = @(Get-ChildItem (Join-Path $Here 'assets\photos') -File |
        Where-Object { $_.Extension -match '^\.(png|jpe?g)$' } | Sort-Object Name)
    if ($photos.Count -eq 0) { throw "Put at least one photo in assets\photos" }
    $outDir = Join-Path $Here 'assets\wallpapers'
    if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
    New-Item -ItemType Directory $outDir | Out-Null

    Invoke-Adb shell rm -rf "$PoodleDir/wallpapers" | Out-Null
    Invoke-Adb shell mkdir -p "$PoodleDir/wallpapers" | Out-Null
    foreach ($p in $photos) {
        $dest = Join-Path $outDir ($p.BaseName + '.png')
        New-Wallpaper $p.FullName $dest | Out-Null
        Invoke-Adb push $dest "$PoodleDir/wallpapers/$($p.BaseName).png" | Out-Null
        "  wallpaper $($p.Name)"
    }
    "Pushed $($photos.Count) wallpaper(s); one is shown per day."
}

function Install-PoodleHome {
    $apk = Join-Path $Here 'launcher\poodle-home.apk'
    if ($Build -or -not (Test-Path $apk)) { & (Join-Path $Here 'launcher\build.ps1') }
    Invoke-Adb install -r $apk | Out-Null
    '  installed Poodle Home'
    Push-Apps | Out-Null
    Push-Wallpapers

    # Only one home screen may stay enabled, or Android asks which to use.
    $all      = Get-Packages '-u'
    $disabled = Get-Packages '-d'
    if ($all -contains $Projectivy -and $disabled -notcontains $Projectivy) {
        Invoke-Adb shell am force-stop $Projectivy | Out-Null
        Invoke-Adb shell pm disable-user --user 0 $Projectivy | Out-Null
        Add-ToBackup @($Projectivy)
        "  disabled $Projectivy (Projectivy; '.\mitv.ps1 restore' brings it back)"
    }
    Invoke-Adb shell cmd package set-home-activity "$PoodleHome/.HomeActivity" | Out-Null
    Invoke-Adb shell input keyevent KEYCODE_HOME | Out-Null
    'Poodle Home is now the home screen.'
}

function New-Wallpaper([string]$src, [string]$dest) {
    Add-Type -AssemblyName System.Drawing
    $W = 1920; $H = 1080

    $dog = [System.Drawing.Image]::FromFile($src)
    $bmp = New-Object System.Drawing.Bitmap $W, $H
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.Clear([System.Drawing.Color]::Black)

        # Dog fills the full height on the right side.
        $dh = $H; $dw = [int]($dog.Width * $H / $dog.Height)
        $dx = $W - $dw - 120
        $g.DrawImage($dog, $dx, 0, $dw, $dh)

        # Fade the photo's edges into black so it blends with the background.
        $fade = 260
        $left = New-Object System.Drawing.Rectangle ($dx - 1), 0, $fade, $H
        $lb = New-Object System.Drawing.Drawing2D.LinearGradientBrush $left, ([System.Drawing.Color]::FromArgb(255, 0, 0, 0)), ([System.Drawing.Color]::FromArgb(0, 0, 0, 0)), 0
        # Without TileFlipX the brush wraps at its last pixel and draws a thin black line.
        $lb.WrapMode = [System.Drawing.Drawing2D.WrapMode]::TileFlipX
        $g.FillRectangle($lb, $left)
        $right = New-Object System.Drawing.Rectangle ($dx + $dw - $fade + 1), 0, $fade, $H
        $rb = New-Object System.Drawing.Drawing2D.LinearGradientBrush $right, ([System.Drawing.Color]::FromArgb(0, 0, 0, 0)), ([System.Drawing.Color]::FromArgb(255, 0, 0, 0)), 0
        $rb.WrapMode = [System.Drawing.Drawing2D.WrapMode]::TileFlipX
        $g.FillRectangle($rb, $right)
        $g.FillRectangle([System.Drawing.Brushes]::Black, ($dx + $dw), 0, ($W - $dx - $dw), $H)

        # Darken the whole picture a little so app names stay readable.
        $dim = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60, 0, 0, 0))
        $g.FillRectangle($dim, 0, 0, $W, $H)

        $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $g.Dispose(); $bmp.Dispose(); $dog.Dispose()
    }
    $dest
}

Connect-Tv
switch ($Action) {
    'scan'      { Invoke-Scan }
    'clean'     { Invoke-Clean }
    'restore'   { Invoke-Restore }
    'home'      { Install-PoodleHome }
    'apps'      { Push-Apps }
    'wallpaper' { Push-Wallpapers }
    'launcher'  {
        Invoke-Adb shell am start -a android.intent.action.VIEW -d "market://details?id=$Projectivy" | Out-Null
        'Play Store is open on the TV: press Install on Projectivy Launcher.'
    }
}
