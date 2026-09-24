<#
.SYNOPSIS
  Liquor Geeks warehouse packing-station setup + Zebra/ShipStation Connect hardening.

.DESCRIPTION
  Run ONCE per packing PC from an *administrator* PowerShell. Safe to re-run.
  What it does:
    1. Inventory  - Windows, network (wired vs Wi-Fi), USB Zebra devices, printer queues,
                    ShipStation Connect state, power settings  -> C:\LG\station-report.json
    2. Power      - never sleep on AC, hibernate + Fast Startup off, USB selective suspend off,
                    "allow the computer to turn off this device" off on every USB hub + Zebra,
                    Zebra Enhanced Power Management off (the classic "printer goes offline" cause)
    3. Printing   - Print Spooler auto-restart, Windows no longer swaps the default printer,
                    Zebra queues taken out of "Use Printer Offline", ghost queues reported
    4. Connect    - ShipStation Connect installed if missing, auto-start at logon,
                    5-minute watchdog that relaunches it and clears Zebra offline flags
    5. Remote     - Tailscale joins the LG tailnet (hostname lg-station-N), OpenSSH server +
                    Remote Desktop reachable only from the tailnet, so the rest can be fixed remotely

.PARAMETER TsKey
  Tailscale auth key (tskey-auth-...). Also read from $env:TS_AUTHKEY.
.PARAMETER Station
  1, 2 or 3 -> tailnet hostname lg-station-1/2/3. 0 = lg-<windows-name>.
.EXAMPLE
  Set-ExecutionPolicy Bypass -Scope Process -Force
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/yorkhanna-collab/lg-warehouse-stations/main/station-setup.ps1))) -TsKey 'tskey-auth-XXXX' -Station 1
#>
[CmdletBinding()]
param(
  [string]$TsKey = $env:TS_AUTHKEY,
  [int]$Station = 0,
  [switch]$SkipTailscale,
  [switch]$SkipSsh,
  [switch]$SkipRdp,
  [switch]$ReportOnly
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$Script:Version = '2026-09-24.1'
$LgDir = 'C:\LG'
New-Item -ItemType Directory -Force -Path $LgDir | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LgDir "station-setup-$Stamp.log"
try { Start-Transcript -Path $LogFile -Force | Out-Null } catch {}

# ---- authorized SSH keys (York's laptop + the Mac mini). Public keys only. ----
$AuthorizedKeys = @(
  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO7XKqXPPWccosK5i9E+uwQmSNpHx1UQo14YMgcpijnj york@macbook->mini'
  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFeNznFi6Yhtzibn+Uw03r7i4q0nu9IpYSEN+a3y9y+E macmini-to-stations'
)
$TailnetCidr = '100.64.0.0/10'   # Tailscale CGNAT range
$ConnectSetupUrl = 'https://downloads.shipstation.com/connect/prod/shipstation/win/5.3.1/ShipStation%20Connect%20Setup.exe'
$TailscaleMsiUrl = 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi'

$Summary = New-Object System.Collections.ArrayList
function Note([string]$Area, [string]$Msg, [string]$Level = 'OK') {
  $line = '[{0,-4}] {1,-9} {2}' -f $Level, $Area, $Msg
  switch ($Level) { 'FAIL' { Write-Host $line -ForegroundColor Red } 'WARN' { Write-Host $line -ForegroundColor Yellow } 'TODO' { Write-Host $line -ForegroundColor Magenta } default { Write-Host $line -ForegroundColor Green } }
  [void]$Summary.Add([pscustomobject]@{ level = $Level; area = $Area; msg = $Msg })
}
function Step([string]$Title) { Write-Host ''; Write-Host ("== $Title ==") -ForegroundColor Cyan }
function Try-Run([string]$What, [scriptblock]$Block) {
  try { & $Block } catch { Note 'error' ("{0}: {1}" -f $What, $_.Exception.Message) 'WARN' }
}

Write-Host ''
Write-Host "LG packing-station setup $Script:Version  ($env:COMPUTERNAME, user $env:USERNAME)" -ForegroundColor Cyan
Write-Host "Log: $LogFile"

# ---- admin check (a #Requires line is ignored when the script is piped through irm) ----
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
  Write-Host 'This must run from an ADMINISTRATOR PowerShell (right-click PowerShell -> Run as administrator).' -ForegroundColor Red
  try { Stop-Transcript | Out-Null } catch {}
  return
}

# =====================================================================================
# 1. INVENTORY
# =====================================================================================
Step 'Inventory'
$Inv = [ordered]@{}
$Inv.script_version = $Script:Version
$Inv.taken_at = (Get-Date).ToString('s')
$Inv.computer = $env:COMPUTERNAME
$Inv.user = "$env:USERDOMAIN\$env:USERNAME"
Try-Run 'os' {
  $os = Get-CimInstance Win32_OperatingSystem
  $Inv.os = "$($os.Caption) $($os.Version) build $($os.BuildNumber)"
  $Inv.last_boot = $os.LastBootUpTime.ToString('s')
  $Inv.uptime_hours = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
  $cs = Get-CimInstance Win32_ComputerSystem
  $Inv.model = "$($cs.Manufacturer) $($cs.Model)"
  $Inv.ram_gb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
}
Try-Run 'users' {
  $Inv.local_users = @(Get-LocalUser | Where-Object Enabled | Select-Object -ExpandProperty Name)
  $Inv.logged_on = @((Get-CimInstance Win32_LoggedOnUser | ForEach-Object { $_.Antecedent.Name }) | Sort-Object -Unique)
}
Try-Run 'network' {
  $Inv.adapters = @(Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
    $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    [pscustomobject]@{ name = $_.Name; type = $_.InterfaceDescription; media = $_.MediaType; link = $_.LinkSpeed; ip = $ip; mac = $_.MacAddress }
  })
  $wlan = (netsh wlan show interfaces 2>$null) -join "`n"
  if ($wlan -match '\s+SSID\s+:\s+(.+)') { $Inv.wifi_ssid = $Matches[1].Trim() }
  if ($wlan -match 'Signal\s+:\s+(.+)') { $Inv.wifi_signal = $Matches[1].Trim() }
  $wired = @($Inv.adapters | Where-Object { $_.media -eq '802.3' -and $_.ip })
  $wifi = @($Inv.adapters | Where-Object { $_.media -like '*802.11*' -and $_.ip })
  if ($wired.Count -gt 0) { Note 'network' ("wired {0} ({1})" -f $wired[0].ip, $wired[0].link) }
  elseif ($wifi.Count -gt 0) { Note 'network' ("Wi-Fi only: SSID '{0}' signal {1} ip {2} - a packing PC should be on a cable" -f $Inv.wifi_ssid, $Inv.wifi_signal, $wifi[0].ip) 'WARN' }
  else { Note 'network' 'no active adapter with an IPv4 address' 'WARN' }
  try { $Inv.public_ip = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 8) } catch {}
}
Try-Run 'zebra-usb' {
  $Inv.zebra_devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_0A5F' -or $_.FriendlyName -match 'Zebra|ZDesigner|ZD420|ZD620|GX420|GK420|ZP450|ZP505' } | ForEach-Object {
    [pscustomobject]@{ name = $_.FriendlyName; class = $_.Class; status = $_.Status; instance = $_.InstanceId }
  })
  if ($Inv.zebra_devices.Count -eq 0) { Note 'zebra' 'no Zebra USB device is currently present (unplugged, powered off, or on a dead cable/hub)' 'WARN' }
  else { $Inv.zebra_devices | ForEach-Object { Note 'zebra' ("USB device present: {0} [{1}] {2}" -f $_.name, $_.class, $_.status) } }
  $Inv.usb_hubs = @(Get-PnpDevice -PresentOnly -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Hub' } | Select-Object -ExpandProperty FriendlyName)
}
Try-Run 'printers' {
  $ports = @{}
  Get-PrinterPort -ErrorAction SilentlyContinue | ForEach-Object { $ports[$_.Name] = $_ }
  $Inv.printers = @(Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
    $w = Get-CimInstance Win32_Printer -Filter ("Name='{0}'" -f ($_.Name -replace "'", "''")) -ErrorAction SilentlyContinue
    [pscustomobject]@{
      name = $_.Name; driver = $_.DriverName; port = $_.PortName; status = [string]$_.PrinterStatus
      is_zebra = [bool]($_.DriverName -match 'Zebra|ZDesigner' -or $_.Name -match 'Zebra|ZDesigner|ZD420|GX420|GK420|ZP450')
      port_exists = $ports.ContainsKey($_.PortName)
      work_offline = [bool]$w.WorkOffline
      default = [bool]$w.Default
      jobs = (Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue | Measure-Object).Count
      shared = $_.Shared
    }
  })
  foreach ($p in ($Inv.printers | Where-Object is_zebra)) {
    $lvl = 'OK'; $extra = ''
    if (-not $p.port_exists) { $lvl = 'WARN'; $extra = ' PORT MISSING (ghost queue from an old USB port)' }
    if ($p.work_offline) { $lvl = 'WARN'; $extra += ' set to Use Printer Offline' }
    if ($p.jobs -gt 0) { $extra += " $($p.jobs) job(s) queued" }
    Note 'queue' ("{0} | {1} | port {2} | {3}{4}" -f $p.name, $p.driver, $p.port, $p.status, $extra) $lvl
  }
  $ghost = @($Inv.printers | Where-Object { $_.name -match '\(Copy \d+\)' })
  if ($ghost.Count -gt 0) { Note 'queue' ("ghost queues: {0} (left alone - clean up remotely)" -f (($ghost | ForEach-Object name) -join ', ')) 'WARN' }
  $usbPrinterPorts = @($ports.Keys | Where-Object { $_ -like 'USB*' })
  $Inv.usb_printer_ports = $usbPrinterPorts
}
Try-Run 'power' {
  $Inv.power_plan = (powercfg /getactivescheme 2>$null) -join ''
  $Inv.hiberboot = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
  $q = (powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb50f7e206 2>$null) -join "`n"
  if ($q -match 'Current AC Power Setting Index:\s+0x(\w+)') { $Inv.usb_selective_suspend_ac = [int]("0x" + $Matches[1]) }
}
Try-Run 'connect' {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'ShipStationConnect\ShipStation Connect.exe'),
    (Join-Path $env:ProgramFiles 'ShipStation Connect\ShipStation Connect.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'ShipStation Connect\ShipStation Connect.exe')
  )
  $exe = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  $Inv.connect_exe = $exe
  if ($exe) {
    $Inv.connect_version = (Get-Item $exe).VersionInfo.ProductVersion
    $Inv.connect_app_dirs = @(Get-ChildItem (Split-Path $exe) -Directory -Filter 'app-*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
  }
  $Inv.connect_running = [bool](Get-Process -Name 'ShipStation Connect' -ErrorAction SilentlyContinue)
  $Inv.connect_run_key = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).'ShipStation Connect'
  # other users' installs (per-user app)
  $Inv.connect_other_users = @(Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'AppData\Local\ShipStationConnect\ShipStation Connect.exe') } | Select-Object -ExpandProperty Name)
  if ($exe) { Note 'connect' ("installed v{0} for {1}; running={2}; other users with their own install: {3}" -f $Inv.connect_version, $env:USERNAME, $Inv.connect_running, ($Inv.connect_other_users -join ',')) }
  else { Note 'connect' ("ShipStation Connect NOT installed for {0} (users that have it: {1})" -f $env:USERNAME, ($Inv.connect_other_users -join ',')) 'WARN' }
}
Try-Run 'spooler' { $Inv.spooler = (Get-Service Spooler).Status.ToString() }
Try-Run 'tailscale' {
  $ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
  $Inv.tailscale_installed = Test-Path $ts
  if ($Inv.tailscale_installed) {
    try { $st = (& $ts status --json 2>$null) | ConvertFrom-Json; $Inv.tailscale_state = $st.BackendState; $Inv.tailscale_ip = ($st.TailscaleIPs | Where-Object { $_ -like '100.*' } | Select-Object -First 1); $Inv.tailscale_name = $st.Self.HostName } catch {}
  }
}
Try-Run 'ssh' { $Inv.sshd = (Get-Service sshd -ErrorAction SilentlyContinue).Status; if ($null -eq $Inv.sshd) { $Inv.sshd = 'not installed' } else { $Inv.sshd = $Inv.sshd.ToString() } }

$Inv | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $LgDir 'station-report.json') -Encoding UTF8
Note 'report' ("written to {0}" -f (Join-Path $LgDir 'station-report.json'))

if ($ReportOnly) {
  Write-Host ''; Write-Host '-ReportOnly: no changes made.' -ForegroundColor Yellow
  try { Stop-Transcript | Out-Null } catch {}
  return
}

# =====================================================================================
# 2. POWER - the usual reasons a USB Zebra "disconnects"
# =====================================================================================
Step 'Power settings'
Try-Run 'powercfg' {
  powercfg /change standby-timeout-ac 0 | Out-Null
  powercfg /change hibernate-timeout-ac 0 | Out-Null
  powercfg /change disk-timeout-ac 0 | Out-Null
  powercfg /change monitor-timeout-ac 30 | Out-Null
  powercfg /hibernate off | Out-Null
  # USB selective suspend: off on AC and battery
  powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb50f7e206 0 | Out-Null
  powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb50f7e206 0 | Out-Null
  powercfg /setactive SCHEME_CURRENT | Out-Null
  Note 'power' 'never sleep/hibernate on AC, display off after 30 min, USB selective suspend OFF'
}
Try-Run 'fast-startup' {
  New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -PropertyType DWord -Force | Out-Null
  Note 'power' 'Fast Startup off (a "shutdown" is now a real shutdown, so USB state resets)'
}
Try-Run 'device-power' {
  # "Allow the computer to turn off this device to save power" -> off for every USB hub, composite device and Zebra
  $targets = Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction Stop | Where-Object {
    $_.InstanceName -match '^USB\\(ROOT_HUB|VID_)' -or $_.InstanceName -match 'VID_0A5F'
  }
  $n = 0
  foreach ($t in $targets) {
    if ($t.Enable) { try { $t | Set-CimInstance -Property @{ Enable = $false }; $n++ } catch {} }
  }
  Note 'power' ("device-level power management disabled on {0} USB hub/device entries ({1} already off)" -f $n, (@($targets).Count - $n))
}
Try-Run 'zebra-epm' {
  # Zebra KB: Windows "Enhanced Power Management" on the USB printer causes offline/disconnect after idle
  $keys = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^VID_0A5F' }
  $n = 0
  foreach ($k in $keys) {
    foreach ($dev in (Get-ChildItem $k.PSPath -ErrorAction SilentlyContinue)) {
      $dp = Join-Path $dev.PSPath 'Device Parameters'
      if (-not (Test-Path $dp)) { New-Item -Path $dp -Force | Out-Null }
      New-ItemProperty -Path $dp -Name EnhancedPowerManagementEnabled -Value 0 -PropertyType DWord -Force | Out-Null
      New-ItemProperty -Path $dp -Name SelectiveSuspendEnabled -Value 0 -PropertyType DWord -Force | Out-Null
      $n++
    }
  }
  if ($n -gt 0) { Note 'power' ("Zebra Enhanced Power Management + selective suspend off on {0} USB printer instance(s) (takes effect after re-plug/reboot)" -f $n) }
  else { Note 'power' 'no Zebra USB instances found under HKLM\...\Enum\USB\VID_0A5F (printer never plugged into this PC?)' 'WARN' }
}

# =====================================================================================
# 3. PRINTING
# =====================================================================================
Step 'Printing'
Try-Run 'spooler' {
  Set-Service Spooler -StartupType Automatic
  sc.exe failure Spooler reset= 86400 actions= restart/5000/restart/5000/restart/10000 | Out-Null
  if ((Get-Service Spooler).Status -ne 'Running') { Start-Service Spooler }
  Note 'print' 'Print Spooler set to auto-start and auto-restart on crash'
}
Try-Run 'default-printer' {
  # Stop Windows from silently changing the default printer to whatever printed last
  $hives = @('HKCU:') + @(Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$' } | ForEach-Object { "Registry::HKEY_USERS\$($_.PSChildName)" })
  $n = 0
  foreach ($h in $hives) {
    $p = "$h\Software\Microsoft\Windows NT\CurrentVersion\Windows"
    if (Test-Path $p) { New-ItemProperty -Path $p -Name LegacyDefaultPrinterMode -Value 1 -PropertyType DWord -Force | Out-Null; $n++ }
  }
  Note 'print' ("'Let Windows manage my default printer' turned off for {0} user profile(s)" -f $n)
}
Try-Run 'zebra-online' {
  $n = 0
  foreach ($w in (Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { ($_.DriverName -match 'Zebra|ZDesigner' -or $_.Name -match 'Zebra|ZDesigner|ZD420|GX420|GK420|ZP450') -and $_.WorkOffline })) {
    try { $w | Set-CimInstance -Property @{ WorkOffline = $false }; $n++ } catch {}
  }
  if ($n -gt 0) { Note 'print' ("took {0} Zebra queue(s) out of 'Use Printer Offline'" -f $n) } else { Note 'print' 'no Zebra queue was stuck in Use Printer Offline' }
}

# =====================================================================================
# 4. SHIPSTATION CONNECT
# =====================================================================================
Step 'ShipStation Connect'
$ConnectExe = if ($Inv.connect_exe) { $Inv.connect_exe } else { Join-Path $env:LOCALAPPDATA 'ShipStationConnect\ShipStation Connect.exe' }
if (-not (Test-Path $ConnectExe)) {
  Try-Run 'connect-install' {
    $setup = Join-Path $LgDir 'ShipStation Connect Setup.exe'
    Invoke-WebRequest -Uri $ConnectSetupUrl -OutFile $setup -TimeoutSec 300
    Note 'connect' ("downloaded installer ({0} MB) - installing silently for {1}" -f [math]::Round((Get-Item $setup).Length / 1MB, 1), $env:USERNAME)
    Start-Process -FilePath $setup -ArgumentList '--silent' -Wait
    Start-Sleep -Seconds 5
    if (Test-Path $ConnectExe) { Note 'connect' 'installed. It must be SIGNED IN once with the ShipStation login used at this station' 'TODO' }
    else { Note 'connect' 'silent install did not produce the app - run C:\LG\ShipStation Connect Setup.exe by hand' 'WARN' }
  }
}
Try-Run 'connect-autostart' {
  if (Test-Path $ConnectExe) {
    $upd = Join-Path (Split-Path $ConnectExe) 'Update.exe'
    $cmd = if (Test-Path $upd) { ('"{0}" --processStart "ShipStation Connect.exe"' -f $upd) } else { ('"{0}"' -f $ConnectExe) }
    New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'ShipStation Connect' -Value $cmd -PropertyType String -Force | Out-Null
    Note 'connect' ("auto-start at logon set for {0}" -f $env:USERNAME)
    if (-not (Get-Process -Name 'ShipStation Connect' -ErrorAction SilentlyContinue)) { Start-Process -FilePath $ConnectExe; Note 'connect' 'was not running - started it' 'WARN' }
  }
}
Try-Run 'connect-watchdog' {
  $wd = Join-Path $LgDir 'connect-watchdog.ps1'
  @'
# LG Connect watchdog: relaunch ShipStation Connect if it died, clear Zebra "offline" flags. Runs every 5 min as the logged-in user.
$exe = @((Join-Path $env:ProgramFiles 'ShipStation Connect\ShipStation Connect.exe'), (Join-Path $env:LOCALAPPDATA 'ShipStationConnect\ShipStation Connect.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($exe -and -not (Get-Process -Name 'ShipStation Connect' -ErrorAction SilentlyContinue)) {
  Start-Process -FilePath $exe
  Add-Content -Path 'C:\LG\watchdog.log' -Value ("{0} restarted ShipStation Connect for {1}" -f (Get-Date -Format s), $env:USERNAME)
}
foreach ($w in (Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { ($_.DriverName -match 'Zebra|ZDesigner' -or $_.Name -match 'Zebra|ZDesigner|ZD420|GX420|GK420|ZP450') -and $_.WorkOffline })) {
  try { $w | Set-CimInstance -Property @{ WorkOffline = $false }; Add-Content -Path 'C:\LG\watchdog.log' -Value ("{0} cleared offline flag on {1}" -f (Get-Date -Format s), $w.Name) } catch {}
}
'@ | Set-Content -Path $wd -Encoding ASCII
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $wd)
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $trigger.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)).Repetition
  $principal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Limited
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
  Register-ScheduledTask -TaskName 'LG-ConnectWatchdog' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
  Note 'connect' 'watchdog task LG-ConnectWatchdog registered (every 5 min for whoever is logged in)'
}

# =====================================================================================
# 5. REMOTE ACCESS - Tailscale + OpenSSH + RDP, reachable only from the tailnet
# =====================================================================================
Step 'Remote access'
$TsExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
if (-not $SkipTailscale) {
  Try-Run 'tailscale-install' {
    if (-not (Test-Path $TsExe)) {
      $msi = Join-Path $LgDir 'tailscale-setup.msi'
      Invoke-WebRequest -Uri $TailscaleMsiUrl -OutFile $msi -TimeoutSec 300
      $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList ('/i "{0}" /quiet /norestart TS_UNATTENDEDMODE=always' -f $msi) -Wait -PassThru
      if ($p.ExitCode -ne 0) { throw "msiexec exit $($p.ExitCode)" }
      Start-Sleep -Seconds 5
      Note 'tailscale' 'installed'
    } else { Note 'tailscale' 'already installed' }
  }
  Try-Run 'tailscale-up' {
    if (Test-Path $TsExe) {
      $state = ''
      try { $state = ((& $TsExe status --json 2>$null) | ConvertFrom-Json).BackendState } catch {}
      $hn = if ($Station -ge 1) { "lg-station-$Station" } else { 'lg-' + ($env:COMPUTERNAME.ToLower() -replace '[^a-z0-9-]', '-') }
      if ($state -eq 'Running') {
        Note 'tailscale' ("already connected as {0}" -f ((& $TsExe status --json | ConvertFrom-Json).Self.HostName))
      } elseif ($TsKey) {
        & $TsExe up --authkey=$TsKey --hostname=$hn --unattended --accept-routes=false 2>&1 | ForEach-Object { Write-Host "   $_" }
        Start-Sleep -Seconds 3
        $ip = (& $TsExe ip -4 2>$null | Select-Object -First 1)
        if ($ip) { Note 'tailscale' ("connected as {0} -> {1}" -f $hn, $ip) } else { Note 'tailscale' 'tailscale up ran but no IP yet - check `tailscale status`' 'WARN' }
      } else {
        Note 'tailscale' 'installed but no -TsKey given; run: & "C:\Program Files\Tailscale\tailscale.exe" up --authkey=tskey-auth-... --unattended' 'TODO'
      }
    }
  }
}

if (-not $SkipSsh) {
  Try-Run 'openssh' {
    $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
    if ($cap.State -ne 'Installed') {
      Note 'ssh' 'installing OpenSSH Server (Windows capability, 1-3 min)...'
      Add-WindowsCapability -Online -Name $cap.Name | Out-Null
    }
    Set-Service sshd -StartupType Automatic
    New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null
    # Dedicated hidden local administrator for remote management (key-only; the random password is never used).
    try {
      if (-not (Get-LocalUser -Name 'lgadmin' -ErrorAction SilentlyContinue)) {
        $rnd = -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
        New-LocalUser -Name 'lgadmin' -Password (ConvertTo-SecureString $rnd -AsPlainText -Force) -FullName 'LG remote admin' -Description 'LG remote management (SSH key only)' -PasswordNeverExpires -AccountNeverExpires | Out-Null
        Note 'ssh' "created local admin account 'lgadmin' (SSH key only)"
      }
      Add-LocalGroupMember -Group 'Administrators' -Member 'lgadmin' -ErrorAction SilentlyContinue
      # hide it from the Windows sign-in screen
      $ul = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
      if (-not (Test-Path $ul)) { New-Item -Path $ul -Force | Out-Null }
      New-ItemProperty -Path $ul -Name 'lgadmin' -Value 0 -PropertyType DWord -Force | Out-Null
    } catch { Note 'ssh' ("lgadmin account: {0}" -f $_.Exception.Message) 'WARN' }
    $akf = 'C:\ProgramData\ssh\administrators_authorized_keys'
    New-Item -ItemType Directory -Force -Path 'C:\ProgramData\ssh' | Out-Null
    $existing = @(); if (Test-Path $akf) { $existing = Get-Content $akf }
    $merged = @($existing + $AuthorizedKeys | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique)
    Set-Content -Path $akf -Value $merged -Encoding ASCII
    icacls.exe $akf /inheritance:r /grant 'SYSTEM:F' /grant 'BUILTIN\Administrators:F' | Out-Null
    Note 'ssh' 'keys installed for Administrators (administrators_authorized_keys)'
    # ALSO authorize the logged-in packer account, which is usually NOT an admin.
    # Windows OpenSSH reads administrators_authorized_keys only for admins; a standard
    # user is authenticated from their own %USERPROFILE%\.ssh\authorized_keys, so without
    # this the box is unreachable whenever the packer account isn't an administrator.
    foreach ($profileDir in (Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') })) {
      $sshDir = Join-Path $profileDir.FullName '.ssh'
      $uakf = Join-Path $sshDir 'authorized_keys'
      $acct = $profileDir.Name
      try {
        # only touch profiles that map to a real, enabled local account (skip service/system profiles)
        $lu = Get-LocalUser -Name $acct -ErrorAction SilentlyContinue
        if (-not $lu -or -not $lu.Enabled) { Note 'ssh' ("profile '{0}' skipped: no enabled local account of that name (Microsoft-account or domain login?)" -f $acct) 'WARN'; continue }
        New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
        $uexist = @(); if (Test-Path $uakf) { $uexist = Get-Content $uakf }
        $umerged = @($uexist + $AuthorizedKeys | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique)
        Set-Content -Path $uakf -Value $umerged -Encoding ASCII
        icacls.exe $uakf /inheritance:r /grant "${acct}:F" /grant 'SYSTEM:F' /grant 'BUILTIN\Administrators:F' | Out-Null
        Note 'ssh' ("keys installed for local user '{0}'" -f $acct)
      } catch { Note 'ssh' ("could not set authorized_keys for '{0}': {1}" -f $acct, $_.Exception.Message) 'WARN' }
    }
    # firewall: only from the tailnet + the local subnet
    Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Get-NetFirewallRule -DisplayName 'LG SSH (tailnet+LAN)' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName 'LG SSH (tailnet+LAN)' -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -RemoteAddress @($TailnetCidr, 'LocalSubnet') -Profile Any | Out-Null
    Restart-Service sshd
    Note 'ssh' ("OpenSSH server running; keys for York's laptop + Mac mini authorized; port 22 open to {0} + LAN only" -f $TailnetCidr)
  }
}

if (-not $SkipRdp) {
  Try-Run 'rdp' {
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1 -PropertyType DWord -Force | Out-Null
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
    Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue | Set-NetFirewallRule -RemoteAddress @($TailnetCidr, 'LocalSubnet')
    Note 'rdp' ("Remote Desktop on (NLA), reachable from {0} + LAN only" -f $TailnetCidr)
  }
}

# =====================================================================================
# SUMMARY
# =====================================================================================
Step 'Summary'
$after = [ordered]@{ finished_at = (Get-Date).ToString('s'); summary = $Summary }
if (Test-Path $TsExe) { try { $after.tailscale_ip = (& $TsExe ip -4 2>$null | Select-Object -First 1) } catch {} }
$Inv.after = $after
try { $Inv.administrators = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop | Select-Object -ExpandProperty Name) } catch {}
try { $Inv.profiles = @(Get-ChildItem 'C:\Users' -Directory | Select-Object -ExpandProperty Name) } catch {}
$ReportJson = $Inv | ConvertTo-Json -Depth 6
$ReportJson | Set-Content -Path (Join-Path $LgDir 'station-report.json') -Encoding UTF8
# Send the report to the Mac mini over the tailnet (receiver is bound to the tailscale address only).
try {
  $r = Invoke-RestMethod -Method Post -Uri 'http://100.97.249.102:7788/report' -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($ReportJson)) -TimeoutSec 15
  Note 'report' ("uploaded to the Mac mini ({0})" -f ([string]$r).Trim())
} catch { Note 'report' ("upload to the Mac mini failed: {0} (fine if Tailscale is not up yet)" -f $_.Exception.Message) 'WARN' }

$fails = @($Summary | Where-Object level -eq 'FAIL').Count
$warns = @($Summary | Where-Object level -eq 'WARN').Count
$todos = @($Summary | Where-Object level -eq 'TODO')
Write-Host ''
Write-Host ("DONE on {0}: {1} warnings, {2} failures. Report: C:\LG\station-report.json  Log: {3}" -f $env:COMPUTERNAME, $warns, $fails, $LogFile) -ForegroundColor Cyan
if ($after.tailscale_ip) { Write-Host ("Tailnet address: {0}" -f $after.tailscale_ip) -ForegroundColor Green }
if ($todos.Count -gt 0) { Write-Host 'Still needs a person:' -ForegroundColor Magenta; $todos | ForEach-Object { Write-Host ("  - " + $_.msg) -ForegroundColor Magenta } }
Write-Host 'Unplug and re-plug the Zebra USB cable once (or reboot when the shift ends) so the USB power settings take effect.' -ForegroundColor Yellow
try { Stop-Transcript | Out-Null } catch {}
