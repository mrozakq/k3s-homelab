# === USTAWIENIA ===
$Base   = 'C:\k3slab'
$Switch = 'switch_one'
$Gw     = '172.18.22.1'
$User   = 'feliks'
$Pass   = 'lab123'
$Nodes  = @(
  @{Name='k3s-server'; Ip='172.18.22.51'},
  @{Name='k3s-agent1'; Ip='172.18.22.52'}
)

function Write-Lf($Path, $Text) { [IO.File]::WriteAllText($Path, ($Text -replace "`r`n","`n")) }

foreach ($n in $Nodes) {
  $name = $n.Name; $dir = "$Base\$name"

  if (Get-VM -Name $name -ErrorAction SilentlyContinue) {
    Write-Host "$name juz istnieje, pomijam"; continue
  }

  New-Item -ItemType Directory $dir -Force | Out-Null
  New-VHD -Path "$dir\os.vhdx" -ParentPath "$Base\base.vhdx" -Differencing | Out-Null

  # dysk seed dla cloud-init
  $seed = "$dir\seed.vhdx"
  New-VHD -Path $seed -SizeBytes 128MB -Dynamic | Out-Null
  $disk = Mount-VHD $seed -Passthru | Get-Disk
  Initialize-Disk $disk.Number -PartitionStyle MBR
  $part = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
  Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel CIDATA -Confirm:$false | Out-Null
  $d = "$($part.DriveLetter):"

  Write-Lf "$d\meta-data" @"
instance-id: $name
local-hostname: $name
"@

  Write-Lf "$d\network-config" @"
version: 2
ethernets:
  lan:
    match:
      driver: hv_netvsc
    set-name: eth0
    dhcp4: false
    addresses: [$($n.Ip)/24]
    routes:
      - to: default
        via: $Gw
    nameservers:
      addresses: [1.1.1.1, 8.8.8.8]
"@

  Write-Lf "$d\user-data" @"
#cloud-config
hostname: $name
users:
  - name: $User
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: $Pass
ssh_pwauth: true
"@

  Dismount-VHD $seed

  New-VM -Name $name -Generation 2 -MemoryStartupBytes 2GB -VHDPath "$dir\os.vhdx" -SwitchName $Switch -Path $dir | Out-Null
  Set-VMProcessor $name -Count 2
  Set-VMMemory $name -DynamicMemoryEnabled $false
  Set-VMFirmware $name -SecureBootTemplate MicrosoftUEFICertificateAuthority
  Add-VMHardDiskDrive $name -Path $seed
  Start-VM $name
  Write-Host "$name -> $($n.Ip)"
}