" eda_utils.vim : Utils for EDA tools
 
if !exists('g:loaded_gtags_from_eda_utils')
    let s:file = fnamemodify(expand('<sfile>'), ':p:h') . "/../externals/gtags.vim"
    execute 'source ' . s:file
    let g:loaded_gtags_from_eda_utils = 1
endif
if exists('g:loaded_eda_utils')
    finish
endif
let g:loaded_eda_utils = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

if !exists("g:eda_utils_HiLightGroups")
    " used in eda_utils#HiLightSearch
    let g:eda_utils_HiLightGroups = [
    \'StatusLine',
    \'Sneak',
    \'DiffAdd',
    \'DiffChange',
    \'DiffDelete',
    \'DiffText',
    \'SpellBad',
    \'SpellCap',
    \'SpellRare',
    \'SpellLocal'
    \]
end

if !exists("g:eda_utils_shell") || !executable(g:eda_utils_shell)
    let g:eda_utils_shell = 'bash'
endif

if has('terminal') || has('nvim')
    command! -bang MakeTerminal   :call eda_utils#MakeTerminal("<bang>")
    command! -bang DeleteTerminal :call eda_utils#DeleteTerminal("<bang>")
endif

command! ViewTable              :call eda_utils#ViewTable()
command! ShowLoclistOnCurrLine  :call eda_utils#ShowLoclistOnCurrLine()

"-----------------------------------------------------------------------------
" Make Table Of Contents.
command! -bang VToc  call eda_utils#Toc("<bang>")
command! -bang VToch call eda_utils#Toc("<bang>", 'horizontal')
command! -bang VTocv call eda_utils#Toc("<bang>", 'vertical')
command! -bang VToct call eda_utils#Toc("<bang>", 'tab')
command! -bang CToc  call eda_utils#Toc("ctags")

"-----------------------------------------------------------------------------
" Invoke HDL simulator or general jobs.
if !exists("g:eda_utils_verilog_opt")
    let g:eda_utils_verilog_opt = ' -y . +libext+.v+.sv +incdir+.'
endif

" args: queue, host, tool
command! -bang -complete=file -nargs=+ Run
\   call eda_utils#Run("bsub", <f-args>)

" args: options to vcs
command! -bang -complete=file    -nargs=* Vcs
\   silent call eda_utils#Run("bsub", get(g:,"eda_utils_bsub_queue",""), get(g:,"eda_utils_bsub_host",""), get(g:,"eda_utils_bsub_vcs",""), "vcs -R -sverilog", g:eda_utils_verilog_opt, "<bang>" == "!" ? "" : expand("%"), <f-args>)

" args: options to qverilog
command! -bang -complete=file -nargs=* Qverilog
\   silent call eda_utils#Run("bsub", get(g:,"eda_utils_bsub_queue",""), get(g:,"eda_utils_bsub_host",""), get(g:,"eda_utils_bsub_questa",""), "qverilog -sv", g:eda_utils_verilog_opt, "<bang>" == "!" ? "" : expand("%"), <f-args>)

" args: options to xcelium
command! -bang -complete=file -nargs=* Xrun
\   silent call eda_utils#Run("bsub", get(g:,"eda_utils_bsub_queue",""), get(g:,"eda_utils_bsub_host",""), get(g:,"eda_utils_bsub_xcelium",""), "xrun -sv", g:eda_utils_verilog_opt, "<bang>" == "!" ? "" : expand("%"), <f-args>)

" args: shell command
command! -complete=file -nargs=+ Bjob
\   silent call eda_utils#Run("bsub", get(g:,"eda_utils_bsub_queue",""), get(g:,"eda_utils_bsub_host",""), "other", <f-args>)

" args: shell command
command! -complete=file -nargs=+ Job
\   silent call eda_utils#Run("shell", "", "", "", <f-args>)

"-----------------------------------------------------------------------------
" other utilties
"
if !exists("g:eda_utils_vlint")
    let g:eda_utils_vlint = "verilator --lint-only -Wall"
endif

if !exists("g:eda_utils_clint")
    let g:eda_utils_clint = "gcc -c -Wall"
endif

if exists("g:eda_utils_modelsim_ase")
    let s:modelsim_ase = "MTI_VCO_MODE=32 " . g:eda_utils_modelsim_ase
    if exists("g:eda_utils_modelsim_ase_work") && isdirectory(g:eda_utils_modelsim_ase_work)
        let s:modelsim_ase_work = " -work " . g:eda_utils_modelsim_ase_work
        let s:modelsim_ase_lib  = " -lib " . g:eda_utils_modelsim_ase_work
    else
        let s:modelsim_ase_work = ""
        let s:modelsim_ase_lib = ""
    endif
    command! -bang -nargs=*	Vlog 	silent call eda_utils#Run("bash", "", "", "", s:modelsim_ase . "/bin/vlog", "-sv -lint -mfcu", g:eda_utils_verilog_opt, s:modelsim_ase_work, "<bang>" == "!" ? "" : expand("%"), <f-args>)
    command! -bang -nargs=*	Vrun 	silent call eda_utils#Run("bash", "", "", "", s:modelsim_ase . "/bin/vlog", "-sv -lint -mfcu", g:eda_utils_verilog_opt, s:modelsim_ase_work . "<bang>" == "!" ? "" : expand("%"), expand(<q-args>), "-R -c -do 'run -all; quit -f;'")
    command!       -nargs=*	Vsim 	silent call eda_utils#Run("bash", "", "", "", s:modelsim_ase . "/bin/vsim", "-c", s:modelsim_ase_lib, " #1:r -do quit")
endif

"command! -bang -nargs=*	-complete=file  CLint 	:let s:_makeprg_ = &makeprg | :execute "setlocal makeprg=".s:clang_check."\\ %" | :make<bang> <f-args> | :execute "setlocal makeprg=".s:_makeprg_
command! -bang -nargs=*	-complete=file  CLint 	:silent call eda_utils#Run("shell", "", "", "", g:eda_utils_clint, "<bang>" == "!" ? "" : expand("%"), <f-args>)
command! -bang -nargs=* -complete=file 	VLint 	:silent call eda_utils#Run("shell", "", "", "", g:eda_utils_vlint, "<bang>" == "!" ? "" : expand("%"), <f-args>)
command! 			    CTags 	!ctags --language=C++ -R
command! 			    VTagsHier 	!ctags --verilog-kinds=-cefnprt -R
command! 			    VTags 	!ctags --verilog-kinds=* -R
command! -nargs=*	GitDiff 	:call eda_utils#GitDiff(<f-args>)
command! -nargs=?	SvnDiff 	:call eda_utils#SvnDiff(<f-args>)
command! -nargs=+	SvnMerge 	:call eda_utils#SvnMerge(<f-args>)
command! CCLint    call eda_utils#CheckClang()
command! CVLint    call eda_utils#CheckVerilator()
command! CQverilog call eda_utils#CheckQuesta()
command! CVlog     call eda_utils#CheckQuesta()
command! CVcs      call eda_utils#CheckVcs()
command! CXrun     call eda_utils#CheckXrun()

command! -range HiLightSearch :call eda_utils#HiLightSearch(0,<range>)
command! HiLightClear  :call eda_utils#HiLightClear()
command! HiLightToggle :call eda_utils#HiLightToggle()
command! HiLightDump   :call eda_utils#HiLightDump()
command! -bang HiLightRender :call eda_utils#HiLightRender("<bang>")
command! HiLightCopy   :call eda_utils#HiLightCopy()
command! HiLightLoad   :call eda_utils#HiLightLoad()

command!          RegisterBuffers   call eda_utils#RegisterBuffers()
command! -nargs=+ Bufgrep           call eda_utils#BufGrep(<f-args>)
command! -nargs=* -complete=file  Makers call eda_utils#Makers(<f-args>)

"-----------------------------------------------------------------------------
" keymaps
if exists("g:eda_utils_mapleader")
    if exists("g:mapleader")
        let s:old_mapleader = g:mapleader
    else
        let s:old_mapleader = ""
    endif
    let mapleader = g:eda_utils_mapleader

    "vnoremap <C-l> :call eda_utils#MarkDownLink()<CR>
    vnoremap <leader>( :call eda_utils#Surround('(',')')<CR>
    vnoremap <leader>) :call eda_utils#Surround('(',')')<CR>
    vnoremap <leader>" :call eda_utils#Surround('"','"')<CR>
    vnoremap <leader>' :call eda_utils#Surround("'","'")<CR>
    vnoremap <leader>` :call eda_utils#Surround('`','`')<CR>
    vnoremap <leader>{ :call eda_utils#Surround('{','}')<CR>
    vnoremap <leader>} :call eda_utils#Surround('{','}')<CR>
    vnoremap <leader>[ :call eda_utils#Surround('[',']')<CR>
    vnoremap <leader>] :call eda_utils#Surround('[',']')<CR>

    " overwrite :gs = :sleep => graphical search 
    nnoremap gs :call eda_utils#HiLightSearch(1,0)<CR>
    nnoremap gS :call eda_utils#HiLightSearch(0,0)<CR>
    vnoremap gs :call eda_utils#HiLightSearch(0,1)<CR>
    vnoremap gS :call eda_utils#HiLightSearch(0,1)<CR>

    nnoremap <silent> <leader>i :call eda_utils#ShowLoclistOnCurrLine()<CR>
    nnoremap <silent> <leader>v :call eda_utils#ViewTable()<CR>
    nnoremap <expr>   <leader>j ':Job '
    nnoremap <expr>   <leader>m ':Makers '

    noremap <F7>  <ESC>:execute "Ggrep ".expand('<cword>')<CR>
    noremap <F8>  <ESC>:Makers<CR>
    noremap <F11> :make <CR>
    noremap <F12> :grep <cword> .<CR>

    if executable('global')
        "let g:Gtags_No_Auto_Jump = 1
        nnoremap <silent> <leader>gf  :Gtags -f %<CR>
        nnoremap <expr>   <leader>gd ':Gtags -a  ' . expand('<cword>') . '<CR>'
        nnoremap <expr>   <leader>gr ':Gtags -ar ' . expand('<cword>') . '<CR>'
        nnoremap <expr>   <leader>gg ':Gtags -ag ' . expand('<cword>')
    endif

    if s:old_mapleader == ""
        unlet g:mapleader
    else
        let g:mapleader = s:old_mapleader
    endif
endif

"-----------------------------------------------------------------------------
if executable('global')
    augroup eda_utils_GlobalComplete
      autocmd!
      autocmd FileType * if &omnifunc == "" | setlocal omnifunc=eda_utils#GlobalComplete | endif
    augroup END
endif

"-----------------------------------------------------------------------------
let &cpoptions = s:save_cpo
unlet s:save_cpo
