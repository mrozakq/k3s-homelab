# === USTAWIENIA ===
$Base   = 'C:\k3slab'
$Switch = 'switch_one'
$Gw     = '172.18.22.1'
$User   = 'feliks'
$Pass   = 'lab123'
$name   = 'k3s-dev'
$ip     = '172.18.22.53'

function Write-Lf($Path, $Text) { [IO.File]::WriteAllText($Path, ($Text -replace "`r`n","`n")) }

$dir = "$Base\$name"
New-Item -ItemType Directory $dir -Force | Out-Null
New-VHD -Path "$dir\os.vhdx" -ParentPath "$Base\base.vhdx" -Differencing | Out-Null

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
    addresses: [$ip/24]
    routes:
      - to: default
        via: $Gw
    nameservers:
      addresses: [1.1.1.1, 8.8.8.8]
"@

# czesc z wstawionymi zmiennymi PowerShell
$ud1 = @"
#cloud-config
hostname: $name
users:
  - name: $User
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: $Pass
ssh_pwauth: true
package_update: true
packages: [git, curl, vim, jq, bash-completion, unzip]
"@

# czesc doslowna (znaki $ zostaja dla basha)
$ud2 = @'
write_files:
  - path: /etc/profile.d/k8s.sh
    content: |
      if [ -n "$BASH_VERSION" ] && command -v kubectl >/dev/null; then
        source <(kubectl completion bash)
        alias k=kubectl
        complete -o default -F __start_kubectl k
      fi
runcmd:
  - curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  - chmod +x /usr/local/bin/kubectl
  - curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  - curl -fsSL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz | tar -xz -C /usr/local/bin k9s
'@

Write-Lf "$d\user-data" ($ud1 + "`n" + $ud2)
Dismount-VHD $seed

New-VM -Name $name -Generation 2 -MemoryStartupBytes 2GB -VHDPath "$dir\os.vhdx" -SwitchName $Switch -Path $dir | Out-Null
Set-VMProcessor $name -Count 2
Set-VMMemory $name -DynamicMemoryEnabled $false
Set-VMFirmware $name -SecureBootTemplate MicrosoftUEFICertificateAuthority
Add-VMHardDiskDrive $name -Path $seed
Start-VM $name
Write-Host "$name -> $ip"