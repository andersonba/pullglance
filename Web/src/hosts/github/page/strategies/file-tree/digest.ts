/** The digest of a `#diff-<digest>` link inside a tree item, or null. */
export function digestOfLink(item: Element): string | null {
  const href = item.querySelector('a[href^="#diff-"]')?.getAttribute('href')
  return href ? href.slice('#diff-'.length) : null
}
