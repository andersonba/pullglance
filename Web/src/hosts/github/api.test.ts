import { FileReviewError, fetchServerRoute, fetchServerViewedState, postFileReview } from './api'
import { AbortedInFlight } from '@/core/host'
import { buildFilesPageHtml, digestOf } from '@@/tests/fixtures/github/build'

const okJson = () => new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } })

describe('postFileReview', () => {
  it('envia a requisição preparada e resolve em 2xx', async () => {
    const calls: Array<[string, RequestInit | undefined]> = []
    await postFileReview('/acme/web/pull/42', 'src/[id]/a b.ts', true, async (u, i) => { calls.push([u, i]); return okJson() })
    expect(calls[0]![0]).toBe('/acme/web/pull/42/file_review')
    expect(JSON.parse(calls[0]![1]!.body as string).path).toBe('src/[id]/a b.ts')
  })

  it('lança FileReviewError com status em não-2xx', async () => {
    await expect(postFileReview('/p', 'a', true, async () => new Response('{"error":"nope"}', { status: 422 }))).rejects.toMatchObject({ status: 422, message: expect.stringContaining('nope') })
    await expect(postFileReview('/p', 'a', true, async () => new Response('x', { status: 500 }))).rejects.toBeInstanceOf(FileReviewError)
  })

  it('abort em voo vira AbortedInFlight', async () => {
    const ac = new AbortController()
    const p = postFileReview('/p', 'a', true, (_u, init) => new Promise((_, rej) => init?.signal?.addEventListener('abort', () => rej(new DOMException('x', 'AbortError')))), ac.signal)
    ac.abort()
    await expect(p).rejects.toBeInstanceOf(AbortedInFlight)
  })
})

describe('fetchServerRoute', () => {
  it('devolve a rota completa da página buscada (basePath, headOid, resumos)', async () => {
    const html = buildFilesPageHtml({ files: [{ path: 'a.ts', viewed: true }], basePath: '/acme/web/pull/7', headOid: 'h7' })
    const route = await fetchServerRoute('/acme/web/pull/7', async () => new Response(html, { status: 200 }))
    expect(route.basePath).toBe('/acme/web/pull/7'); expect(route.headOid).toBe('h7')
    expect(route.summaries.map((s) => [s.path, s.markedAsViewed])).toEqual([['a.ts', true]])
  })
})

describe('fetchServerViewedState', () => {
  it('baixa a página de arquivos e lê markedAsViewed por digest', async () => {
    const html = buildFilesPageHtml({ files: [{ path: 'a.ts', viewed: true }, { path: 'b.ts' }] })
    const state = await fetchServerViewedState('/acme/web/pull/42', async () => new Response(html, { status: 200, headers: { 'Content-Type': 'text/html' } }))
    expect(state.get(digestOf('a.ts'))).toBe(true); expect(state.get(digestOf('b.ts'))).toBe(false)
  })

  it('lança se a resposta não é 2xx ou não tem JSON embutido', async () => {
    await expect(fetchServerViewedState('/p', async () => new Response('', { status: 500 }))).rejects.toThrow()
    await expect(fetchServerViewedState('/p', async () => new Response('<html></html>', { status: 200 }))).rejects.toThrow()
  })
})
