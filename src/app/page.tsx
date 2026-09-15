import Image from 'next/image'
import {
  Download,
  ShieldCheck,
  HardDriveDownload,
  MonitorSmartphone,
  Sparkles,
  Terminal,
  Usb,
  Disc3,
  AlertTriangle,
  Github,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { CopyField } from '@/components/copy-field'
import { isoInfo, formatSize } from '@/lib/deliverables'

const TOOLS = [
  { name: 'aircrack-ng', desc: 'Wi-Fi auditing & WEP/WPA cracking' },
  { name: 'nmap', desc: 'Network discovery & port scanning' },
  { name: 'hydra', desc: 'Parallelized login brute-forcing' },
  { name: 'wpscan', desc: 'WordPress vulnerability scanner' },
  { name: 'dirb', desc: 'Web content & directory bruteforcing' },
  { name: 'sqlmap', desc: 'Automatic SQL injection testing' },
]

const FEATURES = [
  {
    icon: HardDriveDownload,
    title: 'Full-root persistence',
    desc: 'First boot auto-creates a persistence partition using ALL free space on the stick. The entire root filesystem is writable — installed packages, files and settings survive every reboot.',
  },
  {
    icon: MonitorSmartphone,
    title: 'Hybrid BIOS + UEFI',
    desc: 'One image boots on legacy BIOS machines and modern UEFI firmware alike (Secure Boot must be OFF). No more missing boot entries.',
  },
  {
    icon: Sparkles,
    title: 'BNAsec boot splash',
    desc: 'Plymouth shows the BNAsec logo with a spinner instead of scrolling boot text. Themed GRUB menu with persistent / RAM-only / debug entries.',
  },
  {
    icon: Terminal,
    title: 'zsh + powerlevel10k',
    desc: 'Auto-logged-in GNOME desktop (user bna) with a dark BNAsec theme, powerlevel10k prompt, lock screen and trackers disabled.',
  },
]

export default function Home() {
  const info = isoInfo()
  const sizeLabel = info.exists ? formatSize(info.size) : '—'

  return (
    <div className="relative flex min-h-screen flex-col bg-[#0b1020] text-zinc-100">
      {/* hex-pattern backdrop */}
      <div
        className="pointer-events-none absolute inset-0 opacity-40"
        style={{
          backgroundImage: 'url(/bnasec-wallpaper.png)',
          backgroundSize: 'cover',
          backgroundPosition: 'center',
        }}
        aria-hidden
      />
      <div
        className="pointer-events-none absolute inset-0 bg-gradient-to-b from-[#0b1020]/60 via-[#0b1020]/85 to-[#0b1020]"
        aria-hidden
      />

      {/* header */}
      <header className="relative z-10 border-b border-white/5">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-4 sm:px-6">
          <div className="flex items-center gap-3">
            <Image
              src="/bnasec-logo.png"
              alt="BNAsec logo"
              width={40}
              height={40}
              className="rounded-lg"
              priority
            />
            <div>
              <span className="block text-lg font-bold tracking-tight">BNAsec</span>
              <span className="block text-[11px] text-zinc-400">security testing platform</span>
            </div>
          </div>
          <Badge
            variant="outline"
            className="border-cyan-400/30 bg-cyan-400/10 font-mono text-cyan-300"
          >
            v2.0.0
          </Badge>
        </div>
      </header>

      <main className="relative z-10 mx-auto w-full max-w-5xl flex-1 px-4 sm:px-6">
        {/* hero */}
        <section className="py-12 text-center sm:py-16">
          <h1 className="text-4xl font-extrabold tracking-tight sm:text-5xl">
            BNAsec <span className="text-cyan-400">2.0.0</span>
          </h1>
          <p className="mx-auto mt-4 max-w-2xl text-balance text-sm leading-relaxed text-zinc-400 sm:text-base">
            A Debian 13 (trixie) live security-testing OS. Boot from USB with a full GNOME desktop,
            six pentest tools ready, whole-root persistence, and your own boot splash — verified
            working on both BIOS and UEFI.
          </p>

          <div className="mx-auto mt-8 max-w-md space-y-4">
            <Button
              asChild
              size="lg"
              className="h-14 w-full bg-cyan-500 text-base font-semibold text-[#0b1020] shadow-lg shadow-cyan-500/20 hover:bg-cyan-400"
            >
              <a href="/api/iso" download>
                <Download className="mr-2 h-5 w-5" />
                Download ISO · {sizeLabel}
              </a>
            </Button>
            <p className="text-xs text-zinc-500">
              Resumable download · {info.exists ? `${info.size.toLocaleString()} bytes` : 'ISO not found'}
            </p>
            {info.sha256 && <CopyField value={info.sha256} label="SHA256 checksum" />}
          </div>
        </section>

        {/* proof screenshot */}
        <section className="pb-12">
          <figure className="overflow-hidden rounded-xl border border-white/10 shadow-2xl shadow-black/40">
            <Image
              src="/uefi-desktop.png"
              alt="BNAsec 2.0.0 running — GNOME desktop with BNAsec wallpaper, captured from a verified UEFI boot"
              width={1280}
              height={800}
              className="h-auto w-full"
              priority
            />
            <figcaption className="border-t border-white/10 bg-black/40 px-4 py-2 text-center text-xs text-zinc-500">
              Actual boot screenshot — UEFI (OVMF) verification run, GNOME desktop after auto-login
            </figcaption>
          </figure>
        </section>

        {/* features */}
        <section className="pb-12">
          <h2 className="mb-6 text-center text-2xl font-bold tracking-tight">
            Why you&apos;ll like this build
          </h2>
          <div className="grid gap-4 sm:grid-cols-2">
            {FEATURES.map((f) => (
              <div
                key={f.title}
                className="rounded-xl border border-white/10 bg-white/[0.03] p-6 transition-colors hover:border-cyan-400/20 hover:bg-white/[0.05]"
              >
                <f.icon className="mb-3 h-6 w-6 text-cyan-400" aria-hidden />
                <h3 className="mb-2 font-semibold">{f.title}</h3>
                <p className="text-sm leading-relaxed text-zinc-400">{f.desc}</p>
              </div>
            ))}
          </div>
        </section>

        {/* tools */}
        <section className="pb-12">
          <h2 className="mb-6 text-center text-2xl font-bold tracking-tight">
            Six tools, preinstalled
          </h2>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {TOOLS.map((t) => (
              <div
                key={t.name}
                className="rounded-lg border border-white/10 bg-black/30 p-4"
              >
                <div className="font-mono text-sm font-semibold text-cyan-300">{t.name}</div>
                <div className="mt-1 text-xs leading-relaxed text-zinc-400">{t.desc}</div>
              </div>
            ))}
          </div>
        </section>

        {/* quick start */}
        <section className="pb-16">
          <h2 className="mb-6 text-center text-2xl font-bold tracking-tight">Quick start</h2>
          <div className="grid gap-4 md:grid-cols-2">
            <div className="rounded-xl border border-white/10 bg-white/[0.03] p-6">
              <div className="mb-4 flex items-center gap-2">
                <Usb className="h-5 w-5 text-cyan-400" aria-hidden />
                <h3 className="font-semibold">Flash to USB</h3>
              </div>
              <pre className="max-h-96 overflow-x-auto rounded-lg bg-black/50 p-3 font-mono text-xs leading-relaxed text-zinc-300">
{`# Linux
dd if=bnasec-2.0.0-amd64.iso \\
  of=/dev/sdX bs=4M status=progress oflag=sync

# macOS
sudo dd if=bnasec-2.0.0-amd64.iso \\
  of=/dev/rdiskX bs=4m

# Windows: Rufus (DD mode) or balenaEtcher`}
              </pre>
              <p className="mt-3 text-xs text-zinc-500">
                Replace <code className="font-mono text-zinc-400">/dev/sdX</code> with your USB
                device (<code className="font-mono text-zinc-400">lsblk</code>). dd destroys the
                target — double-check.
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/[0.03] p-6">
              <div className="mb-4 flex items-center gap-2">
                <Disc3 className="h-5 w-5 text-cyan-400" aria-hidden />
                <h3 className="font-semibold">Boot it</h3>
              </div>
              <ul className="space-y-3 text-sm leading-relaxed text-zinc-400">
                <li className="flex gap-2">
                  <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-cyan-400" aria-hidden />
                  <span>
                    Pick the USB stick in your firmware&apos;s boot menu — both BIOS and UEFI are
                    supported from the same image.
                  </span>
                </li>
                <li className="flex gap-2">
                  <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-400" aria-hidden />
                  <span>
                    <strong className="text-amber-300">Secure Boot must be OFF</strong> — the
                    kernel is not signed.
                  </span>
                </li>
                <li className="flex gap-2">
                  <HardDriveDownload className="mt-0.5 h-4 w-4 shrink-0 text-cyan-400" aria-hidden />
                  <span>
                    First boot auto-creates the persistence partition with all remaining space —
                    everything you save survives reboots.
                  </span>
                </li>
              </ul>
              <div className="mt-4 rounded-lg border border-white/10 bg-black/40 p-3 text-xs text-zinc-400">
                <span className="font-semibold text-zinc-300">Login:</span> user{' '}
                <code className="font-mono text-cyan-300">bna</code>, password{' '}
                <code className="font-mono text-cyan-300">bna</code> — GDM logs you in
                automatically. Change it with <code className="font-mono">passwd</code>.
              </div>
            </div>
          </div>
        </section>
      </main>

      {/* footer */}
      <footer className="relative z-10 mt-auto border-t border-white/5 bg-black/30 pb-[env(safe-area-inset-bottom)]">
        <div className="mx-auto flex max-w-5xl flex-col items-center justify-between gap-3 px-4 py-4 text-xs text-zinc-500 sm:flex-row sm:px-6">
          <span>BNAsec 2.0.0 · Debian trixie · built &amp; verified in QEMU</span>
          <a
            href="https://github.com/f1999society-cmd/bnasec-os/releases/tag/v2.0.0"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1.5 transition-colors hover:text-cyan-300"
          >
            <Github className="h-3.5 w-3.5" aria-hidden />
            GitHub Release
          </a>
        </div>
      </footer>
    </div>
  )
}
