# viclaude

A Vim plugin for browsing Claude Code conversation history.

## Usage

Open Vim in a project directory where you've used Claude Code, then run:

```vim
:ClaudeHistory
```

This opens a quickfix list of sessions for the current project, sorted by most recent. Press `<Enter>` on an entry to view the rendered conversation.

## Install

With a plugin manager (e.g. vim-plug):

```vim
Plug 'user/viclaude'
```

Or clone into your Vim packages directory:

```sh
git clone https://github.com/user/viclaude ~/.vim/pack/plugins/start/viclaude
```

## License

MIT
