export interface PreparedRequest {
  url: string
  init: RequestInit
}

const VERIFIED_HEADERS = {
  'GitHub-Verified-Fetch': 'true',
  'X-Requested-With': 'XMLHttpRequest',
  Accept: 'application/json',
  'Content-Type': 'application/json',
}

export function fileReviewRequest(basePath: string, path: string, viewed: boolean): PreparedRequest {
  return {
    url: `${basePath}/file_review`,
    init: {
      method: viewed ? 'POST' : 'DELETE',
      credentials: 'same-origin',
      headers: VERIFIED_HEADERS,
      body: JSON.stringify(viewed ? { path, viewed: 'viewed' } : { path, _method: 'delete' }),
    },
  }
}

export function filesPageRequest(basePath: string): PreparedRequest {
  return {
    url: `${basePath}/files`,
    init: { method: 'GET', credentials: 'same-origin', headers: { Accept: 'text/html', 'X-Requested-With': 'XMLHttpRequest' } },
  }
}
