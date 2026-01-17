Kraken OS 
If you need a Linux kernel OS that combines Qubes OS and Tails. 
If you need maximum 
security for everything, 
including encryption, 
anonymity,
and protection.
Full list of technologies used:

1. BASE SYSTEM

· Base: Debian 12 "Bookworm" (amd64)
· Architecture: x86_64 with UEFI/Legacy BIOS support
· Package Manager: APT with hardened repositories
· Minimal base set: debootstrap with variant=minbase

2. INIT SYSTEM

· Primary: Dinit (systemd replacement)
· Configuration: /etc/dinit.d/ custom services
· Services:
  · dinit-console-services
  · dinit-network (NetworkManager)
  · dinit-ssh (OpenSSH server)

3. KERNEL AND MODULES

· Kernel: linux-image-amd64 with security patches
· Firmware:
  · firmware-linux-nonfree
  · firmware-misc-nonfree
  · microcode updates
· Security modules:
  · Disabled: firewire-core, usb-storage, thunderbolt, bluetooth
  · Enabled: kvm, virtio, tpm

SECURITY SYSTEMS

4. MANDATORY ACCESS CONTROL

· SELinux:
  · Policy: selinux-policy-default
  · Tools: setools, policycoreutils, checkpolicy
  · Configuration: enforcing mode with custom contexts
  · Management: semanage, restorecon, audit2allow
· AppArmor:
  · Profiles: apparmor-profiles, apparmor-profiles-extra
  · Utilities: apparmor-utils, aa-status, aa-complain
  · Auto-enforce for all preinstalled profiles

5. CRYPTOGRAPHIC INFRASTRUCTURE

· Disk encryption:
  · LUKS2 via cryptsetup/cryptsetup-initramfs
  · TPM 2.0 integration via clevis-luks
  · Multi-key encryption
  · Configuration via /etc/crypttab
· Signing and verification:
  · sbsigntool for EFI binaries
  · efitools for Secure Boot management
  · shim-signed with MOK (Machine Owner Key)

6. HARDWARE TECHNOLOGIES

· TPM 2.0:
  · tpm2-tools, tpm2-abrmd, tpm2-tss-engine
  · tpm2-pkcs11 for PKCS#11 tokens
  · libtss2-* libraries
  · LUKS integration via clevis-tpm2
· YubiKey/PIV:
  · yubikey-manager, yubikey-personalization
  · yubico-piv-tool for PIV cards
  · libpam-yubico for PAM authentication
  · pcscd (PC/SC daemon)

NETWORK SECURITY

7. FIREWALL AND NETWORK FILTERS

· nftables (iptables replacement):
  · Custom inet/ip/ip6 tables
  · Stateful filtering
  · Geoblocking via ip set
  · MAC address filtering
· Firewall configuration:
  · Default block (deny all)
  · Only SSH and outbound allowed
  · Network zone isolation
  · DDoS and scanning protection

8. NETWORK PROTOCOLS AND STEALTH

· NetworkManager with custom plugins:
  · WPA2-Enterprise support
  · Random MAC addressing
  · VPN integration
  · Tor network routing
· WireGuard:
  · Modern VPN protocol
  · Noise protocol framework
  · Zero-trust configuration

ANONYMITY AND PRIVACY

9. TOR NETWORK

· Tor Core:
  · Multi-port configurations (SocksPort 9050/9051)
  · DNSPort 53 for DNS over Tor
  · TransPort 9040 for transparent proxy
  · AutomapHostsOnResolve for .onion
· Bridges and plugins:
  · Obfs4proxy for obfuscation
  · Snowflake (planned)
  · Meek (planned)
· Geofiltering:
  · ExcludeNodes {ru},{cn},{by},{kz},{ua}
  · ExcludeExitNodes with same countries
  · StrictNodes 1 for strict enforcement

10. ALTERNATIVE NETWORKS

· I2P:
  · i2p-router with custom configuration
  · SAM bridge for applications
  · SusiDNS for anonymous DNS
· RetroShare:
  · P2P encrypted network
  · F2F (friend-to-friend) architecture
  · Distributed hash table

11. DNS SECURITY

· DNSCrypt-proxy:
  · DNS query encryption
  · DoH (DNS over HTTPS) support
  · Anonymized DNS via relays
· Stubby:
  · DNS over TLS
  · Strict TLS verification
  · Multi-resolvers

VIRTUALIZATION AND ISOLATION

12. HARDWARE VIRTUALIZATION (KVM/QEMU)

· KVM (Kernel-based Virtual Machine):
  · kvm kernel module
  · kvm_intel/kvm_amd module
  · /dev/kvm interface
· QEMU system emulation:
  · qemu-system-x86
  · qemu-utils for image management
  · QXL driver for graphics
  · VirtIO for devices
· Libvirt management:
  · libvirt-daemon-system
  · libvirt-clients (virsh)
  · Custom network XML
  · ACL via polkit

13. VM IMAGES AND TEMPLATES

· Disk formats:
  · QCOW2 (copy-on-write)
  · RAW images
  · LVM thin provisioning
· OVMF (UEFI for VMs):
  · Secure boot in VMs
  · TPM emulation via swtpm
  · Secure Boot certificates

14. CONTAINER ISOLATION (FALLBACK)

· Firejail:
  · Isolation profiles
  · seccomp-bpf filters
  · Network namespaces
  · Private /tmp and /dev
· System call restrictions:
  · caps.drop all
  · no_new_privs
  · seccomp strict mode

MONITORING AND AUDIT

15. AUDIT SYSTEM

· auditd framework:
  · Custom rules
  · Kernel auditing
  · System call monitoring
· AIDE (Advanced Intrusion Detection):
  · File integrity monitoring
  · Hash database (SHA256)
  · Automatic checks

16. VULNERABILITY SCANNERS

· Lynis:
  · System hardening auditing
  · Compliance checking
  · Custom profiles
· chkrootkit/rkhunter:
  · Rootkit detection
  · Backdoor scanning
  · Suspicious process detection

SYSTEM SETTINGS AND HARDENING

17. KERNEL HARDENING

· sysctl parameters:
  · kernel.randomize_va_space = 2 (ASLR)
  · kernel.kptr_restrict = 2
  · kernel.dmesg_restrict = 1
  · kernel.unprivileged_bpf_disabled = 1
· Memory protection:
  · vm.mmap_rnd_bits = 32
  · vm.mmap_rnd_compat_bits = 16
  · vm.swappiness = 10
· Network security:
  · net.ipv4.tcp_syncookies = 1
  · net.ipv4.conf.all.rp_filter = 1
  · net.ipv6.conf.all.accept_ra = 0

18. FILESYSTEM

· Mount options:
  · noexec,nosuid,nodev for /tmp
  · strictatime instead of relatime
  · data=journal for ext4
· Filesystem protections:
  · fs.protected_fifos = 2
  · fs.protected_regular = 2
  · fs.protected_hardlinks = 1
  · fs.protected_symlinks = 1

19. PROCESSES AND PERMISSIONS

· PAM (Pluggable Authentication):
  · pam_tally2 for bruteforce blocking
  · pam_cracklib for password complexity
  · pam_limits for resources
· systemd hardening:
  · PrivateTmp=yes
  · NoNewPrivileges=yes
  · ProtectSystem=strict
  · ProtectHome=yes

MANAGEMENT TOOLS

20. SCRIPTS AND AUTOMATION

· kraken-vm-isolate:
  · Automatic virtualization detection
  · VM/container selection
  · Dynamic VM creation
· System utilities:
  · cpu-checker (kvm-ok)
  · virt-top for VM monitoring
  · virt-what for virtualization detection

21. CONFIGURATION MANAGERS

· GRUB2:
  · Encrypted partition support
  · Secure Boot integration
  · Custom Kraken theme
· initramfs-tools:
  · LUKS support
  · TPM2 hooks
  · Network boot modules

UPDATE SYSTEM

22. SECURE UPDATES

· APT hardening:
  · Tor transport for updates
  · GPG key validation
  · Package pinning
· Automatic updates:
  · unattended-upgrades
  · Tor proxy for updates
  · Auto-removal of old kernels

SYSTEM SERVICES

23. BACKGROUND SERVICES

· systemd-timesyncd:
  · NTP over Tor
  · Hardcoded trusted servers
· systemd-journald:
  · ForwardToSyslog=no
  · Compress=yes
  · MaxFileSec=1week
· udisks2:
  · Encrypted drives auto-mount
  · ACL on removable media

INTER-PROCESS COMMUNICATION

24. IPC RESTRICTIONS

· System V IPC:
  · msgmax, msgmnb, msgmni limits
  · shmmax, shmall, shmmni quotas
· POSIX IPC:
  · mqueue limits
  · semaphore restrictions

25. CGROUPS AND NAMESPACES

· cgroup v2:
  · memory controller
  · CPU bandwidth limiting
  · I/O throttling
· Linux namespaces:
  · PID namespace isolation
  · Network namespaces
  · User namespace mapping

PASSWORD POLICY AND AUTHENTICATION

26. PASSWORD POLICY

· pam_pwquality:
  · minlen=14
  · dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1
  · maxrepeat=3
  · difok=7
· pam_faillock:
  · deny=5
  · unlock_time=1800
  · fail_interval=900

27. MULTI-FACTOR AUTHENTICATION

· PAM modules:
  · pam_google_authenticator
  · pam_yubico (YubiKey OTP)
  · pam_ssh_agent_auth

PACKAGE FORMATS AND DEPLOYMENT

28. BUILD SYSTEM

· debootstrap:
  · Minimal base
  · Custom inclusions
  · Local mirror
· xorriso:
  · ISO image creation
  · EFI boot support
  · Hybrid ISO mode (USB ready)

29. PACKAGE SIGNING

· GPG infrastructure:
  · Debian archive keys
  · Custom repository key
  · Package signature verification

INTERNATIONAL SUPPORT

30. LOCALIZATION AND TIME

· Locales: en_US.UTF-8, ru_RU.UTF-8
· Timezone: UTC (forced)
· Keyboard: All layouts, but US default
· Fonts: DejaVu, Noto (Unicode coverage)

PERFORMANCE AND OPTIMIZATION

31. SECURITY OPTIMIZATION

· PaX/grsecurity-like:
  · paxctl for ELF hardening
  · MPROTECT, RANDMMAP, RANDEXEC
  · SEGMEXEC, PAGEEXEC
· Compiler hardening:
  · CFI (Control Flow Integrity)
  · Stack protection (-fstack-protector-strong)
  · PIE (Position Independent Executables)

32. SECURE DELETION

· Secure erase:
  · shred (GNU coreutils)
  · wipe for blocks
  · cryptsetup luksErase

FORENSIC CAPABILITIES

33. TRACE COLLECTION AND ANALYSIS

· Logging infrastructure:
  · Centralized syslog
  · Journald with compression
  · Automatic rotation
· Memory forensics:
  · Linux modules for dumps
  · Volatility support

ADVANCED TECHNOLOGIES

34. MODULAR ARCHITECTURE

· Dynamic module loading:
  · Dangerous module disabling
  · Blacklist mechanism
  · Runtime module signing

35. RESOURCE LIMITATIONS

· ulimits:
  · nofile=1024
  · nproc=512
  · core=0 (no core dumps)

36. NETWORK PROTOCOL PROTECTION

· TCP/IP hardening:
  · TCP SYN cookies
  · ICMP rate limiting
  · ARP spoofing protection

INTERFACES AND APIS

37. DBUS SECURITY

· D-Bus policy:
  · Strict message routing
  · Service whitelisting
  · SELinux context matching

38. udev RULES

· Device management:
  · Persistent network naming
  · USB device restrictions
  · Block device encryption hooks

REMOTE MANAGEMENT

39. SSH HARDENING

· OpenSSH configuration:
  · PermitRootLogin no
  · PasswordAuthentication no
  · AllowUsers user
  · Protocol 2 only

40. REMOTE ATTESTATION

· TPM remote attestation:
  · TPM quote generation
  · Integrity measurement
  · Remote verification

COMPLEX TECHNOLOGIES

41. STACK PROTECTION

· Stack canaries:
  · GCC -fstack-protector-strong
  · Random canary generation
  · Stack gap protection

42. HEAP PROTECTION

· glibc hardening:
  · MALLOC_CHECK_=3
  · FORTIFY_SOURCE=2
  · _FORTIFY_SOURCE=3 (where available)

43. ASLR (Address Space Layout Randomization)

· Full ASLR:
  · Executable ASLR
  · Library ASLR
  · Stack ASLR
  · Heap ASLR

DETECTIVE TECHNOLOGIES

44. HONEYPOT SYSTEMS

· tarpitting:
  · SSH tarpit
  · SMTP tarpit
  · HTTP honeypot

45. BEHAVIOR ANALYSIS

· execution monitoring:
  · Process whitelisting
  · Suspicious exec patterns
  · Inter-process communication monitoring

RECOVERY SYSTEM

46. SYSTEM RECOVERY

· Boot recovery:
  · Rescue kernel
  · Emergency shell
  · Network recovery

47. BACKUP INFRASTRUCTURE

· System state backup:
  · Configuration versioning
  · Package state snapshots
  · Critical data backup

TARGET ARCHITECTURES

48. SUPPORTED PLATFORMS

· Primary: x86_64 with UEFI/BIOS
· Experimental: ARM64 (Raspberry Pi 4)
· Planned: RISC-V

49. VIRTUALIZATION PLATFORMS

· Hypervisors: KVM, Xen (planned)
· Containers: Firejail, systemd-nspawn
· Sandboxes: bubblewrap

PERFORMANCE METRICS

50. SECURITY METRICS

· Audit metrics:
  · Lynis score target: 90+
  · OpenSCAP compliance
  · STIG compliance (partial)

List of pre-installed programs:

Category Primary Applications Alternatives Specialized Tools
Browsers Firefox ESR, Tor Browser Chromium -
Office LibreOffice OnlyOffice Master PDF Editor
Graphics GIMP, Inkscape Darktable, Krita Blender, FreeCAD
Multimedia VLC, OBS Studio Audacity, HandBrake Kodi
File Management Thunar, Ranger Double Commander PeaZip
Terminal Alacritty, tmux Terminator, fish -
Security KeePassXC, VeraCrypt GnuPG, Wireshark Autopsy, John the Ripper
Networking Transmission, FileZilla curl, wget nmap, iperf3
Development VS Code, Git IntelliJ, PyCharm Qt Creator, Eclipse
System Utilities GParted, Timeshift BleachBit, Stacer Hardinfo, sysbench
Virtualization Virt-manager, Docker VirtualBox, Podman Boxes
Gaming Steam, Lutris RetroArch -
Science Geogebra, Octave R Studio, Jupyter KiCad, Arduino
Mobility KDE Connect, scrcpy Syncthing Nextcloud
Translation Crow Translate Translate Shell -
Cryptocurrency Electrum, Monero GUI Wasabi Wallet, Sparrow Wallet -

This OS was created primarily for Russian users to access the Tor browser as conveniently and securely as possible.
And I'm inspired by that same Kraken, to which I have absolutely no sympathy and condemn everything that happens there. 
But everyone makes money as best they can. 
I liked its style and security. 
Kudos to the authors for that alone, and for everything related to it I strongly disapprove, but everyone has their own opinion. 
And I should note that I know there's already an official Kraken OS, but I doubt its authenticity. 
Moreover, this code doesn't run from an installation disk like Tails, but functions as a full-fledged OS. 
I highly recommend testing the OS in an isolated machine before running it. 
And yes, this OS is provided for exclusively legal use.
Any violation of the law is condemned first and foremost by me, and secondly by the STATE.

Кто к нам с мичом придёт тот от мечя и погибель свою сышит .
