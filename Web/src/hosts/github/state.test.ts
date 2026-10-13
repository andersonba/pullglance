import { ViewedOverlay } from './state'

describe('ViewedOverlay', () => {
  it('guarda por contexto e limpa os demais', () => {
    const o = new ViewedOverlay()
    o.set('c1', 'a', true); o.setMany('c2', [['b', false]])
    expect(o.get('c1', 'a')).toBe(true); expect(o.get('c1', 'b')).toBeUndefined(); expect(o.get('c2', 'b')).toBe(false)
    o.clearExcept('c2')
    expect(o.get('c1', 'a')).toBeUndefined(); expect(o.get('c2', 'b')).toBe(false)
  })
})
