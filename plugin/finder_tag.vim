" finder_tag.vim
" Apply, replace, or remove macOS Finder tags on the current file,
" with optional StatusLine colour tinting and tag name display.
"
" Commands:
"   :Tag       - prompt for name and/or colour interactively
"   :TagRemove - remove all Finder tags from the current file
"   :TagLast   - re-apply the last used tag (persists for the session)
"
" Public functions for vimrc:
"   call FinderTag('Read', 2)    name + colour index
"   %{FinderTagStatusText()}     include in your statusline for tag name
"
" Options (set in vimrc, all optional):
"
"   let g:finder_tag_statusline_colour = 1
"       Tints StatusLine background to match the tag colour.
"       Set to 0 to disable.
"
"   let g:finder_tag_statusline_text = 1
"       Makes FinderTagStatusText() return the tag name.
"       Add %{FinderTagStatusText()} wherever you want it in your statusline.
"       Set to 0 to disable (function returns empty string).
"
"   let g:finder_tag_set_statusline = 0
"       Set to 1 if you do not have a custom statusline and want the plugin
"       to set one that includes the tag name automatically.
"       If you have your own statusline, leave this 0 and add
"       %{FinderTagStatusText()} to it yourself instead.
"
"   let g:finder_tag_auto_refresh = 1
"       Re-reads the tag from disk on BufEnter and updates the statusline.
"       Set to 0 if you notice any slowness (unlikely but possible on network fs).
"
" TagRead is intentionally not defined here. Add to vimrc:
"   command! TagRead call FinderTag('Read', 2)
"
" Colour index reference:
"   0 none  1 grey  2 green  3 purple  4 blue  5 yellow  6 orange  7 red

if exists('g:loaded_finder_tag') || &compatible
  finish
endif
let g:loaded_finder_tag = 1

" Internal state
let s:colour_map = {
  \ 'none':   0,
  \ 'grey':   1,
  \ 'gray':   1,
  \ 'green':  2,
  \ 'purple': 3,
  \ 'blue':   4,
  \ 'yellow': 5,
  \ 'orange': 6,
  \ 'red':    7
  \ }

let s:colour_names = ['none', 'grey', 'green', 'purple', 'blue', 'yellow', 'orange', 'red']

" StatusLine highlight strings per colour index (gui + cterm).
" Colours are tuned to macOS Finder tag colours.
let s:tag_hl = {
  \ 1: 'guibg=#8E8E93 guifg=#FFFFFF ctermbg=244 ctermfg=15',
  \ 2: 'guibg=#30D158 guifg=#000000 ctermbg=35  ctermfg=0',
  \ 3: 'guibg=#BF5AF2 guifg=#FFFFFF ctermbg=129 ctermfg=15',
  \ 4: 'guibg=#0A84FF guifg=#FFFFFF ctermbg=27  ctermfg=15',
  \ 5: 'guibg=#FFD60A guifg=#000000 ctermbg=226 ctermfg=0',
  \ 6: 'guibg=#FF9F0A guifg=#000000 ctermbg=208 ctermfg=0',
  \ 7: 'guibg=#FF453A guifg=#FFFFFF ctermbg=196 ctermfg=15',
  \ }

let s:last_name         = ''
let s:last_colour       = -1
let s:current_name      = ''
let s:current_colour    = -1
let s:saved_sl_hl       = ''   " saved StatusLine highlight string
let s:sl_tinted         = 0    " whether we currently own the StatusLine colour

" StatusLine highlight save / restore
function! s:SaveStatusLineHL()
  " only save if we're not already tinting (so we always hold the original)
  if s:sl_tinted
    return
  endif
  let l:out = ''
  redir => l:out
  silent highlight StatusLine
  redir END
  " output: "StatusLine     xxx guibg=... ctermfg=..."
  " or:     "StatusLine     xxx cleared"
  " or:     "StatusLine     xxx links to ..."
  let s:saved_sl_hl = substitute(trim(l:out), '^StatusLine\s\+xxx\s*', '', '')
endfunction

function! s:ApplyStatusLineColour(colour_index)
  if !get(g:, 'finder_tag_statusline_colour', 1)
    return
  endif
  if a:colour_index < 1 || a:colour_index > 7
    call s:RestoreStatusLineHL()
    return
  endif
  call s:SaveStatusLineHL()
  execute 'highlight StatusLine ' . s:tag_hl[a:colour_index]
  let s:sl_tinted = 1
endfunction

function! s:RestoreStatusLineHL()
  if !s:sl_tinted
    return
  endif
  if empty(s:saved_sl_hl) || s:saved_sl_hl =~# 'cleared'
    highlight clear StatusLine
  elseif s:saved_sl_hl =~# '^links to'
    let l:target = matchstr(s:saved_sl_hl, '^links to \zs\S\+')
    execute 'highlight! link StatusLine ' . l:target
  else
    execute 'highlight StatusLine ' . s:saved_sl_hl
  endif
  let s:sl_tinted = 0
endfunction

" State update (called after any tag read or write)
function! s:UpdateState(name, colour_index)
  let s:current_name   = a:name
  let s:current_colour = a:colour_index
  call s:ApplyStatusLineColour(a:colour_index)
  if get(g:, 'finder_tag_set_statusline', 0)
    call s:SetManagedStatusLine()
  endif
  redrawstatus!
endfunction

function! s:ClearState()
  let s:current_name   = ''
  let s:current_colour = -1
  call s:RestoreStatusLineHL()
  if get(g:, 'finder_tag_set_statusline', 0)
    call s:SetManagedStatusLine()
  endif
  redrawstatus!
endfunction

" Managed statusline (only used when g:finder_tag_set_statusline = 1)
function! s:SetManagedStatusLine()
  set statusline=%<%f\ %m%r%h%w%=%{FinderTagStatusText()}\ %l:%c\ %P
endfunction

" Public: statusline text function
" Add %{FinderTagStatusText()} to your statusline to show the tag name.
function! FinderTagStatusText()
  if !get(g:, 'finder_tag_statusline_text', 1)
    return ''
  endif
  if empty(s:current_name)
    return ''
  endif
  return '[' . s:current_name . ']'
endfunction

" Private helpers
function! s:BuildTagString(name, colour_index)
  if empty(a:name) && a:colour_index >= 1
    return s:colour_names[a:colour_index] . "\n" . a:colour_index
  endif
  if !empty(a:name) && a:colour_index >= 1
    return a:name . "\n" . a:colour_index
  endif
  return a:name
endfunction

" Returns -1 (blank), -2 (invalid), or 0-7.
function! s:ParseColour(input)
  let l:lower = tolower(trim(a:input))
  if empty(l:lower)
    return -1
  endif
  if has_key(s:colour_map, l:lower)
    return s:colour_map[l:lower]
  endif
  if l:lower =~# '^\d$'
    let l:n = str2nr(l:lower)
    if l:n >= 0 && l:n <= 7
      return l:n
    endif
  endif
  return -2
endfunction

" Reads the tag from disk. Returns a dict:
"   {'name': str, 'colour': int, 'display': str}
" or {} if no tag.
function! s:ReadTagFromFile(file)
  call system('xattr -p com.apple.metadata:_kMDItemUserTags ' . shellescape(a:file) . ' >/dev/null 2>&1')
  if v:shell_error
    return {}
  endif
  let l:raw = system('mdls -raw -name _kMDItemUserTags ' . shellescape(a:file) . ' 2>/dev/null')
  let l:raw = trim(l:raw)
  if l:raw ==# '(null)' || empty(l:raw)
    return {}
  endif
  let l:match = matchstr(l:raw, '"[^"]*"')
  if empty(l:match)
    return {'name': '', 'colour': 0, 'display': 'unknown'}
  endif
  let l:inner = l:match[1 : len(l:match) - 2]
  let l:inner = substitute(l:inner, '\\n', "\n", 'g')
  let l:parts = split(l:inner, "\n")
  let l:tname = get(l:parts, 0, '')
  let l:cidx  = str2nr(get(l:parts, 1, '0'))
  let l:cidx  = (l:cidx >= 0 && l:cidx <= 7) ? l:cidx : 0
  let l:display = l:cidx >= 1
    \ ? "'" . l:tname . "' (" . s:colour_names[l:cidx] . ")"
    \ : "'" . l:tname . "'"
  return {'name': l:tname, 'colour': l:cidx, 'display': l:display}
endfunction

" Core write
" a:check = 1: prompt before overwriting existing tag
" a:check = 0: write unconditionally (PromptTag already informed user)
function! s:WriteTag(name, colour_index, check)
  if !has('macunix')
    echom "finder_tag: only works on macOS"
    return
  endif
  let l:file = expand('%:p')
  if empty(l:file)
    echom "finder_tag: no file in current buffer"
    return
  endif
  let l:tag = s:BuildTagString(a:name, a:colour_index)
  if empty(l:tag)
    echom "finder_tag: nothing to apply (no name and no colour)"
    return
  endif
  if a:check
    let l:existing = s:ReadTagFromFile(l:file)
    if !empty(l:existing)
      let l:choice = confirm(
        \ "'" . fnamemodify(l:file, ':t') . "' already has tag " . l:existing.display . ". Overwrite?",
        \ "&Yes\n&No", 2)
      if l:choice != 1
        echom "finder_tag: cancelled"
        return
      endif
    endif
  endif
  let l:plist = '<plist version="1.0"><array><string>' . l:tag . '</string></array></plist>'
  call system('xattr -w com.apple.metadata:_kMDItemUserTags ' . shellescape(l:plist) . ' ' . shellescape(l:file))
  if v:shell_error
    echom "finder_tag: xattr failed (exit " . v:shell_error . ")"
  else
    let s:last_name   = a:name
    let s:last_colour = a:colour_index
    call s:UpdateState(a:name, a:colour_index)
    echom "finder_tag: tagged '" . fnamemodify(l:file, ':t') . "'"
  endif
endfunction

" Remove

function! s:RemoveTag()
  if !has('macunix')
    echom "finder_tag: only works on macOS"
    return
  endif
  let l:file = expand('%:p')
  if empty(l:file)
    echom "finder_tag: no file in current buffer"
    return
  endif
  let l:existing = s:ReadTagFromFile(l:file)
  if empty(l:existing)
    echom "finder_tag: no tag on '" . fnamemodify(l:file, ':t') . "'"
    return
  endif
  let l:choice = confirm(
    \ "Remove tag " . l:existing.display . " from '" . fnamemodify(l:file, ':t') . "'?",
    \ "&Yes\n&No", 2)
  if l:choice != 1
    echom "finder_tag: cancelled"
    return
  endif
  call system('xattr -d com.apple.metadata:_kMDItemUserTags ' . shellescape(l:file) . ' 2>/dev/null')
  if v:shell_error
    echom "finder_tag: removal failed (exit " . v:shell_error . ")"
  else
    call s:ClearState()
    echom "finder_tag: tag removed from '" . fnamemodify(l:file, ':t') . "'"
  endif
endfunction

" Last tag
function! s:TagLast()
  if empty(s:last_name) && s:last_colour == -1
    echom "finder_tag: no tag applied yet this session"
    return
  endif
  call s:WriteTag(s:last_name, s:last_colour, 1)
endfunction

" Interactive prompt
function! s:PromptTag()
  if !has('macunix')
    echom "finder_tag: only works on macOS"
    return
  endif
  let l:file = expand('%:p')
  if empty(l:file)
    echom "finder_tag: no file in current buffer"
    return
  endif
  let l:existing = s:ReadTagFromFile(l:file)
  if !empty(l:existing)
    echo "Current tag on '" . fnamemodify(l:file, ':t') . "': " . l:existing.display
  endif
  let l:name = trim(input("Tag name (blank to skip): "))
  redraw
  let l:colour_raw = trim(input("Colour - none grey green purple blue yellow orange red, or 0-7 (blank to skip): "))
  redraw
  let l:colour_index = s:ParseColour(l:colour_raw)
  if l:colour_index == -2
    echom "finder_tag: unrecognised colour '" . l:colour_raw . "'"
    return
  endif
  if empty(l:name) && l:colour_index == -1
    echom "finder_tag: nothing to apply"
    return
  endif
  " check=0: user already saw the existing tag above, no second confirm needed
  call s:WriteTag(l:name, l:colour_index, 0)
endfunction

" Auto-refresh on buffer switch
function! s:RefreshFromFile()
  if !get(g:, 'finder_tag_auto_refresh', 1)
    return
  endif
  let l:file = expand('%:p')
  if empty(l:file) || !filereadable(l:file)
    call s:ClearState()
    return
  endif
  let l:tag = s:ReadTagFromFile(l:file)
  if empty(l:tag) || empty(l:tag.name)
    call s:ClearState()
  else
    call s:UpdateState(l:tag.name, l:tag.colour)
  endif
endfunction

augroup FinderTagRefresh
  autocmd!
  autocmd BufEnter    * call s:RefreshFromFile()
augroup END

" Public API
" Callable from vimrc (s: functions are script-local so this wrapper is needed).
" Example:
"   command! TagRead call FinderTag('Read', 2)
function! FinderTag(name, colour_index)
  call s:WriteTag(a:name, a:colour_index, 1)
endfunction

" Initialise managed statusline if opted in
if get(g:, 'finder_tag_set_statusline', 0)
  call s:SetManagedStatusLine()
endif

" Commands
command! Tag       call s:PromptTag()
command! TagRemove call s:RemoveTag()
command! TagLast   call s:TagLast()
