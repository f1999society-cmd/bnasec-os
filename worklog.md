# BNAsec 2.0.0 Build Worklog

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
