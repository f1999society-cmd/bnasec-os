import { readFileSync, existsSync } from 'fs'
import { SHA_PATH, README_PATH, isoInfo, formatSize } from '@/lib/deliverables'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

/**
 * GET /api/files -> metadata + text artifacts (sha256, README) as JSON
 */
export async function GET() {
  const info = isoInfo()
  let sha256Text: string | null = null
  let readme: string | null = null
  try {
    if (existsSync(SHA_PATH)) sha256Text = readFileSync(SHA_PATH, 'utf8').trim()
  } catch {}
  try {
    if (existsSync(README_PATH)) readme = readFileSync(README_PATH, 'utf8')
  } catch {}

  return Response.json({
    iso: {
      name: 'bnasec-2.0.0-amd64.iso',
      available: info.exists,
      size: info.size,
      sizeLabel: info.exists ? formatSize(info.size) : null,
      sha256: info.sha256,
      modified: info.mtime,
      downloadUrl: '/api/iso',
    },
    sha256Text,
    readme,
  })
}
