<#
.SYNOPSIS
  Install the LG warehouse printers on a packing PC. Safe to re-run; run as administrator.

.DESCRIPTION
  1. Zebra  - stages the ZDesigner v10 driver package (C:\LG\zdesigner.tar, copied from another
              station's DriverStore) with pnputil and pre-adds the ZD420 203/300 dpi drivers, so a
              Zebra plugged in over USB binds to the right driver immediately, no download needed.
  2. Network - adds the shared warehouse printers as IPP queues (Microsoft IPP Class Driver), found
              by mDNS name so a DHCP lease change does not break them:
                HP OfficeJet Pro 9130e   HPI34FA9A.local    (packing slips / documents)
                HP Color LaserJet M283cdw NPI65B897.local
                HP LaserJet M209dw        NPI0EB1BE.local
                Epson (Wi-Fi)             EPSONEACE23.local
              A printer that is asleep or off at install time is skipped and retried by the
              LG-PrinterInstall scheduled task (at logon + every 30 min) until every queue exists.
  3. Report  - prints the queues and writes C:\LG\printers-report.json

.PARAMETER ZebraTar   path of the ZDesigner driver tar (default C:\LG\zdesigner.tar)
.PARAMETER NoTask     do not register the retry task
#>
[CmdletBinding()]
param(
  [string]$ZebraTar = 'C:\LG\zdesigner.tar',
  [switch]$NoTask
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$LgDir = 'C:\LG'
New-Item -ItemType Directory -Force -Path $LgDir | Out-Null
$Log = Join-Path $LgDir 'printers-install.log'
function Note([string]$Area, [string]$Msg, [string]$Level = 'OK') {
  $line = '{0:yyyy-MM-dd HH:mm:ss} [{1,-4}] {2,-8} {3}' -f (Get-Date), $Level, $Area, $Msg
  $color = switch ($Level) { 'FAIL' { 'Red' } 'WARN' { 'Yellow' } 'TODO' { 'Magenta' } default { 'Green' } }
  Write-Host $line -ForegroundColor $color
  Add-Content -Path $Log -Value $line
}

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) { Write-Host 'Run from an ADMINISTRATOR PowerShell.' -ForegroundColor Red; return }

$Printers = @(
  @{ Name = 'HP OfficeJet Pro 9130e';    Host = 'HPI34FA9A.local' },
  @{ Name = 'HP Color LaserJet M283cdw'; Host = 'NPI65B897.local' },
  @{ Name = 'HP LaserJet M209dw';        Host = 'NPI0EB1BE.local' },
  @{ Name = 'Epson EPSONEACE23';         Host = 'EPSONEACE23.local' }
)

# ---- 1. Zebra driver ----
Write-Host "`n== Zebra driver ==" -ForegroundColor Cyan
$zebraDir = Join-Path $LgDir 'zdesigner'
if (Test-Path $ZebraTar) {
  New-Item -ItemType Directory -Force -Path $zebraDir | Out-Null
  & tar.exe -xf $ZebraTar -C $zebraDir 2>&1 | Out-Null
  $inf = Get-ChildItem $zebraDir -Filter 'zdesigner.inf' -Recurse | Select-Object -First 1
  if ($inf) {
    $out = & pnputil.exe /add-driver $inf.FullName /install 2>&1
    $added = ($out | Select-String 'Driver package added successfully|already exists|Total driver packages:\s+1' | Measure-Object).Count
    Note 'zebra' ("pnputil: " + (($out | Select-String 'added|exist|Failed|error' | Select-Object -First 2) -join ' / ')) $(if ($added) { 'OK' } else { 'WARN' })
    foreach ($drv in 'ZDesigner ZD420-300dpi ZPL', 'ZDesigner ZD420-203dpi ZPL') {
      if (Get-PrinterDriver -Name $drv -ErrorAction SilentlyContinue) { Note 'zebra' "$drv already present" }
      else {
        try { Add-PrinterDriver -Name $drv -ErrorAction Stop; Note 'zebra' "$drv added" }
        catch { Note 'zebra' ("{0}: {1}" -f $drv, $_.Exception.Message) 'WARN' }
      }
    }
  } else { Note 'zebra' "no zdesigner.inf inside $ZebraTar" 'WARN' }
} else {
  if (Get-PrinterDriver -Name 'ZDesigner ZD420-300dpi ZPL' -ErrorAction SilentlyContinue) { Note 'zebra' 'driver already present (no tar needed)' }
  else { Note 'zebra' "$ZebraTar not found - copy it from another station (tar.exe -cf of its zdesigner.inf_amd64_* DriverStore folder)" 'TODO' }
}
# Zebra USB power management off (same as station-setup.ps1), harmless if no Zebra yet
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'VID_0A5F*' } | Get-ChildItem | ForEach-Object {
  $dp = Join-Path $_.PSPath 'Device Parameters'
  if (Test-Path $dp) { Set-ItemProperty -Path $dp -Name 'EnhancedPowerManagementEnabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue }
}

# ---- 2. Network printers over IPP ----
Write-Host "`n== Network printers (IPP) ==" -ForegroundColor Cyan
$missing = @()
foreach ($p in $Printers) {
  if (Get-Printer -Name $p.Name -ErrorAction SilentlyContinue) { Note 'ipp' ("{0}: already installed" -f $p.Name); continue }
  $ip = $null
  try { $ip = ([System.Net.Dns]::GetHostAddresses($p.Host) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1).IPAddressToString } catch {}
  if (-not $ip) {
    $pong = ping.exe -4 -n 1 -w 1500 $p.Host 2>&1 | Select-String 'Reply from ([0-9.]+)' | Select-Object -First 1
    if ($pong) { $ip = $pong.Matches[0].Groups[1].Value }
  }
  if (-not $ip) { Note 'ipp' ("{0}: {1} not on the network right now - will retry" -f $p.Name, $p.Host) 'TODO'; $missing += $p.Name; continue }
  $reach = Test-NetConnection -ComputerName $ip -Port 631 -WarningAction SilentlyContinue -InformationLevel Quiet
  if (-not $reach) { Note 'ipp' ("{0}: {1} ({2}) does not answer on 631 - will retry" -f $p.Name, $p.Host, $ip) 'TODO'; $missing += $p.Name; continue }
  $ok = $false
  foreach ($url in @("ipp://$($p.Host)/ipp/print", "ipp://$ip/ipp/print")) {
    try { Add-Printer -Name $p.Name -IppURL $url -ErrorAction Stop; Note 'ipp' ("{0}: installed via {1}" -f $p.Name, $url); $ok = $true; break }
    catch { Note 'ipp' ("{0}: {1} -> {2}" -f $p.Name, $url, $_.Exception.Message) 'WARN' }
  }
  if (-not $ok) { $missing += $p.Name }
}

# ---- retry task until everything is installed ----
$taskName = 'LG-PrinterInstall'
$self = Join-Path $LgDir 'printers-install.ps1'
if ($PSCommandPath -and ($PSCommandPath -ne $self)) { Copy-Item $PSCommandPath $self -Force -ErrorAction SilentlyContinue }
if (-not (Test-Path $self)) {
  # piped in through irm: keep a copy on disk for the retry task
  try { Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/yorkhanna-collab/lg-warehouse-stations/main/printers-install.ps1' -OutFile $self -ErrorAction Stop } catch { Note 'task' ("could not save a copy of this script: {0}" -f $_.Exception.Message) 'WARN' }
}
if ($missing.Count -gt 0 -and -not $NoTask) {
  if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$self`""
    $t1 = New-ScheduledTaskTrigger -AtLogOn
    $t2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 30)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $t1, $t2 -Settings $settings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
    Note 'task' ("{0} registered: retries {1}" -f $taskName, ($missing -join ', '))
  } else { Note 'task' ("{0} still pending: {1}" -f $taskName, ($missing -join ', ')) 'TODO' }
} elseif ($missing.Count -eq 0) {
  if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false; Note 'task' "$taskName removed - every printer is installed" }
}

# ---- 3. report ----
Write-Host "`n== Queues ==" -ForegroundColor Cyan
$queues = Get-Printer | Select-Object Name, DriverName, PortName, PrinterStatus
$queues | Format-Table -AutoSize | Out-String -Width 160 | Write-Host
[pscustomobject]@{
  computer = $env:COMPUTERNAME; when = (Get-Date).ToString('s'); missing = $missing
  queues = $queues; drivers = @(Get-PrinterDriver | Select-Object -ExpandProperty Name)
} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $LgDir 'printers-report.json') -Encoding UTF8
