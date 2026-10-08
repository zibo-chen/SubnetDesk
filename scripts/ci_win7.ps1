param(
    [ValidateSet('x64', 'x86', 'both')]
    [string]$Arch = 'both',
    [string]$CacheRoot = 'C:\SubnetDeskWin7',
    [string]$NasmDirectory = 'C:\scd-tools\nasm'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $repoRoot

function Invoke-Checked([scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Native command failed with exit code $LASTEXITCODE" }
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $visualStudio) { throw 'VS 2022 C++ tools are required' }
$devCmd = Join-Path $visualStudio 'Common7\Tools\VsDevCmd.bat'
$clangDirectory = Join-Path $visualStudio 'VC\Tools\Llvm\x64\bin'
if (-not (Test-Path (Join-Path $clangDirectory 'libclang.dll'))) { throw 'VS LLVM/libclang is required' }
if (-not (Test-Path (Join-Path $NasmDirectory 'nasm.exe'))) { throw 'Set -NasmDirectory to the NASM installation' }

New-Item -ItemType Directory -Force $CacheRoot | Out-Null
$env:RUSTUP_HOME = Join-Path $CacheRoot 'rustup'
$env:CARGO_HOME = Join-Path $CacheRoot 'cargo'
$env:CARGO_BUILD_JOBS = '8'
$env:CMAKE_BUILD_PARALLEL_LEVEL = '8'
$env:LIBCLANG_PATH = $clangDirectory
$env:Path = "$NasmDirectory;$clangDirectory;$env:Path"
$env:VCPKG_ROOT = Join-Path $CacheRoot 'vcpkg'
$env:VCPKG_INSTALLED_ROOT = Join-Path $env:VCPKG_ROOT 'installed'
$env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
Invoke-Checked { rustup toolchain install nightly-2025-08-01 --profile minimal --component rust-src --no-self-update }

$pythonEnv = Join-Path $CacheRoot 'python'
if (-not (Test-Path (Join-Path $pythonEnv 'Scripts\python.exe'))) {
    Invoke-Checked { python -m venv $pythonEnv }
}
$python = Join-Path $pythonEnv 'Scripts\python.exe'
Invoke-Checked { & $python -m pip install brotli }
if (-not (Test-Path (Join-Path $env:VCPKG_ROOT '.git'))) {
    Invoke-Checked { git clone https://github.com/microsoft/vcpkg $env:VCPKG_ROOT }
}
Invoke-Checked { git -C $env:VCPKG_ROOT checkout 120deac3062162151622ca4860575a33844ba10b }
Invoke-Checked { & (Join-Path $env:VCPKG_ROOT 'bootstrap-vcpkg.bat') -disableMetrics }
Invoke-Checked { & $python -m unittest discover -s scripts -p test_win7_build.py }

$architectures = if ($Arch -eq 'both') { @('x64', 'x86') } else { @($Arch) }
foreach ($architecture in $architectures) {
    Write-Output "WIN7_STAGE=MSVC-$architecture"
    # A child developer shell supplies each target's SDK/linker paths without
    # changing the Jenkins agent service's environment.
    $environmentScript = Join-Path $CacheRoot "msvc-$architecture.cmd"
    @"
@echo off
call "$devCmd" -no_logo -host_arch=x64 -arch=$architecture >nul
if errorlevel 1 exit /b %errorlevel%
set
"@ | Set-Content -Encoding ASCII $environmentScript
    $variables = & cmd.exe /d /c $environmentScript
    if ($LASTEXITCODE -ne 0) { throw 'MSVC developer environment failed' }
    foreach ($variable in $variables) {
        $pair = $variable -split '=', 2
        if ($pair.Length -eq 2 -and $pair[0]) {
            [Environment]::SetEnvironmentVariable($pair[0], $pair[1], 'Process')
        }
    }
    # VsDevCmd also sets VCPKG_ROOT to Visual Studio's bundled copy.
    # Restore the isolated dependency tree before both vcpkg and Cargo run.
    $env:VCPKG_ROOT = Join-Path $CacheRoot 'vcpkg'
    $env:VCPKG_INSTALLED_ROOT = Join-Path $env:VCPKG_ROOT 'installed'
    $env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
    Write-Output "WIN7_VCPKG_ROOT=$env:VCPKG_ROOT"
    Write-Output "WIN7_STAGE=native-dependencies-$architecture"
    Invoke-Checked {
        & (Join-Path $env:VCPKG_ROOT 'vcpkg.exe') install --enforce-port-checks --triplet "$architecture-windows-static" "--x-manifest-root=$repoRoot/res/win7" "--overlay-triplets=$repoRoot/res/win7/triplets" "--overlay-ports=$repoRoot/res/win7/ports" "--overlay-ports=$repoRoot/res/vcpkg" "--x-install-root=$env:VCPKG_INSTALLED_ROOT"
    }
    Write-Output "WIN7_STAGE=app-service-launcher-$architecture"
    Invoke-Checked { & $python scripts/build_win7.py --arch $architecture }
}
Write-Output 'WIN7_STAGE=completed'
