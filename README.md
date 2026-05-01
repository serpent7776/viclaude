# viclaude

A Vim plugin for browsing Claude Code conversation history.

## Usage

Open Vim in a project directory where you've used Claude Code, then run:

```vim
:ClaudeHistory
```

This opens a quickfix list of sessions for the current project, sorted by most recent. Press `<Enter>` on an entry to view the rendered conversation.

To search across all sessions for a pattern:

```vim
:ClaudeGrep <pattern>
```

This opens a quickfix list of matching excerpts (one per match) from user and assistant messages, sorted by most recent session. Press `<Enter>` on an entry to open the rendered conversation jumped to that match.

![Preview](files/viclaude2.png)

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
