import { install } from './entry'
import { mountComparePage, digestOf } from './test-fixtures'
import { storage } from '#imports'

describe('review script API', () => {
  beforeEach(() => { storage._resetForTests(); document.body.innerHTML = '' })

  it('reports the context and counts files on a compare page', async () => {
    mountComparePage({ files: [{ path: 'a.test.ts' }, { path: 'b.ts' }] })
    const events: Array<{ name: string; payload: unknown }> = []
    const api = install({ post: (e) => events.push(e) })
    expect(api.context().kind).toBe('compare')
    const c = await api.counts(null)
    expect(c.total).toBe(2)
    expect(c.matching).toBe(1)                  // a.test.ts by the js-unit preset
    expect(c.perRule['js-unit']).toBe(1)
    expect(events.some((e) => e.name === 'context')).toBe(true)
  })

  it('marks by rule ids, then undoes', async () => {
    mountComparePage({ files: [{ path: 'a.test.ts' }, { path: 'b.ts' }] })
    const api = install({ post: () => {} })
    const r = await api.mark(['js-unit'])
    expect(r.marked).toBe(1)
    expect(r.canUndo).toBe(true)
    expect(document.getElementById(`diff-${digestOf('a.test.ts')}`)!.classList.contains('open')).toBe(false)
    const u = await api.undo()
    expect(u.marked).toBe(1)
    await expect(api.undo()).rejects.toThrow('nothing to undo')
  })

  it('scrolls to the next unviewed file and reports when there is none', async () => {
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts' }] })
    const api = install({ post: () => {} })
    const calls: string[] = []
    // happy-dom has no layout: place the two files below the fold by hand.
    const tops: Record<string, number> = { 'a.ts': 200, 'b.ts': 900 }
    for (const id of ['a.ts', 'b.ts']) {
      const node = document.getElementById(`diff-${digestOf(id)}`) as any
      node.scrollIntoView = () => calls.push(id)
      node.getBoundingClientRect = () => ({ top: tops[id] }) as DOMRect
    }
    expect(await api.scrollToUnviewed('next')).toBe(true)
    expect(calls).toEqual(['a.ts'])
    expect(await api.scrollToUnviewed('previous')).toBe(false)   // nothing above the viewport
    tops['a.ts'] = -900; tops['b.ts'] = -200                       // both scrolled past
    expect(await api.scrollToUnviewed('next')).toBe(false)
    expect(await api.scrollToUnviewed('previous')).toBe(true)
    expect(calls).toEqual(['a.ts', 'b.ts'])
  })

  it('posts the listing on install and again when the file list changes', async () => {
    mountComparePage({ files: [{ path: 'a.ts' }, { path: 'b.ts' }] })
    const listings: unknown[] = []
    const api = install({ post: (e) => { if (e.name === 'listing') listings.push(e.payload) } })
    await vi.waitFor(() => expect(listings).toEqual([{ total: 2, viewed: 0, partial: false }]))
    await api.mark(null)                         // nothing matches by default: no change, no new event
    document.querySelector<HTMLButtonElement>(`#diff-${digestOf('a.ts')} button[data-ghra-viewed]`)!.click()   // the user marks a file
    await vi.waitFor(() => expect(listings.at(-1)).toEqual({ total: 2, viewed: 1, partial: false }))
    expect(listings).toHaveLength(2)
  })
})
