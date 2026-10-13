export class ViewedOverlay {
  private byContext = new Map<string, Map<string, boolean>>()
  get(contextKey: string, id: string) { return this.byContext.get(contextKey)?.get(id) }
  set(contextKey: string, id: string, viewed: boolean) {
    if (!this.byContext.has(contextKey)) this.byContext.set(contextKey, new Map())
    this.byContext.get(contextKey)!.set(id, viewed)
  }
  setMany(contextKey: string, entries: Iterable<[string, boolean]>) { for (const [id, v] of entries) this.set(contextKey, id, v) }
  clearExcept(contextKey: string) { for (const k of [...this.byContext.keys()]) if (k !== contextKey) this.byContext.delete(k) }
}
