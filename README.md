<p align="center">
  <img src="monkeys.svg" alt="" width="200">
</p>

<h1 align="center">monkeys</h1>

<p align="center">
  <code>.env</code> you can hand to an LLM, or <code>git add</code>.<br>
  The name reads as <em>mon keys</em>: my keys.
</p>

<p align="center">
  <img alt="license" src="https://img.shields.io/github/license/eastriverlee/monkeys?color=E94100">
  <img alt="swift 6.1" src="https://img.shields.io/badge/swift-6.1-E94100">
  <img alt="macOS and Linux" src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-E94100">
</p>

<p align="center">
  <img src="terminal.svg" alt="monkeys remembering a secret, running a command with it, forgetting it, and then refusing the same command" width="640">
</p>

## Overview

`.monkeys` is a `.env` you can commit. Keys stay in the file, secrets stay in
your vault. Even the command you hand one to cannot print it.

```
with .env                   with monkeys

foo/                        foo/
├── .env                    ├── .monkeys
├── .env.example            └── hello.sh
├── .gitignore
└── hello.sh
```

Four files become one, and it is the one you commit:

```monkeys
+foo
@test
OPENROUTER_API_KEY
PORT=3000
```

```sh
monkeys remember OPENROUTER_API_KEY  # the secret goes into the vault, once
monkeys run ./hello.sh               # the command gets it, nothing else does
monkeys pack                         # to share: one encrypted file
```

It exists for two reasons, and either would have been enough.

1. **LLMs read `.env`.** `cat .env` is just too tempting, and once it's in
   the transcript, it's there for good. The usual answers are to ignore it,
   trust the provider, or rotate the key after it leaks. Skill issue? There
   was never a safe way to share a secret, so it went in a file. Being
   careful never fixed C's memory bugs. Rust did.

2. **`.env` was never good, even for people.** Sharing it means pasting the
   whole file into a chat. Test and production mean two more files and a
   loader. Staying out of git means an `.env.example` that drifts. `monkeys`
   folds all of it into one committed file, and `pack` shares the whole thing
   or the part a teammate needs.

## Install

### Install script

On macOS or Linux, from the latest release:

```sh
curl -fsSL https://monk3ys.dev/install | sh
```

The script picks the build for your operating system and processor, checks the
published checksum, and installs into `~/.local/bin`. Set `INSTALL_DIRECTORY`
to put it elsewhere. It is short, and reading it first is a fine habit.

### Homebrew

Which then upgrades `monkeys` along with everything else:

```sh
brew install eastriverlee/tap/monkeys
```

### From source

With Swift 6.1 or later, on macOS 13 or later or on Linux:

```sh
git clone https://github.com/eastriverlee/monkeys
cd monkeys
make install
```

### Update

```sh
monkeys update
```

`monkeys upgrade` does the same. Homebrew installs update through Homebrew;
other installs download the latest release, verify its checksum and replace
`monkeys` in its current directory.

### On Linux

`monkeys` reaches the vault through `secret-tool`: install `libsecret-tools`
on Debian and Ubuntu, `libsecret` on Fedora and Arch.

## Quickstart

### Remember it

```sh
monkeys remember SUPER_SECRET
```

Type `sesame` at the prompt.

### Run with monkeys

```sh
monkeys run SUPER_SECRET sh -c '
  test "$SUPER_SECRET" = sesame && echo opened || echo closed
  echo "the word was $SUPER_SECRET"
'
```

> ```
> opened
> the word was [redacted SUPER_SECRET]
> ```

The right word reached the command, and what the command printed came back
with the secret taken out. `run` becomes the command once the secret is set,
so the exit status, the output and the signals are the command's own.

### Run without monkeys

```sh
sh -c 'test "$SUPER_SECRET" = sesame && echo opened || echo closed'
```

> ```
> closed
> ```

### Forget and retry

```sh
monkeys forget SUPER_SECRET
monkeys run SUPER_SECRET sh -c '
  test "$SUPER_SECRET" = sesame && echo opened || echo closed
'
```

> ```
> forgot SUPER_SECRET
> monkeys: SUPER_SECRET is not remembered yet
> nothing happened. a human types the secret into:
>   monkeys remember SUPER_SECRET
> then try again.
> ```

Nothing ran at all: a missing secret stops `run` before the command starts,
and the message says what to do, which is what an agent passes on.

Inside a git checkout the first step also started a `.monkeys` and listed
`SUPER_SECRET` in it, since that file is how a project says which keys it
needs. `monkeys drop SUPER_SECRET` takes the key back out of it, and
`monkeys poo` writes a `.env` of those keys with nothing after them, for a
tool that wants the file to exist.

## Plugin

The binary is the whole tool, and an agent that can run a shell can already
use it. The plugin adds the skill, which is what makes the agent reach for
`monkeys` on its own instead of asking you to paste a secret.

`plugins/monkeys` is an [Agent Plugins](https://agent-plugins.org) package
around an [Agent Skills](https://agentskills.io) skill, and this repository is
a marketplace for it in the two clients that have one:

```tree
plugins/monkeys/
├── plugin.json
└── skills/monkeys/SKILL.md
```

### Claude Code

```sh
claude plugin marketplace add eastriverlee/monkeys
claude plugin install monkeys@eastriverlee
```

`/monkeys:install` then fetches the binary, and a session that starts without
one says so.

### Codex

```sh
codex plugin marketplace add eastriverlee/monkeys
codex plugin add monkeys@eastriverlee
```

Codex does not fetch the binary, so install that first.

### Other agents

Agent Skills is an open standard, and the directory its clients share is
`.agents/skills`. <https://monk3ys.dev/skill> serves the file:

```sh
mkdir -p .agents/skills/monkeys
curl -fsSL https://monk3ys.dev/skill -o .agents/skills/monkeys/SKILL.md
```

That covers the project. `~/.agents/skills/monkeys/SKILL.md` covers every
project at once. Codex, Cursor and opencode read both, alongside a directory
of their own such as `.cursor/skills`, and other clients follow the same
pattern.

The skill restates a few invocations so an agent knows them before it runs
anything. `make check` holds that copy to the binary, failing when the skill
names a command `monkeys help` does not list.

## Documentation

Everything else, from the command list to what `run` hands back, is
[DOCS.md](DOCS.md), rendered with search at <https://docs.monk3ys.dev>.

## Contributing

Bugs and proposals go through the issue templates, which ask for what a fix
or a decision needs. A pull request runs `make check` first: it holds the help
text, the skill and the docs to the binary.

## Sponsoring

If it has saved you a key once, you know what it is worth.
[Sponsoring](https://github.com/sponsors/onethreeeseven) keeps the builds
current, the plugin working in each new agent, and the redaction ahead of new
ways output leaks. One-time is fine.

## License

MIT
