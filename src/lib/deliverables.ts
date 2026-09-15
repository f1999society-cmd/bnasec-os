import { statSync, existsSync, readFileSync } from 'fs'

export const ISO_PATH = '/home/z/my-project/bnasec-build/bnasec-2.0.0-amd64.iso'
export const SHA_PATH = '/home/z/my-project/bnasec-build/bnasec-2.0.0-amd64.iso.sha256'
export const README_PATH = '/home/z/my-project/download/README.md'

export const ISO_VERSION = '2.0.0'
export const ISO_NAME = 'bnasec-2.0.0-amd64.iso'

export interface IsoInfo {
  exists: boolean
  size: number
  sha256: string | null
  mtime: string | null
}

export function isoInfo(): IsoInfo {
  try {
    if (!existsSync(ISO_PATH)) return { exists: false, size: 0, sha256: null, mtime: null }
    const st = statSync(ISO_PATH)
    let sha256: string | null = null
    try {
      sha256 = readFileSync(SHA_PATH, 'utf8').trim().split(/\s+/)[0] || null
    } catch {
      sha256 = null
    }
    return {
      exists: true,
      size: st.size,
      sha256,
      mtime: st.mtime.toISOString(),
    }
  } catch {
    return { exists: false, size: 0, sha256: null, mtime: null }
  }
}

export function readmeText(): string | null {
  try {
    if (!existsSync(README_PATH)) return null
    return readFileSync(README_PATH, 'utf8')
  } catch {
    return null
  }
}

export function formatSize(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(2)} GB`
  if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MB`
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${bytes} B`
}
