" eda_utils.vim : Utils for EDA tools

let s:save_cpo = &cpoptions
set cpoptions&vim
"-----------------------------------------------------------------------------

"-----------------------------------------------------------------------------
" Open the terminal at the bottom of the window.
function! eda_utils#MakeTerminal(bang)
    split
    wincmd j
    resize 10
    if has('nvim')
        terminal g:eda_utils_shell
    else
        execute ":terminal ++curwin ++close " . g:eda_utils_shell
    endif
    if a:bang == "!"
        wincmd k
        stopinsert
    endif
endfunction

"-----------------------------------------------------------------------------
" Close all terminals.
function! eda_utils#DeleteTerminal(bang)
    let list = filter(range(1, bufnr('$')), 'getbufvar(v:val, "&buftype") == "terminal"')
    if len(list) != 0
        :execute "bdelete" . a:bang . " " . join(list)
    endif
endfunction

"-----------------------------------------------------------------------------
" Split current window to view a Table.
" The top window shows the table header. 
function! eda_utils#ViewTable()
    :split
    :resize 4 
    :exec "normal zt" 
    :set scrollbind
    :set scrollopt=hor,jump
    :wincmd j
    :set scrollbind
endfunction

"-----------------------------------------------------------------------------
" Execute a command.
"   mode = bsub or shell or bash
function! eda_utils#Run(mode, queue, host, tool, ...)
    if a:mode == "bsub" && a:queue != "" && a:host != "" && a:tool != ""
        let cmd = "bsub -q " . a:queue . " -R 'rusage[mem=" . 
        \   get(g:,"eda_utils_bsub_mem","4G") .
        \   ":" . a:tool . "=1] select[type==" . a:host . "]' -F" . 
        \   get(g:,"eda_utils_bsub_flimit","10G") . " -Is"
    elseif a:mode == "srun" && a:queue != "" && a:host != ""
        let cmd = "srun -p " . a:queue . " --mem " . 
        \   get(g:,"eda_utils_bsub_mem","4G") .
        \   " -C \"" . a:host . "\""

        if a:tool != ""
            let cmd = cmd . " -L " . a:tool
        endif
    else
        let cmd = ""
    endif

    let arg = copy(a:000)
    let cmd = cmd . " " . join(map(arg, 'expand(v:val)'))
    let cmd = "echo " . shellescape(cmd) . "; echo '';" . cmd

    let term_on = (!exists('g:eda_utils_no_terminal') || (g:eda_utils_no_terminal == 0))

    if has('terminal') && term_on
        let cmd = ":term ++shell ++curwin " . cmd 
    elseif has('nvim') && term_on
        let cmd = ":term " . cmd 
    else
        let cmd = "set bt=nofile | r!" . cmd 
        let term_on = 0
    endif

    if a:mode == "bash"
        let shell = &shell
        :execute "setlocal shell=bash"
    endif

    let winid = -1
    if get(g:, "eda_utils_shell_override") != "1"
        for winnr in range(1, winnr('$'))
            let bufnr = winbufnr(winnr)
            let done = getbufvar(bufnr, "eda_utils_shell_done")
            if done == "1"
                if term_on
                    let winid = bufwinid(bufnr)
                else
                    let winid = winnr
                endif
                break
            end
        endfor
    endif


    if winid == -1
        :new
        :let b:eda_utils_shell_done = 0
        :execute cmd
        :let b:eda_utils_shell_done = 1
        :wincmd j
    elseif !term_on
        let this_winnr = winnr()
        :execute winid . "windo " . ":normal! GVggd"
        :execute winid . "windo " . ":let b:eda_utils_shell_done = 0"
        :execute winid . "windo " . cmd
        :execute winid . "windo " . ":let b:eda_utils_shell_done = 1"
        :execute this_winnr."wincmd w"
    else
        :call win_execute(winid, "let b:eda_utils_shell_done = 0")
        :call win_execute(winid, cmd)
        :call win_execute(winid, "let b:eda_utils_shell_done = 1")
    endif

    if a:mode == "bash"
        :execute "setlocal shell=" . shell
    endif

    :stopinsert
endfunction

"-----------------------------------------------------------------------------
" Generate Verilog outline.

" Return list of headers and their levels.
function! s:GetHeaderList(get_marker)
    let l:bufnr = bufnr('%')
    let l:header_list = []
    let l:level = 0

    let l:headersRegexp = get(g:, "eda_utils_headersRegexp", '\v^\s*(module|class|task|function|package)>')
    let l:footerRegexp = get(g:, "eda_utils_footerRegexp", '\v^\s*(endmodule|endclass|endtask|endfunction|endpackage)>')
    let l:markerRegexp = get(g:, "eda_utils_markerRegexp", '\v^\s*(//+|\#+)\s*(MARK|TODO|FIXME|NOTE):')
    for i in range(1, line('$'))
        let l:line = getline(i)
        " match line against header regex
        if join(getline(i, i + 1), "\n") =~ l:headersRegexp
            " append line to list
            let l:level = l:level + 1
            let l:item = {'level': l:level, 'text': l:line, 'lnum': i, 'bufnr': bufnr}
            let l:header_list = l:header_list + [l:item]
        elseif l:level > 0 && join(getline(i, i + 1), "\n") =~ l:footerRegexp
            let l:level = l:level - 1
        elseif a:get_marker && join(getline(i, i + 1), "\n") =~ l:markerRegexp
            let l:ans = ' ' . substitute(l:line, '\v^\s*(//+|\#+)\s*', '', '')
            let l:item = {'level': l:level, 'text': l:ans, 'lnum': i, 'bufnr': bufnr}
            let l:header_list = l:header_list + [l:item]
        endif
    endfor
    return l:header_list
endfunction

" Generate outline by ctags.
function! s:GetHeaderListCtags(get_marker)
    let l:bufnr = bufnr('%')
    let l:header_list = []
    let l:filetype = getbufvar(bufnr('%'), '&filetype')

    if index(['c', 'cpp', 'sfc'], l:filetype) >= 0
        " function
        let l:opt = "--c-types=f"
    elseif index(['verilog', 'systemverilog'], l:filetype) >= 0
        " module, instance
        let l:opt = "--verilog-kinds=mi"
    else
        let l:opt = ""
    endif

    let l:path = bufname('%')
    let l:result = system("ctags -x --sort=no " . l:opt . " " . l:path . " | awk '{$2=\"\"; $4=\"\"; print}'")
    let l:tags_list = []
    for l:line in split(l:result, "\n")
        let l:a = split(l:line)
        let l:tags_list = l:tags_list + [{'symbol':l:a[0], 'lnum':l:a[1], 'text':join(l:a[2:-1], " ")}]
    endfor

    if len(l:tags_list) == 0
        let l:tags_lnum = -1
    else
        let l:tags = l:tags_list[0]
        let l:tags_lnum = l:tags.lnum
        let l:tags_idx = 0
    endif

    let l:markerRegexp = get(g:, "eda_utils_markerRegexp", '\v^\s*(//+|\#+)\s*(MARK|TODO|FIXME|NOTE):')
    for i in range(1, line('$'))
        let l:line = getline(i)
        " match line against header regex
        if i == l:tags_lnum
            " append line to list
            let l:item = {'level': 0, 'text': l:tags.text, 'lnum': i, 'bufnr': bufnr}
            let l:header_list = l:header_list + [l:item]
            let l:tags_idx = l:tags_idx + 1
            if len(l:tags_list) == l:tags_idx
                let l:tags_lnum = -1
            else
                let l:tags = l:tags_list[l:tags_idx]
                let l:tags_lnum = l:tags.lnum
            end
        elseif a:get_marker && join(getline(i, i + 1), "\n") =~ l:markerRegexp
            let l:ans = ' ' . substitute(l:line, '\v^\s*(//+|\#+)\s*', '', '')
            let l:item = {'level': 0, 'text': l:ans, 'lnum': i, 'bufnr': bufnr}
            let l:header_list = l:header_list + [l:item]
        endif
    endfor
    return l:header_list
endfunction

" Genrate Table Of Contents. 
function! eda_utils#Toc(bang, ...)
    if a:0 > 0
        let l:window_type = a:1
    else
        let l:window_type = 'vertical'
    endif

    let l:cursor_line = line('.')
    let l:cursor_header = 0
    let l:filetype = getbufvar(bufnr('%'), '&filetype')
    if a:bang[0:4] == "ctags"
        let get_marker = len(a:bang) != 5
        let l:header_list = s:GetHeaderListCtags(get_marker)
    else
        let get_marker = len(a:bang) == 0
        let l:header_list = s:GetHeaderList(get_marker)
    endif
    let l:indented_header_list = []
    if len(l:header_list) == 0
        echom "Toc: No headers."
        return
    endif
    let l:header_max_len = 0
    let l:vim_verilog_toc_autofit = get(g:, "eda_utils_toc_autofit", 0)
    for h in l:header_list
        " set header number of the cursor position
        if l:cursor_header == 0
            let l:header_line = h.lnum
            if l:header_line == l:cursor_line
                let l:cursor_header = index(l:header_list, h) + 1
            elseif l:header_line > l:cursor_line
                let l:cursor_header = index(l:header_list, h)
            endif
        endif
        " indent header based on level
        let l:text = repeat(' ', h.level-1) . h.text
        "let l:text = h.text
        " keep track of the longest header size (heading level + title)
        let l:total_len = strdisplaywidth(l:text)
        if l:total_len > l:header_max_len
            let l:header_max_len = l:total_len
        endif
        " append indented line to list
        let l:item = {'lnum': h.lnum, 'text': l:text, 'valid': 1, 'bufnr': h.bufnr, 'col': 1}
        let l:indented_header_list = l:indented_header_list + [l:item]
    endfor
    call setloclist(0, l:indented_header_list)

    if l:window_type ==# 'horizontal'
        lopen
    elseif l:window_type ==# 'vertical'
        vertical lopen
        " auto-fit toc window when possible to shrink it
        if (&columns/4) > l:header_max_len && l:vim_verilog_toc_autofit == 1
            " header_max_len + 1 space for first header + 3 spaces for line numbers
            execute 'vertical resize ' . (l:header_max_len + 1 + 3)
        else
            execute 'vertical resize ' . (&columns/4)
        endif
    elseif l:window_type ==# 'tab'
        tab lopen
    else
        lopen
    endif
    setlocal modifiable
    for i in range(1, line('$'))
        " this is the location-list data for the current item
        let d = getloclist(0)[i-1]
        call setline(i, d.text)
    endfor
    setlocal nomodified
    setlocal nomodifiable
    execute 'normal! ' . l:cursor_header . 'G'
endfunction

"-----------------------------------------------------------------------------
" grep files in buffer.

" Retuns list of file names in buffer.
function! eda_utils#GetBuffers(...)
    let ans = ""
    for b in filter(range(1, bufnr('$')), 'buflisted(v:val) && getbufvar(v:val, "&filetype") != "qf"')
        let path = fnamemodify(bufname(b), ':p')
        if filereadable(path)
            let ans = ans . " " . path
        endif
    endfor
    return ans
endfunction

" Store RegisterBuffers() result to unnamed register. 
function! eda_utils#RegisterBuffers()
    let ans = eda_utils#GetBuffers()
    let @" = ans
endfunction

" grep files in buffer.
function! eda_utils#BufGrep(...)
    let ans = eda_utils#GetBuffers()
    execute "grep " . join(a:000) . " " . ans
endfunction

"-----------------------------------------------------------------------------
" Get test in the selected region.
function! eda_utils#GetSelectedText() range
    let [lnum1, col1] = getpos("'<")[1:2]
    let [lnum2, col2] = getpos("'>")[1:2]

    " Get all the lines represented by this range
    let lines = getline(lnum1, lnum2)         

    " The last line might need to be cut if the visual selection didn't end on the last column
    let lines[-1] = lines[-1][: col2 - (&selection == 'inclusive' ? 1 : 2)]
    " The first line might need to be trimmed if the visual selection didn't start on the first column
    let lines[0] = lines[0][col1 - 1:]

    " Get the desired text
    let selectedText = join(lines, "\n")         

    return selectedText
endfunction

"-----------------------------------------------------------------------------
" Convert selected text to markdown link format.
function! eda_utils#MarkDownLink() range
    normal! gvy
    let ans = getreg('"')
    let ans = "[" . ans . "](" . ans . ")"
    call setreg('"', ans)
    normal! gvp
endfunction

function! eda_utils#Surround(begin, end) range
    normal! gvy
    let ans = getreg('"')
    let ans = a:begin . ans . a:end
    call setreg('"', ans)
    normal! gvp
endfunction

"-----------------------------------------------------------------------------
"diff current file with git base
function! eda_utils#GitDiff(...)
	if a:0 == 0
		let rev = "HEAD"
	elseif a:0 == 1
		let rev = a:1
    else
		let rev = shellescape(join(a:000))
	endif
	:diffthis
	let cmd = ":vert new | set bt=nofile | r! git show " . rev . ":$(git ls-files --full-name " . @% . ") "
	:execute cmd
	:goto 1
	:1 d
	:diffthis
endfunction

"-----------------------------------------------------------------------------
"diff current file with svn base
function! eda_utils#SvnDiff(...)
	if a:0 == 0
		let rev = "-r HEAD"
	else
		let rev = "-r " . a:1
	endif
	:diffthis
	let cmd = ":vert new | set bt=nofile | r! svn cat " . rev . " " . @% 
	:execute cmd
	:goto 1
	:1 d
	:diffthis
endfunction

"diff same file with other branch
"from	current user
"to		diff user
function! eda_utils#SvnMerge(from,to)
	:diffthis
	let cmd = "vert new | set bt=nofile | r ! svn info " . @% . " | grep URL | ruby -W0 -ane 'print $F[1].sub(/" . a:from . "/,\"" . a:to . "\")'"
	:execute cmd
	:normal y$
	let cmd = "r!svn cat " . @"
	:execute cmd
	:diffthis
endfunction

"-----------------------------------------------------------------------------
" send current buffer to QuickFix

function! s:CheckAfter()
    cbuffer
    copen
endfunction

" clang or gcc
function! eda_utils#CheckClang()
    setlocal errorformat=%f\|%l\ col\ %c\|\ %m,%f:%l:%c:\ %trror:\ %m
    setlocal errorformat+=%f:%l:%c:\ %tarning:\ %m
    setlocal errorformat+=%f:%l:%c:\ %tote:\ %m
    call s:CheckAfter()
endfunction

" verilator 4
function! eda_utils#CheckVerilator()
    setlocal errorformat=%%Error%.%#:\ %f:%l:%c:\ %m
    setlocal errorformat+=%%%trror%.%#:\ %f:%l:\ %m
    setlocal errorformat+=%%%tarning%.%#:\ %f:%l:%c:\ %m
    setlocal errorformat+=%%%tarning%.%#:\ %f:%l:\ %m
    call s:CheckAfter()
endfunction

" not tested yet.
function! eda_utils#CheckQuesta()
    "setlocal errorformat=\*\*\ Error:\ (vlog-%.%#)\ %f(%l):\ %m
    setlocal errorformat=\*\*\ Error:\ (%s)\ %f(%l):\ %m
    setlocal errorformat+=\*\*\ Error\ (%s):\ %f(%l):\ %m
    setlocal errorformat+=\*\*\ Error:\ %f(%l):\ %m
    setlocal errorformat+=\*\*\ Warning:\ \[\%n\]\ %f(%l):\ %m
    call s:CheckAfter()
endfunction

" not tested yet.
function! eda_utils#CheckVcs()
    " Error level formats
    setlocal errorformat =%EError-\[%.%\\+\]\ %m
    setlocal errorformat+=%C%m\"%f\"\\,\ %l%.%#
    setlocal errorformat+=%C%f\\,\ %l
    setlocal errorformat+=%C%\\s%\\+%l:\ %m\\,\ column\ %c
    setlocal errorformat+=%C%\\s%\\+%l:\ %m
    setlocal errorformat+=%C%m\"%f\"\\,%.%#
    setlocal errorformat+=%Z%p^                      "Column pointer
    setlocal errorformat+=%C%m                       "Catch all rule
    setlocal errorformat+=%Z                         "Error message end on empty line
    " Warning level formats
    setlocal errorformat+=%WWarning-\[%.%\\+]\\$
    setlocal errorformat+=%-WWarning-[LCA_FEATURES_ENABLED]\ Usage\ warning    "Ignore LCA enabled warning
    setlocal errorformat+=%WWarning-\[%.%\\+\]\ %m
    " Lint level formats
    setlocal errorformat+=%I%tint-\[%.%\\+\]\ %m
    "
    call s:CheckAfter()
endfunction

" not tested yet.
function! eda_utils#CheckXrun()
    " Error level formats
    setlocal errorformat =%.%#:\ *%t\\,%.%#\ %#\(%f\\,%l\|%c\):\ %m
    setlocal errorformat+=%.%#:\ *%t\\,%.%#\ %#\(%f\\,%l\):\ %m
    " Multi-line error messages
    setlocal errorformat+=%A%.%#\ *%t\\,%.%#:\ %m,%ZFile:\ %f\\,\ line\ =\ %l\\,\ pos\ =\ %c
    " Ignore Warning level formats
    setlocal errorformat^=%-G%.%#\ *W\\,%.%#:\ %m
    "
    call s:CheckAfter()
endfunction

" not tested yet.
function! eda_utils#CheckSpyglass()
    " Error level formats
    "setlocal errorformat =%.%#\ SynthesisWarning\ *%f\ *%l\ *\[0-9]*\ *%m
    setlocal errorformat =%.%#SynthesisWarning\ *%f\ *%l\.*%m
    "let &errorformat = '.*SynthesisWarning *%f *%m.*'
    echo &errorformat
    call s:CheckAfter()
endfunction


"-----------------------------------------------------------------------------
" Search and highlight word.

" Search and highlight word.
" - whole_word=0, is_ranged=0
"   - Search /\<cword\>/
" - whole_word=1, is_ranged=0
"   - Search /cword/
" - whole_word=0, is_ranged=1
"   - Search selected text
function! eda_utils#HiLightSearch(whole_word, is_ranged) range
    if a:is_ranged == 0
        let cword = expand("<cword>")
    else
        normal! gvy
        let cword = getreg('"')
    endif
    if !exists("b:eda_utils_HiLightWords")
        let b:eda_utils_HiLightWords = []
    end
    if !exists("b:eda_utils_HiLightID")
        let b:eda_utils_HiLightID = -1
    end

    if len(cword) != 0
        if a:whole_word == 1
            let cword = '\<' . cword . '\>'
        endif
        let i = index(b:eda_utils_HiLightWords, cword)
        if i >= 0 
            :call remove(b:eda_utils_HiLightWords, i)
            for m in filter(getmatches(), "v:val['pattern'] == cword")
                :call matchdelete(m.id)
            endfor
        else
            let b:eda_utils_HiLightID = (b:eda_utils_HiLightID + 1) % len(g:eda_utils_HiLightGroups)
            let cg = g:eda_utils_HiLightGroups[b:eda_utils_HiLightID]
            let ans = getreg('/') . '\|' . cword
            :call add(b:eda_utils_HiLightWords, cword)
            if !exists("g:eda_utils_no_HighLight") 
                :call matchadd(cg, cword)
            endif
        endif
        :call setreg('/', join(b:eda_utils_HiLightWords, '\|'))
    endif
endfunction

" Clear highlight.
function! eda_utils#HiLightClear()
    let b:eda_utils_HiLightWords = []
    let b:eda_utils_HiLightID = 0
    let m = getmatches()
    if len(m) != 0
        let b:eda_utils_HiLightPrev = m
    endif
    :call clearmatches()
endfunction

" Toggle highlight (back to previous HiLightClear/Toggle).
function! eda_utils#HiLightToggle()
    let m = getmatches()
    if len(m) == 0
        if exists("b:eda_utils_HiLightPrev")
            :call setmatches(b:eda_utils_HiLightPrev)
            let b:eda_utils_HiLightWords = []
            for m in b:eda_utils_HiLightPrev
                :call add(b:eda_utils_HiLightWords, m.pattern)
            endfor
            :call setreg('/', join(b:eda_utils_HiLightWords, '\|'))
        endif
    else
        :call eda_utils#HiLightClear()
    endif
endfunction

function! eda_utils#HiLightDump()
    if !exists("b:eda_utils_HiLightWords")
        return
    end
    for i in b:eda_utils_HiLightWords
        let n = len(i)
        if n > 4 && i[0:1] == '\<' && i[n-2:n-1] == '\>'
            echo i[2:n-3]
        else
            echo i
        endif
    endfor
endfunction

" Highlight words in b:eda_utils_HiLightWords.
function! eda_utils#HiLightRender(bang)
    if !exists("b:eda_utils_HiLightWords") || len(b:eda_utils_HiLightWords)==0
        return
    end
    let m = getmatches()
    if len(m) != 0
        let b:eda_utils_HiLightPrev = m
    endif
    :call clearmatches()
    let b:eda_utils_HiLightID = 0
    for cword in b:eda_utils_HiLightWords
        if a:bang != ""
            let cword = '\<' . cword . '\>'
        end
        let b:eda_utils_HiLightID = (b:eda_utils_HiLightID + 1) % len(g:eda_utils_HiLightGroups)
        let cg = g:eda_utils_HiLightGroups[b:eda_utils_HiLightID]
        :call matchadd(cg, cword)
    endfor
    :call setreg('/', join(b:eda_utils_HiLightWords, '\|'))
endfunction

" Copy the buffer local matches to the global.
function! eda_utils#HiLightCopy()
    let m = getmatches()
    if len(m) != 0
        let g:eda_utils_HiLightPrev = m
    endif
endfunction

" Load the buffer local matches from the global.
function! eda_utils#HiLightLoad()
    if exists("g:eda_utils_HiLightPrev")
        let b:eda_utils_HiLightPrev = g:eda_utils_HiLightPrev
        :call clearmatches()
        :call eda_utils#HiLightToggle()
    endif
endfunction

"-----------------------------------------------------------------------------
" Synchroize loclist and cursor, then show the current match position.
function! eda_utils#ShowLoclistOnCurrLine()
    let curLine = line(".")
    let list = getloclist(".")
    if len(list) == 0
        :echo "loclist not found"
        return
    endif

    if version >= 800
        let ent = len(filter(getloclist("."), {i,v -> v.lnum <= curLine}))
    else
        let i = 0
        let ent = -1
        for v in getloclist(".")
            echom v.lnum.":".curLine
            if v.lnum >= curLine
                if v.lnum == curLine
                    let ent = i + 1
                else
                    let ent = i
                endif
                break
            endif
            let i = i + 1
        endfor
    endif
    if ent <= 0
        :echo "Before first match ".list[0].lnum
        return
    endif

    let pos = [ 0, curLine, col("."), 0 ]

    " Move in loclist.
    silent exe "ll ".ent

    " Re-set cursor position.
    :call setpos(".", pos)

    " Do redraw to keep message in the status window.
    redraw | echo "(".ent." of ".len(list).") line:".list[ent-1].lnum." ".list[ent-1].text
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""" cargo-make
" For makers (cargo-make), search Makefile.toml up to 4 parent directory.
function! eda_utils#Makers(...)
    :let c = 1
    :let prefix = ""
    :if a:0 > 0
    :  let args = join(a:000, " ")
    :else
    :  let args = "default"
    :endif
    :while c <= 4
    :    echom prefix
    :  if filereadable(prefix . "Makefile.toml")
    :    if c == 1
    :      let cwd = ""
    :    else
    :      let cwd = "--cwd " . prefix
    :    endif
    :    let cmd = "Job makers " . cwd . " " . args
    :    echom cmd
    :    exe cmd
    :    break
    :  endif
    :  if isdirectory(prefix . ".git")
    :    break
    :  endif
    :  let prefix = "../" . prefix
    :  let c += 1
    :endwhile
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""" gtags 6.6.8
function! eda_utils#GlobalComplete(findstart, base)
  if a:findstart == 1
    return s:LocateCurrentWordStart()
  else
    return split(system('global -c ' . a:base), '\n')
  endif
endfunction

function! s:LocateCurrentWordStart()
  let l:line = getline('.')
  let l:start = col('.') - 1
  while l:start > 0 && l:line[l:start - 1] =~# '\a'
    let l:start -= 1
  endwhile
  return l:start
endfunction

"-----------------------------------------------------------------------------
let &cpoptions = s:save_cpo
unlet s:save_cpo
