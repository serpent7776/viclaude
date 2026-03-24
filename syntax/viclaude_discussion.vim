if exists('b:current_syntax')
  finish
endif

runtime! syntax/markdown.vim
unlet! b:current_syntax

" Blockquote lines (user messages) with distinct background
syntax match viclaudeBlockquote /^>.*$/ contains=@Spell
highlight viclaudeBlockquote ctermfg=cyan ctermbg=236 guifg=#00ffff guibg=#303030

" Thinking lines (extended thinking output)
syntax match viclaudeThinking /^\~.*$/ contains=@Spell
highlight viclaudeThinking ctermfg=243 guifg=#767676

let b:current_syntax = 'viclaude_discussion'
