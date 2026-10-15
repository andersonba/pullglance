export const EMBEDDED_SCRIPT_OPEN = '<script type="application/json" data-target="react-app.embeddedData">'

export const TOOLBAR = `
<div class="use-sticky-header-module__stickyHeader__sf0hv PullRequestFilesToolbar-module__toolbar__ztHN6 prc-Stack-Stack-UQ9k6">
  <div class="d-flex PullRequestFilesToolbar-module__file-controls__Tgb8F">
    <div class="d-flex flex-row flex-items-center PullRequestFilesToolbar-module__hide-viewed-progress-on-small__DLtKy">
      <svg aria-hidden="true"></svg>
      <span aria-hidden="true" class="ml-1 ViewedFileProgress-module__ProgressContainer___3P2j"><span class="ViewedFileProgress-module__FilesCountText__NwSKr">{{viewedCount}}</span> / <span class="ViewedFileProgress-module__FilesCountText__NwSKr">{{total}}</span> <span class="ViewedFileProgress-module__ViewedText__s4QAn">viewed</span></span>
      <span class="sr-only">{{viewedCount}} of {{total}} files viewed</span>
    </div>
  </div>
</div>`

/** Botão Viewed com atributos ARIA (variante padrão observada). */
export const VIEWED_BUTTON_ARIA = `<button data-component="Button" type="button" aria-pressed="{{pressed}}" aria-label="{{label}}" class="prc-Button-ButtonBase-9n-Xk {{viewedClass}}MarkAsViewedButton-module__iconOnly__kEP4e" data-loading="false" data-size="small" data-variant="default"><span data-component="buttonContent" data-align="center" class="prc-Button-ButtonContent-Iohp5"><span data-component="leadingVisual" class="prc-Button-Visual-YNt2F"><svg aria-hidden="true"></svg></span><span data-component="text" class="prc-Button-Label-FWkx3"><span class="responsive-module__hide-on-mobile__v3LUR">Viewed</span></span></span></button>`

/** Variante hipotética sem ARIA: só a classe com hash indica estado. */
export const VIEWED_BUTTON_CSS_ONLY = `<button data-component="Button" type="button" class="prc-Button-ButtonBase-9n-Xk {{viewedClass}}MarkAsViewedButton-module__iconOnly__kEP4e" data-loading="false" data-size="small" data-variant="default"><span data-component="text" class="prc-Button-Label-FWkx3"><span class="responsive-module__hide-on-mobile__v3LUR">Viewed</span></span></button>`

export const FILE_HEADER = `
<div class="Diff-module__diffHeaderWrapper__UgUyv" data-diff-header-wrapper="true" style="--header-sticky-offset:0px">
  <div class="DiffFileHeader-module__diff-file-header__UuNN4 diff-file-header{{collapsedClass}}">
    <div class="d-flex flex-shrink-0"><button data-component="IconButton" type="button" class="prc-Button-ButtonBase-9n-Xk prc-Button-IconButton-fyge7" data-size="small" data-variant="invisible" aria-labelledby="_R_x_"><svg aria-hidden="true"></svg></button></div>
    <div class="d-flex px-1 flex-items-center overflow-hidden DiffFileHeader-module__file-path-section__ZcmB1">
      <h3 id="heading-_R_x_" class="DiffFileHeader-module__file-name__VVXpg DiffFileHeader-module__file-name-truncate__NBVtv"><a class="Link--primary prc-Link-Link-9ZwDx" data-component="Link" href="#diff-{{digest}}"><code>&lrm;<!-- -->{{path}}<!-- -->&lrm;</code></a></h3>
      <button data-component="IconButton" type="button" class="prc-Button-ButtonBase-9n-Xk ml-2 flex-shrink-0 prc-Button-IconButton-fyge7" data-size="small" data-variant="invisible" aria-labelledby="_R_x_"><svg aria-hidden="true"></svg></button>
    </div>
    <div class="d-flex flex-row flex-justify-end flex-items-center gap-2 flex-1">
      <div class="d-flex flex-items-center gap-2">
        {{viewedButton}}
        <button data-component="IconButton" type="button" aria-haspopup="true" aria-expanded="false" class="prc-Button-ButtonBase-9n-Xk prc-Button-IconButton-fyge7" data-size="small" data-variant="invisible" aria-labelledby="_R_x_"><svg aria-hidden="true"></svg></button>
      </div>
    </div>
  </div>
</div>
{{body}}`

export const DIFF_BODY = `<div class="Diff-module__diffContent__x"><table><tbody><tr><td>+ linha</td></tr></tbody></table></div>`

/** Assumed shape of the large-diff placeholder: a message and a "Load Diff" button, no table. */
export const LARGE_DIFF_BODY = `<div class="Diff-module__diffContent__x"><div class="text-center p-3"><button type="button" class="prc-Button-ButtonBase-9n-Xk" data-variant="invisible">Load Diff</button><p class="color-fg-muted">Large diffs are not rendered by default.</p></div></div>`
