Shared multi-agent work log. Append-only.

---
Task ID: 0-reset
Agent: main
Task: Rebuild BNAsec 2.0.0 from scratch after second sandbox reset

Work Log:
- Sandbox reset detected: /home/z/my-project wiped (90MB used, only platform scaffold left)
- Previous session's rootfs (1,578 pkgs), tools-root, repo indexes, scripts all lost
- New resilience strategy: git commit scripts at every milestone; rootfs checkpoint as squashfs for GitHub Release upload once user provides token (pending)
- User requirements confirmed this session: hybrid BIOS+UEFI ISO (fix "USB not shown in boot menu"), full-root persistence via auto-created partition using ALL free USB space, plymouth splash with BNAsec logo (not boot text), backup to GitHub private repo "bnasec-os" (token pending), website rebuild

Stage Summary:
- Full rootless rebuild initiated: fakechroot+fakeroot mmdebstrap pipeline, trixie, GNOME+GDM3+6 tools
- Pipeline: Stage A bootstrap -> Stage B apt install -> customize -> splash/persistence -> squashfs -> hybrid ISO -> QEMU verify -> deliverables -> website -> GitHub

---
Task ID: 1-github-backup
Agent: main
Task: Push everything to GitHub (user: "everything you do must go to github")

Work Log:
- Token verified: user f1999society-cmd; repo bnasec-os (private) already existed with 13 checkpoint commits + checkpoint release (rootfs squashfs 1364MB)
- Freed disk (deleted test-usb.img); committed checkpoint 14 (reference-initramfs-persist) and pushed
- Created release v2.0.0; uploaded bnasec-2.0.0-amd64.iso (1660682240 bytes, state uploaded) + .sha256
- ISO SHA256: 2ef97a750691dcdd50960d7a4ac2eb6af8c70d6fa428c702009ad6cd68060947

Stage Summary:
- Full disaster-recovery now possible from GitHub alone: git (scripts/history) + checkpoint release (rootfs) + v2.0.0 release (final ISO)

---
Task ID: 2-bug-forensics
Agent: main
Task: Persistence verification exposed catastrophic bug — full forensics

Work Log:
- Re-ran persist:1 fresh-USB test: log shows "creating 8GiB persistence partition" + "persistence ready — rebooting" but byte-level diff of test-usb.img vs ISO found EXACTLY ONE changed byte: 0x01->0x00 at byte 32768 (ISO9660 PVD type byte, start of GPT Gap0 partition = /dev/sda1, 129KB)
- Root cause chain PROVEN: (a) initramfs init-premount hook silently no-ops (USB not enumerated yet); (b) systemd bnasec-persist-setup: lsblk -bno END returned empty -> lastend=0 -> "8GiB" gap; sfdisk binary MISSING from rootfs (fdisk pkg absent, exit 127 hidden by || true) -> no partition created (GPT forensically unchanged); pnum fallback=1 -> mkfs.ext4 -F /dev/sda1 -> mke2fs -q -F on 129KB "succeeds" (exit 0) zeroing byte 32768; (c) boot2: iso9660 unmountable, GRUB cannot load kernel, ZERO serial output in 120s = USB bricked
- Also: persistence.conf ("/ union") was NEVER created by any provisioner — even a correctly-created partition would not activate whole-root persistence
- mke2fs tiny-device behavior reproduced on host: exit 0, first block zeroed

Stage Summary:
- ISO on GitHub (v2.0.0) is BUGGY for persistence — must rebuild before release announcement
- Fix plan: hardened initramfs hook (usb wait + persistence.conf + same-boot activation + console debug), hardened systemd fallback (require sfdisk, sfdisk-d-based lastend, never format pre-existing partitions, persistence.conf), add fdisk pkg to rootfs, rebuild initrd+squashfs+ISO, full 2-boot persistence proof, re-upload

---
Task ID: 3-initrd-saga
Agent: main
Task: Rebuild initramfs with working udev/coldplug (USB medium detection)

Work Log:
- persist:1 test on rebuilt ISO: udevd dead (libcrypt.so.1 dangling symlink in initrd) -> no coldplug -> no USB -> "Unable to find a medium"
- mkinitramfs in fakechroot proved fragile: fakeroot payload errors dropped libs; ldd resolved via host LD_LIBRARY_PATH leak (tools-root paths inside chroot -> copy_file ENOENT); stock hooks (kmod/udev/zz-busybox/klibc-utils/live) failed one by one
- Fixes built and proven: bnasec-chroot-ldd (objdump-based in-chroot ldd, resolves libsystemd-shared via /usr/lib/x86_64-linux-gnu/systemd), hook-functions patched to call it explicitly, explicit kmod/busybox hooks (hardlink applets — sandbox blocks some symlink() calls), udev+plymouth complete-closure hooks with self-verification
- CRITICAL discovery: sq-from-iso (ISO squashfs, built 03:44) is INCOMPLETE (missing klibc lib, iucode_tool) — the 3rd run's unsquashfs silently hit ENOSPC. Current ISO system layer untrustworthy -> full rebuild from GitHub checkpoint required

Stage Summary:
- initramfs toolchain now deterministic and self-verifying
- Next: fetch checkpoint from GitHub release, full rootfs rebuild, apply all fixes, initrd+squashfs+ISO, full test matrix

---
Task ID: 4-reset3-recovery
Agent: main
Task: Third sandbox reset — full recovery from GitHub, rebuild ISO with fixes, test, deliver

Work Log:
- Reset #3 detected: my-project wiped (only platform scaffold); token still valid (user f1999society-cmd)
- GitHub disaster recovery worked: cloned repo (scripts+debs+tools-root), downloaded checkpoint release (1,430,368,256 bytes verified), unsquashed rootfs (131,694 entries, 1587 pkgs, all fixes+tools+themes present)
- Kernel: downloaded linux-image-6.12.107+deb13-amd64_6.12.107-1 (exact version match from frozen repo-index), extracted vmlinuz into rootfs/boot + isostage
- Regenerated assets (logo/wallpaper/grub-bg) + menu tiles + iso-grub.cfg/iso-theme.txt
- Installed all hardened fixes: fixed-initramfs-premount-bnasec-persist, fixed-bnasec-persist-setup, persist-tools/udev-complete/plymouth-complete/kmod-explicit/zz-busybox hooks, bnasec-ldd + hook-functions patch, fdisk deb (sfdisk 2.41.5 verified in-rootfs)
- Rebuilt initramfs (125MB): VERIFIED — trixie layout = raw cpio segment (892 .ko.xz: usb-storage/uas/scsi_mod/sd_mod/sr_mod/isofs/ext4/overlay/squashfs/loop/ahci/virtio/e1000) + zstd frame (init, persist hook, udevadm, plymouthd+theme, busybox, 1519 firmware, 14 udev rules, live-boot scripts)
- Built squashfs 1.43GB -> hybrid ISO 1,574,187,008 bytes (MBR boot + El Torito BIOS + EFI part2 0xef, volid BNASEC)
- Incident: force-push overwrote remote worklog.md with empty file; reconstructed from session context (this file); NO more force pushes

Stage Summary:
- Fixed ISO rebuilt from clean checkpoint+kernel; QEMU test matrix next: BIOS, UEFI, persist boot1+boot2, tools
- NOTE for future agents: use toram/careful git adds; NEVER git add -A at my-project root (rootfs/.git bloat filled disk twice)
