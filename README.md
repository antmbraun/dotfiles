# dotfiles

```sh
git clone https://github.com/antmbraun/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

The installer links the configs below into `$HOME`, sources the zsh snippets from `~/.zshrc`, points both Claude accounts (`~/.claude` for work, `~/.claude-personal` for personal) at the status line, prompt hook and shared rules, and links the herdr plugins. Open a new terminal afterwards.

## What's here

| Path | What it is |
|---|---|
| `herdr/config.toml` | herdr (run `herdr` in Ghostty): sidebar layout, tab bar usage line, keys |
| `herdr/plugins/space-shell` | Lays out every new tab: Claude left, shell top-right, status board bottom-right |
| `herdr/plugins/space-tasks` | Lists each space's tasks under it, with state, branch and PR |
| `herdr/plugins/sort-spaces` | Keeps spaces in alphabetical order, "other" last |
| `herdr/space-status.sh`, `herdr/usage.sh` | The status board, and the Claude usage line |
| `claude/statusline-command.sh` | Claude Code status line; also reports each Claude's branch to herdr |
| `claude/hooks/herdr-last-prompt.sh` | Shows each Claude's last prompt in herdr's Agents panel |
| `claude/CLAUDE.md`, `claude/rules/` | Instructions shared by both Claude accounts |
| `zsh/worktrees.zsh` | `task`, `wt-setup`, `wt-open`, `wt-done` |
| `ghostty/config`, `vimrc`, `zsh/colors.zsh` | Terminal, editor and prompt |

## Working in tasks

One herdr space per repo (`b2b`, `play`, `bkr`, or `other`), one tab per task, each with its own Claude.

```sh
task slack-followups              # tab in "other", Claude in ~/Repos
task new-relic b2b                # tab in "b2b", Claude in the main checkout
task fix/pricing-cache b2b wt     # new worktree ~/Repos/mktg-web-b2b-pricing-cache on branch fix/pricing-cache
wt-done pricing-cache             # after it merges: delete its DDEV site, folder, branch and tab
```

With `wt`, the tab's shell starts DDEV and copies the main checkout's database in (a few minutes) while Claude starts. Run `ddev stop` in worktrees you aren't testing. Repos for `task` are the `TASK_REPOS` line in `zsh/worktrees.zsh`.

## Keys

`prefix` is Ctrl+B.

| Keys | |
|---|---|
| `Alt+/` (or `prefix` `g`) | Goto picker: every Claude and terminal; `/` to search |
| `Alt+1`..`9` | Nth Claude in the Agents panel |
| `prefix` `.` / `,` | Next / previous Claude (what needs you first) |
| `prefix` `o` | The task behind the current notification |
| `prefix` `Space` | Back to the last pane, across tabs and spaces |
| `prefix` `n` / `p`, `prefix` `1`..`9` | Next / previous task, task N in this space |
| `prefix` `h` `j` `k` `l` | Move between Claude, shell and status board |
| `prefix` `t` | Show or hide the shell pane |
| `prefix` `Shift+S` | Rebuild a tab's layout |
| `prefix` `z` | Zoom the focused pane |
| `prefix` `?` | Every binding |

Alt needs the left Option key to send Alt, which `ghostty/config` sets.

## Manual setup (not done by the installer)

- **herdr and Ghostty**: install both, and use the herdr terminal app, not the native Herdr.app, which reads none of this.
- **Docker memory for DDEV worktrees**: a b2b site runs out of memory at 6 GB with two sites up. `colima stop && colima start --memory 16 --cpu 8` (kept in `~/.colima/default/colima.yaml`).
- **DDEV DNS**: if the router blocks `*.ddev.site` (DNS rebinding protection), `ddev start` asks for sudo to edit `/etc/hosts`. Instead:
  `sudo mkdir -p /etc/resolver && echo "nameserver 1.1.1.1" | sudo tee /etc/resolver/ddev.site`
- **A repo's main checkout**: when its `.ddev/config.yaml` has no `name:`, the project takes the folder's name. To keep an older project name and its database, put `name: <old-name>` in `.ddev/config.local.yaml` (git ignores it).
