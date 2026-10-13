import { fileReviewRequest, filesPageRequest } from './endpoints'

describe('endpoints', () => {
  it('POST para marcar com headers verificados e path intacto', () => {
    const r = fileReviewRequest('/acme/web/pull/42', 'src/my dir/[id]/ação.test.ts', true)
    expect(r.url).toBe('/acme/web/pull/42/file_review')
    expect(r.init.method).toBe('POST')
    expect(r.init.credentials).toBe('same-origin')
    expect(new Headers(r.init.headers).get('GitHub-Verified-Fetch')).toBe('true')
    expect(new Headers(r.init.headers).get('X-Requested-With')).toBe('XMLHttpRequest')
    expect(new Headers(r.init.headers).get('Content-Type')).toBe('application/json')
    expect(JSON.parse(r.init.body as string)).toEqual({ path: 'src/my dir/[id]/ação.test.ts', viewed: 'viewed' })
  })

  it('DELETE para desmarcar', () => {
    const r = fileReviewRequest('/acme/web/pull/42', 'a.ts', false)
    expect(r.init.method).toBe('DELETE')
    expect(JSON.parse(r.init.body as string)).toEqual({ path: 'a.ts', _method: 'delete' })
  })

  it('GET da página de arquivos pede HTML', () => {
    const r = filesPageRequest('/acme/web/pull/42')
    expect(r.url).toBe('/acme/web/pull/42/files')
    expect(new Headers(r.init.headers).get('Accept')).toContain('text/html')
  })
})
