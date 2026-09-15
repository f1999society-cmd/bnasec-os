# BNAsec 2.0.0 — Security Testing Live OS

Debian 13 (trixie) live ISO: GNOME + GDM3 autologin `bna`, zsh + powerlevel10k,
dark BNAsec theme, 6 pentest tools, hybrid BIOS+UEFI boot, plymouth splash,
full-root persistence auto-provisioned on first boot.

## Files
- `bnasec-2.0.0-amd64.iso` — the ISO (hybrid: flash to USB or burn)
- `bnasec-2.0.0-amd64.iso.sha256` — SHA256 checksum

## Verify
```
sha256sum -c bnasec-2.0.0-amd64.iso.sha256
```

## Flash to USB (replaces everything on the stick)
```
# Linux
dd if=bnasec-2.0.0-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
# macOS
sudo dd if=bnasec-2.0.0-amd64.iso of=/dev/rdiskX bs=4m
# Windows: use Rufus (DD mode) or balenaEtcher
```
Replace `/dev/sdX` with YOUR USB device (`lsblk` to identify). Double-check — dd destroys the target.

## Boot
- **Secure Boot must be OFF** in firmware settings (the kernel is not signed).
- Pick the USB in the boot menu (BIOS and UEFI both supported).
- GRUB menu → "BNAsec 2.0.0 — live (full persistence)".

## Persistence (whole root)
On first boot from USB the system automatically:
1. Creates a new partition using **all remaining free space** on the stick,
2. Formats it ext4 labeled `persistence`,
3. Writes `/persistence.conf` with `/ union`,
4. Activates whole-root persistence **on the same boot** — no reboot needed.

Everything you change (installed packages, files, settings) survives reboots
and shutdowns. Keep the ISO files on the stick untouched — they live in their
own partition and are never modified.

## Sessions
- **live (full persistence)** — default; persistent
- **RAM-only session (no persistence)** — nothing is written
- **verbose console (debug)** — serial console for debugging

## Login
User `bna`, password `bna` — set on first boot automatically; GDM logs you in
automatically. Change it any time with `passwd`.

## Tools
aircrack-ng · nmap · hydra · wpscan · dirb · sqlmap
(wpscan is at `/usr/local/bin/wpscan`)

## Notes
- Hostname: `bnasec`
- Plymouth splash shows the BNAsec logo; press ESC during boot for verbose output.
- The ISO is ~1.6 GB; after first-boot provisioning you get the rest of the
  stick (~6.4 GB on an 8 GB stick) as persistent storage.
