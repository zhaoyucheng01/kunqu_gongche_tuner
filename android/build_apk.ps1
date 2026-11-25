param(
    [switch]$Install,
    [switch]$Launch
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$HtmlSource = Join-Path $ProjectRoot "kunqu_gongche_tuner.html"
$BuildDir = Join-Path $ScriptDir "build"

if (-not (Test-Path $HtmlSource)) {
    throw "未找到源文件: $HtmlSource"
}

function Find-AndroidSdk {
    $candidates = @(
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA "Android\Sdk"),
        "C:\Android\Sdk",
        "D:\Android\Sdk"
    )
    $found = @($candidates | Where-Object { $_ -and (Test-Path $_) })
    if ($found.Count -eq 0) {
        throw "未找到 Android SDK，请设置 ANDROID_HOME 环境变量。"
    }
    return $found[0]
}

function Find-Jdk {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += $env:JAVA_HOME }
    $regStudio = Get-ItemProperty "HKLM:\SOFTWARE\Android Studio" -ErrorAction SilentlyContinue
    if ($regStudio -and $regStudio.Path) {
        $candidates += (Join-Path $regStudio.Path "jbr")
        $candidates += (Join-Path $regStudio.Path "jre")
    }
    $candidates += @(
        "C:\Program Files\Android\Android Studio\jbr",
        "D:\SoftWare\Android\Android Studio\jbr"
    )
    foreach ($dir in $candidates) {
        if ($dir -and (Test-Path (Join-Path $dir "bin\javac.exe"))) {
            return $dir
        }
    }
    throw "未找到包含 javac 的 JDK，请设置 JAVA_HOME 或安装 Android Studio。"
}

$SdkDir = Find-AndroidSdk
$JdkDir = Find-Jdk
$env:JAVA_HOME = $JdkDir
$env:PATH = "$(Join-Path $JdkDir 'bin');$env:PATH"

$BuildToolsDir = Get-ChildItem (Join-Path $SdkDir "build-tools") -Directory | Sort-Object Name -Descending | Select-Object -First 1
$PlatformDir = Get-ChildItem (Join-Path $SdkDir "platforms") -Directory | Sort-Object Name -Descending | Select-Object -First 1
if (-not $BuildToolsDir) { throw "Android SDK 缺少 build-tools。" }
if (-not $PlatformDir) { throw "Android SDK 缺少 platforms。" }

$Aapt2 = Join-Path $BuildToolsDir.FullName "aapt2.exe"
$D8 = Join-Path $BuildToolsDir.FullName "d8.bat"
$ZipAlign = Join-Path $BuildToolsDir.FullName "zipalign.exe"
$ApkSigner = Join-Path $BuildToolsDir.FullName "apksigner.bat"
$AndroidJar = Join-Path $PlatformDir.FullName "android.jar"
$Javac = Join-Path $JdkDir "bin\javac.exe"
$Keytool = Join-Path $JdkDir "bin\keytool.exe"

Write-Host "[1/6] 准备构建目录..." -ForegroundColor Cyan
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
$GenDir = Join-Path $BuildDir "gen"
$ObjDir = Join-Path $BuildDir "obj"
$ResFlatDir = Join-Path $BuildDir "res_flat"
$DexDir = Join-Path $BuildDir "dex"
$AssetsDir = Join-Path $BuildDir "assets"
New-Item -ItemType Directory -Force -Path $GenDir, $ObjDir, $ResFlatDir, $DexDir, $AssetsDir | Out-Null

Copy-Item -Force $HtmlSource (Join-Path $AssetsDir "kunqu_gongche_tuner.html")

Write-Host "[2/6] 编译与链接资源 (aapt2)..." -ForegroundColor Cyan
$ResZip = Join-Path $ResFlatDir "resources.zip"
& $Aapt2 compile --dir (Join-Path $ScriptDir "res") -o $ResZip
if ($LASTEXITCODE -ne 0) { throw "aapt2 compile 失败" }

$UnalignedApk = Join-Path $BuildDir "app-unaligned.apk"
& $Aapt2 link `
    -I $AndroidJar `
    --manifest (Join-Path $ScriptDir "AndroidManifest.xml") `
    --java $GenDir `
    -A $AssetsDir `
    -o $UnalignedApk `
    $ResZip
if ($LASTEXITCODE -ne 0) { throw "aapt2 link 失败" }

Write-Host "[3/6] 编译 Java 源码 (javac)..." -ForegroundColor Cyan
$JavaFiles = @(
    (Get-ChildItem -Path (Join-Path $ScriptDir "src") -Filter "*.java" -Recurse | ForEach-Object { $_.FullName }),
    (Get-ChildItem -Path $GenDir -Filter "*.java" -Recurse | ForEach-Object { $_.FullName })
) | ForEach-Object { $_ } | Where-Object { $_ }

& $Javac -encoding UTF-8 -source 11 -target 11 -classpath $AndroidJar -d $ObjDir @JavaFiles
if ($LASTEXITCODE -ne 0) { throw "javac 编译失败" }

Write-Host "[4/6] 生成 DEX 字节码 (d8)..." -ForegroundColor Cyan
$ClassFiles = Get-ChildItem -Path $ObjDir -Filter "*.class" -Recurse | ForEach-Object { $_.FullName }
& $D8 --min-api 24 --lib $AndroidJar --output $DexDir @ClassFiles
if ($LASTEXITCODE -ne 0) { throw "d8 转换失败" }

Write-Host "[5/6] 打包与对齐 APK (zipalign)..." -ForegroundColor Cyan
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$DexFile = Join-Path $DexDir "classes.dex"
$zip = [System.IO.Compression.ZipFile]::Open($UnalignedApk, [System.IO.Compression.ZipArchiveMode]::Update)
try {
    $existing = $zip.GetEntry("classes.dex")
    if ($existing) { $existing.Delete() }
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $DexFile, "classes.dex", [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
} finally {
    $zip.Dispose()
}

$AlignedApk = Join-Path $BuildDir "app-aligned.apk"
& $ZipAlign -p -f 4 $UnalignedApk $AlignedApk
if ($LASTEXITCODE -ne 0) { throw "zipalign 对齐失败" }

Write-Host "[6/6] 签名 APK (apksigner)..." -ForegroundColor Cyan
$DebugKeystore = Join-Path $env:USERPROFILE ".android\debug.keystore"
if (-not (Test-Path $DebugKeystore)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DebugKeystore) | Out-Null
    & $Keytool -genkey -v -keystore $DebugKeystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
    if ($LASTEXITCODE -ne 0) { throw "生成 debug.keystore 失败" }
}

$FinalApk = Join-Path $ProjectRoot "kunqu-gongche-tuner.apk"
& $ApkSigner sign `
    --v4-signing-enabled false `
    --ks $DebugKeystore `
    --ks-key-alias androiddebugkey `
    --ks-pass pass:android `
    --key-pass pass:android `
    --out $FinalApk `
    $AlignedApk
if ($LASTEXITCODE -ne 0) { throw "apksigner 签名失败" }

$verifyOut = & $ApkSigner verify --verbose $FinalApk
if ($LASTEXITCODE -ne 0) {
    $verifyOut | ForEach-Object { Write-Host $_ }
    throw "apksigner 校验失败"
}
$verifyOut | Where-Object { $_ -match "^Verifi" } | ForEach-Object { Write-Host $_ }

$SizeKb = [Math]::Round((Get-Item $FinalApk).Length / 1KB, 1)
Write-Host "`nAPK 构建成功: $FinalApk ($SizeKb KB)" -ForegroundColor Green

if ($Install -or $Launch) {
    $SdkAdb = Join-Path $SdkDir "platform-tools\adb.exe"
    if (Test-Path $SdkAdb) {
        $AdbPath = $SdkAdb
    } else {
        $Adb = Get-Command adb -ErrorAction SilentlyContinue
        if (-not $Adb) { throw "未找到 adb.exe。" }
        $AdbPath = $Adb.Source
    }
    Write-Host "`n正在安装到已连接设备..." -ForegroundColor Cyan
    & $AdbPath devices
    & $AdbPath install -r $FinalApk
    if ($LASTEXITCODE -ne 0) { throw "adb install 失败" }
    if ($Launch) {
        Write-Host "正在启动应用..." -ForegroundColor Cyan
        & $AdbPath shell am start -n "com.kunqu.gongchetuner/.MainActivity"
    }
}
