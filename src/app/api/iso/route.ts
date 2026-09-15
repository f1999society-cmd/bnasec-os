import { NextRequest } from 'next/server'
import { createReadStream, statSync, existsSync } from 'fs'
import { Readable } from 'stream'
import { ISO_PATH, ISO_NAME } from '@/lib/deliverables'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

/**
 * Streams the BNAsec ISO with HTTP Range support (resumable downloads).
 * GET /api/iso            -> full file (200)
 * GET /api/iso Range      -> partial file (206)
 * HEAD /api/iso           -> metadata only
 */
function fileHeaders(size: number, start: number, end: number, partial: boolean) {
  const h = new Headers()
  h.set('Content-Type', 'application/octet-stream')
  h.set('Content-Length', String(end - start + 1))
  h.set('Accept-Ranges', 'bytes')
  h.set('Content-Disposition', `attachment; filename="${ISO_NAME}"`)
  h.set('Cache-Control', 'no-store')
  if (partial) h.set('Content-Range', `bytes ${start}-${end}/${size}`)
  return h
}

export async function GET(req: NextRequest) {
  if (!existsSync(ISO_PATH)) {
    return new Response('ISO not found on server', { status: 404 })
  }
  const size = statSync(ISO_PATH).size
  const range = req.headers.get('range')

  let start = 0
  let end = size - 1
  let partial = false

  if (range) {
    const m = /^bytes=(\d*)-(\d*)$/.exec(range.trim())
    if (!m || (m[1] === '' && m[2] === '')) {
      return new Response('Invalid Range header', {
        status: 416,
        headers: { 'Content-Range': `bytes */${size}` },
      })
    }
    if (m[1] === '') {
      // suffix range: last N bytes
      const n = Math.min(parseInt(m[2], 10), size)
      start = size - n
      end = size - 1
    } else {
      start = parseInt(m[1], 10)
      if (m[2] !== '') end = Math.min(parseInt(m[2], 10), size - 1)
    }
    if (start >= size || start > end) {
      return new Response('Range not satisfiable', {
        status: 416,
        headers: { 'Content-Range': `bytes */${size}` },
      })
    }
    partial = start !== 0 || end !== size - 1
  }

  const stream = createReadStream(ISO_PATH, { start, end })
  return new Response(Readable.toWeb(stream) as ReadableStream, {
    status: partial ? 206 : 200,
    headers: fileHeaders(size, start, end, partial),
  })
}

export async function HEAD() {
  if (!existsSync(ISO_PATH)) return new Response(null, { status: 404 })
  const size = statSync(ISO_PATH).size
  return new Response(null, {
    status: 200,
    headers: {
      'Content-Length': String(size),
      'Accept-Ranges': 'bytes',
      'Content-Disposition': `attachment; filename="${ISO_NAME}"`,
    },
  })
}
