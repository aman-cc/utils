let g:ale_completion_enabled = 1
let g:ale_completion_autoimport = 0
set omnifunc=ale#completion#OmniFunc
filetype plugin on
let g:ale_linters = {
      \ 'python': ['ruff'],
      \ }

call plug#begin()
    Plug 'dense-analysis/ale'
    Plug 'Shougo/deoplete.nvim'
    Plug 'vim-airline/vim-airline'
    Plug 'scrooloose/nerdcommenter'
    Plug 'jiangmiao/auto-pairs'
    Plug 'morhetz/gruvbox'
call plug#end()

let g:deoplete#enable_at_startup = 1

set clipboard+=unnamedplus
xnoremap p pgvy
set number
set shiftwidth=4
syntax enable
set background=dark
colorscheme gruvbox

" filetype plugin on

" set tabstop=4

" Uncomment the following to have Vim jump to the last position when
" reopening a file
if has("autocmd")
  au BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$")
    \| exe "normal! g'\"" | endif
endif

let g:python3_host_prog = expand('~/.venv/bin/python')

