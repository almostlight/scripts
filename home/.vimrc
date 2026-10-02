" ============================================================================
" .vimrc
" Shared configuration for:
"   - Vim
"   - VSCodeVim (vim.vimrc.path)
"   - IdeaVim (~/.ideavimrc)
" ============================================================================

" ============================================================================
" Leader
" ============================================================================

let mapleader = ' '
let maplocalleader = ' '

" ============================================================================
" Plugin globals
" ============================================================================

let g:tex_flavor = 'latex'
let g:tex_conceal = 'abdmgs'

let g:airline_powerline_fonts = 1

let g:livepreview_previewer = 'zathura'

let g:vimtex_view_method = 'zathura'
let g:vimtex_compiler_method = 'latexrun'

" ============================================================================
" Display
" ============================================================================

set number
set relativenumber

set cursorline

" Don't show the mode
" set noshowmode

set signcolumn=yes

set scrolloff=10

set splitright
set splitbelow

set conceallevel=2

set showmatch

set ttyfast

" Highlight column 80
set colorcolumn=80

" ============================================================================
" Spell
" ============================================================================

set spell
set spelllang=pl

" ============================================================================
" Search
" ============================================================================

set hlsearch
set incsearch

set ignorecase
set smartcase

" ============================================================================
" Indentation and whitespace
" ============================================================================

set tabstop=4
set shiftwidth=4
set softtabstop=4

set autoindent
set breakindent

set list

" tab     = »
" trail   = ·
" nbsp    = ␣
set listchars=tab:»\ ,trail:·,nbsp:␣

" ============================================================================
" Editing behaviour
" ============================================================================

" Disable mouse interactions
set mouse=

" System clipboard
set clipboard=unnamedplus

" Persistent undo
set undofile

" Ask before commands that would discard unsaved changes
set confirm

" Command-line completion
set wildmode=longest,list

" ============================================================================
" Backups
" ============================================================================

set backup
set backupcopy=yes
set backupdir=~/.vim/backup/
set writebackup

" ============================================================================
" Encoding
" ============================================================================

scriptencoding utf-8

" ============================================================================
" Timing
" ============================================================================

set updatetime=250
set timeoutlen=300

" ============================================================================
" Filetype
" ============================================================================

filetype plugin indent on
syntax enable

" ============================================================================
" KEYMAPS
" ============================================================================

" --------------------------------------------------------------------------
" Search
" --------------------------------------------------------------------------

" Clear search highlights
nnoremap <Esc> :nohlsearch<CR>

" --------------------------------------------------------------------------
" Disable arrow keys
" --------------------------------------------------------------------------

nnoremap <Left>  :echo "Use h to move!!"<CR>
nnoremap <Right> :echo "Use l to move!!"<CR>
nnoremap <Up>    :echo "Use k to move!!"<CR>
nnoremap <Down>  :echo "Use j to move!!"<CR>

" --------------------------------------------------------------------------
" Window navigation
" --------------------------------------------------------------------------

nnoremap <C-h> <C-w><C-h>
nnoremap <C-l> <C-w><C-l>
nnoremap <C-j> <C-w><C-j>
nnoremap <C-k> <C-w><C-k>

" ============================================================================
" Terminal mode
" ============================================================================
" Exit terminal mode with <Esc><Esc>
" This is only relevant to actual Vim/Neovim terminal buffers.
" VSCodeVim and IdeaVim will simply ignore it if terminal-mode mappings
" aren't supported by the host.

if exists(':tnoremap')
tnoremap <Esc><Esc> <C-><C-n>
endif

" ============================================================================
" Quickfix / diagnostics
" ============================================================================

nnoremap <leader>q :lopen<CR>

" ============================================================================
" VimTeX
" ============================================================================
" Clean up VimTeX temporary files when leaving a TeX buffer.

if exists('*execute')

```
augroup vimtex-cleanup
    autocmd!
    autocmd VimLeave *.tex silent! VimtexStop | silent! VimtexClean
augroup END
```

endif

" ============================================================================
" Yank highlighting
" ============================================================================
"
if exists('*matchadd')

```
function! s:HighlightYank() abort
    silent! matchdelete(get(w:, 'yank_match_id', -1))

    let w:yank_match_id = matchadd(
                \ 'IncSearch',
                \ '\%'.line("'[").'l\%'.col("'[").'c\%'.line("']").'l\%'.col("']").'c'
                \ )

    call timer_start(150, function('s:ClearYankHighlight'))
endfunction

function! s:ClearYankHighlight(timer) abort
    if exists('w:yank_match_id')
        silent! matchdelete(w:yank_match_id)
        unlet w:yank_match_id
    endif
endfunction

augroup highlight-yank
    autocmd!
    autocmd TextYankPost * silent! call <SID>HighlightYank()
augroup END
```

endif

" ============================================================================
" File explorer
" ============================================================================

nnoremap <leader>e :Explore<CR>

" Optional persistent sidebar:
"
" nnoremap <leader>e :Lexplore<CR>

" Parent directory in netrw
augroup netrw-custom
autocmd!

```
autocmd FileType netrw nnoremap <buffer> <C-t> -

autocmd FileType netrw nnoremap <buffer> ?
            \ :help netrw<CR>
```

augroup END

