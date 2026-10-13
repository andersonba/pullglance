import type { Strategy, ToolbarSlotSource } from '../../concepts'

/**
 * Barra do compare clássico: o bloco flutuante à direita do `#toc` (Split/Unified). Ele é inline-block com um
 * <form> em bloco dentro, então não dá para entrar nele sem quebrar linha. Entramos como irmão logo depois,
 * também flutuando à direita: floats à direita empilham da direita para a esquerda, então ficamos à esquerda dele.
 */
const SLOT = '#toc .float-right'

export const toolbarSlotClassicToc: Strategy<ToolbarSlotSource> = {
  id: 'toolbar-slot/classic-toc',
  priority: 20,
  probe: (doc) => doc.querySelector(SLOT) !== null,
  create: (doc) => ({ find: () => doc.querySelector(SLOT), placement: 'after', hostFlag: 'float-right' }),
}
