# PowerShell script to register Malinali for "Open With" on Windows.
# Run this once after building the app or moving the folder.

$ExePath = Join-Path $PSScriptRoot "build\windows\x64\runner\Release\malinali.exe"
if (-not (Test-Path $ExePath)) {
    $ExePath = Join-Path $PSScriptRoot "malinali.exe"
}

if (-not (Test-Path $ExePath)) {
    Write-Error "Could not find malinali.exe. Please run this script from the folder containing the executable or from the project root after a build."
    exit 1
}

$ExePath = [System.IO.Path]::GetFullPath($ExePath)
$Command = "`"$ExePath`" `"%1`""

Write-Host "Registering Malinali at: $ExePath"

# 1. Register the application
$AppKey = "Software\Classes\Applications\malinali.exe"
New-Item -Path "HKCU:\$AppKey\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\$AppKey\shell\open\command" -Name "(Default)" -Value $Command

# 2. Add to SupportedTypes
New-Item -Path "HKCU:\$AppKey\SupportedTypes" -Force | Out-Null
$Extensions = @(".opus", ".ogg", ".m4a", ".mp3", ".wav", ".aac", ".amr", ".3gp", ".flac", ".wma", ".webm")
foreach ($Ext in $Extensions) {
    Set-ItemProperty -Path "HKCU:\$AppKey\SupportedTypes" -Name $Ext -Value ""
}

# 3. Create a Friendly Type
$ProgId = "malinali.audio"
New-Item -Path "HKCU:\Software\Classes\$ProgId\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Classes\$ProgId" -Name "(Default)" -Value "Fichier audio Malinali"
Set-ItemProperty -Path "HKCU:\Software\Classes\$ProgId\shell\open\command" -Name "(Default)" -Value $Command

# 4. Associate extensions (Optional: makes it show up more prominently)
foreach ($Ext in $Extensions) {
    $OpenWithKey = "HKCU:\Software\Classes\$Ext\OpenWithProgids"
    if (-not (Test-Path $OpenWithKey)) {
        New-Item -Path $OpenWithKey -Force | Out-Null
    }
    Set-ItemProperty -Path $OpenWithKey -Name $ProgId -Value ""
}

Write-Host "Success! You can now right-click an audio file and select 'Open With' -> 'Malinali'."
Write-Host "Note: You might need to select 'Choose another app' the first time to see it in the list."
