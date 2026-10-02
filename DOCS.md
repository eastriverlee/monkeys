# Overview

`.monkeys` is a `.env` you can commit. Keys stay in the file, secrets stay in
each person's vault, and `monkeys run` hands them to the command that needs
them. Even that command cannot print one.

## Why it exists

Two reasons, and either would have been enough.

1. **LLMs read `.env`.** `cat .env` is just too tempting, and once it's in
   the transcript, it's there for good. `monkeys` takes that path away. The
   secret goes from the vault straight into the process, a missing one comes
   back as a message saying what to ask for, and whatever the command prints
   comes back redacted.

2. **`.env` was never good, even for people.** Sharing it means pasting the
   whole file into a chat. Test and production mean two more files and a
   loader. Staying out of git means an `.env.example` that drifts. `monkeys`
   folds all of it into one committed file, and `pack` shares the whole thing
   or the part a teammate needs.

## What it is

The same project, kept both ways. With `.env`, three files have to stay in
step, and the one with the secrets is the one you must not commit:

```tree
foo/
├── .env
├── .env.example
├── .gitignore
└── hello.sh
```

```ini title=".env"
OPENROUTER_API_KEY=sk-or...
STRIPE_SECRET_KEY=sk_li...
```

```ini title=".env.example"
OPENROUTER_API_KEY=
STRIPE_SECRET_KEY=
```

```text title=".gitignore"
.env
```

With `monkeys`, one file holds the keys, the vault holds the secrets, and the
file is the one you commit:

```tree
foo/
├── .monkeys
└── hello.sh
```

```monkeys title=".monkeys"
+foo
@test
OPENROUTER_API_KEY
STRIPE_SECRET_KEY
```

```sh
monkeys remember OPENROUTER_API_KEY  # the secret goes into the vault, once
monkeys run ./hello.sh               # the command gets them, nothing else does
monkeys pack                         # to share: one encrypted file
```

One file replaces three. A line that was never secret sits in it as
`KEY=value`. One binary for macOS and Linux does the rest: no runtime, no
service, no vault of its own.

## What it is not

Not a secret manager with a server or an audit log. Not a wall against an
agent that sets out to read a secret; it removes the reflex, which is the
everyday problem.

## Where to go next

[Quickstart](/docs/quickstart) remembers a secret and uses it,
[Concepts](/docs/concepts/key) defines every term the reference uses, and
[Commands](/docs/commands) has one page per command.

# Concepts

## Key

A key is the name of an environment variable, the `KEY` of `KEY=secret`.

It is what a program reads, what a `.monkeys` file lists, and what every
command takes on its line:

```sh
monkeys remember OPENROUTER_API_KEY
monkeys run OPENROUTER_API_KEY ./hello.sh
```

### Form

A key takes letters, digits and `_`, and cannot start with a digit, the rule
POSIX gives for a variable name. `OPENROUTER_API_KEY` is a key;
`openrouter-key` is refused.

### Where a key appears

Keys are public. They are committed in `.monkeys`, they appear in `list` and
in every message, and the process `run` starts sees them as the names of its
variables. `monkeys` takes no secret as an argument, only keys, so remembering one
never types it: your shell history and the process table both see
`monkeys remember GITHUB_TOKEN` and nothing more.

### One key, several secrets

The same key in two profiles is two secrets, `foo.test/DATABASE_URL` and
`foo.production/DATABASE_URL`, and the key alone, with no profile, is a third.
Which one a command gets is decided by the profile, never by the key.

## Secret

A secret is what a key holds: the API key, token or password itself.

It is the only thing `monkeys` exists to keep, and the only thing it never
prints.

### Where it goes

A secret enters the vault through `remember`, typed at a prompt, piped in or
pasted from the clipboard. It leaves one way only: into the environment of a
command that `run` starts. What that command prints comes back through
`monkeys`, which replaces the secret with `[redacted KEY]` on the way.

### Replacing one

Remembering a secret under a key that already has one replaces it, and
nothing says so. The previous secret is gone; the vault keeps no history to
recover it from.

### Reading one

No `monkeys` command prints a secret. To read one in full, open the vault
itself, Keychain Access on macOS or the desktop's secret browser on Linux,
where the decision to look at one is yours and deliberate.

## Value

A value is the other thing a key can hold: a setting that is safe to commit.

`PORT=3000`, `API_URL=https://api.example.com`, `NODE_ENV=development`. In a
`.env` file these sat on the same lines as the secrets; here they sit in
`.monkeys` as `KEY=value` and the vault never sees them.

### Where it lives

A value is written into `.monkeys` on the key's own line, after an `=`, and
belongs to every profile of the block above it. One that differs by profile,
a port or a hostname, goes in that profile's own block. It is committed with
the file, so a clone has it without anyone being asked for anything.

### What it is not

A value is public by definition. Anything that must stay out of the
repository is a secret, and goes in the vault under a bare key. For one
profile a key is one or the other, never both.

### How the commands treat it

`run` puts a value into the command's environment straight from the file,
alongside the secrets from the vault, and never redacts it. `preview` and
`doctor` show it as it is. `set --public` writes one, `forget` deletes the
line, and `eat` writes one for every `.env` line answered as public.

## Vault

The vault is the operating system's own secret store.

`monkeys` keeps nothing anywhere else. There is no file of `monkeys`'s own to
back up, leak or forget, and the desktop's own tools see everything `monkeys`
remembers.

| platform | vault | reached through |
| --- | --- | --- |
| macOS | the login keychain | Security.framework |
| Linux | whatever answers the [Secret Service](https://specifications.freedesktop.org/secret-service-spec/latest/) API over D-Bus: GNOME Keyring on most desktops, KWallet on KDE | `secret-tool` from libsecret |

### What an item looks like

Each secret is one item carrying two attributes: `service` is `monkeys`, and
`account` is `<profile>/<KEY>`, or `<KEY>` alone for a key with no profile, so a
project's item reads `foo.test/OPENROUTER_API_KEY`. The label is `monkeys: `
followed by the account. Deleting an item in the desktop's tools deletes it
for `monkeys`.

On macOS that is a generic password in the login keychain. Search Keychain
Access for `monkeys`, or ask for one by account:

```sh
security find-generic-password -s monkeys -a OPENROUTER_API_KEY
security find-generic-password -s monkeys -a foo.test/OPENROUTER_API_KEY
```

Items are created with
[`kSecAttrAccessibleAfterFirstUnlock`](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlock),
so a shell that starts while the screen is locked can still read them.

On Linux the same attributes go through `secret-tool`:

```sh
secret-tool lookup service monkeys account foo.test/OPENROUTER_API_KEY
```

### What the keychain asks

A keychain item remembers the program that stored it, and asks before any
other program reads it, once per item. Always Allow adds that program to the
item, and the keychain stays quiet for it from then on.

What counts as the same program is its signature. The release builds are
signed with one Developer ID, so an upgrade is the same program and asks
nothing. A build from source is signed ad-hoc, whose identity is the binary's
own hash, so each rebuild asks again for every item it reads. `make install`
signs with a Developer ID when your keychain holds one.

`security` is a program of its own, so the line `export` writes asks once too.

The boundary is the user account. Whatever runs as you can read what you can
read, here as in the startup files themselves. What the vault gives is that
the secret is in none of the places a tool stumbles on: not a file in the
repository, not one beside it, and not a command line.

### The Secret Service on Linux

The Secret Service is a desktop session service. Over SSH or in a container
there is usually no session bus and no secret daemon, and `monkeys` fails
saying so. Machines like that want a different mechanism, not this one.

## Profile

A profile is a named set of secrets.

Every secret `monkeys` remembers sits under one, as `<profile>/<KEY>`, and a
project's `.monkeys` file lists its keys under the profiles they belong to:

```monkeys
+foo
@test
DATABASE_URL
STRIPE_SECRET_KEY
OPENROUTER_API_KEY
```

The `@` line names the profile and the `+` line the namespace it sits in, so
these three are remembered as `foo.test/DATABASE_URL` and so on. The keys are the
project's and the secrets are yours. Everyone who clones the repository gets
the same profile and the same keys, and each of them fills their own vault.
That is why the file can be committed and a vault never has to be.

### The default profile

The first profile a `.monkeys` file mentions is the default, the one every
command uses in that project when none is given. Inside the checkout, `run`
takes only the command, `remember` writes under the profile, and `preview` with no
keys shows the file's keys:

```sh
monkeys run ./hello.sh
monkeys remember STRIPE_SECRET_KEY        # remembers foo.test/STRIPE_SECRET_KEY
monkeys preview
```

`list` shows the whole vault as blocks by profile, so you can see what each
one holds.

### Several profiles

A profile line can name several profiles, and a file can hold several blocks:

```monkeys
+foo
@test,production
DATABASE_URL
STRIPE_SECRET_KEY
@production
SENTRY_DSN
```

A profile's keys are those of every block that lists it: both profiles here
need `DATABASE_URL` and `STRIPE_SECRET_KEY`, and `production` also needs
`SENTRY_DSN`. The default is still the first, `test`, so production is
something you say.

A secret missing in one profile stops only that profile, and only when it is
used: `production` can be half filled while `test` runs. `doctor` shows the
whole picture.

### The usual names

A name is yours to choose, and `monkeys` never checks one against a list.
These four are what projects tend to mean, and a name the reader already
knows needs no explanation:

```monkeys
+foo
@test,staging,production
DATABASE_URL
@production
SENTRY_DSN
@personal
OPENROUTER_API_KEY
```

`test` holds the keys that can leak without anyone being woken, `production`
the real ones, and `staging` a deployment that is not production, for the
projects that have one.

`test` goes at the top, and goes there even when it arrives after the others,
unless whoever asked for it says where it belongs. The first profile is the
one a command takes when none is given, so the default is the harmless one
and production is something you say.

`personal` is a key each person holds their own copy of rather than one the
team shares, a seat on an API they pay for themselves. It belongs in the file
because the project needs it, so `doctor` names it in a fresh checkout, and
`pack` asks before a bundle carries it away. A key that is yours in every
project rather than in this one has no profile at all.

Write the names in full, not `prod` or `dev`. A prefix is enough to type, so
`@p` already reaches `@production`, and the file stays readable for whoever
did not write it.

### Choosing a profile

Any command takes a leading `@profile`, which picks another declared one. A
prefix that fits only one of them is enough, the way a short git hash is:

```sh
monkeys run @production ./deploy
monkeys remember @production SENTRY_DSN
monkeys run @prod ./deploy           # production, by its prefix
```

A profile the file does not declare is refused with the declared ones listed,
and a prefix that fits several is refused with those, so a typo never becomes
a new profile. A profile name is words of letters, digits, `_` and `-`,
joined by `.`, and the namespace supplies the part before the dot.

### No profile

A key remembered outside any project has no profile and needs no `@`. That is
where a secret that belongs to you rather than to a project lives, such as
the one a tool you start from anywhere reads:

```sh
monkeys remember ANTHROPIC_API_KEY
monkeys run ANTHROPIC_API_KEY claude
```

A project profile never reads from the keys with no profile. A key missing
in `@production` is missing there even when a copy with no profile exists,
so a project cannot quietly pick up a secret meant for another.

Inside a project every command is scoped to that project's profile, so the
keys with no profile are out of reach there: `monkeys run` reads `foo.test/`,
and `monkeys remember ANTHROPIC_API_KEY` would write `foo.test/ANTHROPIC_API_KEY`.
A bare `@` means no profile. It sets the project file aside, so keys are
given again, and reaches those keys without leaving the directory:

```sh
monkeys run @ ANTHROPIC_API_KEY claude
monkeys remember @ ANTHROPIC_API_KEY
monkeys preview @ ANTHROPIC_API_KEY
```

It is the same secret either way; the `@` only says which profile to look in
when a file would otherwise decide.

## Namespace

A namespace is the part of a profile's name that belongs to the project.

The `+` line of a `.monkeys` file sets it, and every `@` line in that file is
read with it in front. In a file that starts with `+foo`, `@test` is the
profile `foo.test`, and its secrets sit at `foo.test/DATABASE_URL`.

### What it is for

Two projects that both call a profile `test` would otherwise share
`test/DATABASE_URL`. With a namespace each keeps its own, since
`bar.test/DATABASE_URL` is another secret, and `list` shows the two under
separate profiles.

### Where it is written

Once, in the file. It is the same in every clone and needs no git remote or
directory name to agree with. A namespace takes letters, digits, `_`, `-` and
`.`, usually the repository's name; a group that publishes several projects
can use reverse domain name notation, as in `+dev.eastriver.foo`.

### Referring to a profile

Inside the project the namespace is never typed. A profile is `@test` or
`@production`, and the file supplies the rest. The full name works from
anywhere, since it is only the profile's name; inside a project, a dotted
name the file does not declare is read as another project's:

```sh
monkeys run @production ./deploy          # inside foo
monkeys preview @foo.production           # from anywhere
monkeys fill @bar.test --with @foo.test   # across projects
```

### Without one

A file with no `+` line names its profiles as written, so `@test` there is
the profile `test`, remembered as `test/DATABASE_URL`, and a second project that
also says `@test` would share it.

## .monkeys

A `.monkeys` file is a project's list of the environment variables it needs,
kept next to the code and committed with it.

It is `.env.example` with the secrets left out: every key the program reads,
and the values that were never secret. Commit it. The name is the whole of
it, the way `.env` is: nothing comes before the dot, so `.monkeys` is the
file's name rather than an extension on some other name.

### Format

```monkeys
+foo
@test,production
DATABASE_URL
STRIPE_SECRET_KEY
@production
SENTRY_DSN
PORT=80
```

| line | meaning |
| --- | --- |
| `+foo` | the namespace, first and at most once |
| `@test,production` | opens a block for one profile or several |
| `DATABASE_URL` | a key whose secret is in the vault, for every profile of the block above it |
| `PORT=80` | a key with its value set right here, kept in the file and never in the vault |
| `# ...` | a comment |

The first profile mentioned is the default. Three things are refused, with
the line quoted: a key listed twice for one profile, a line that comes before
any `@` line, and a name that is not a key.

### Values

A line with `=` is a value: everything after the `=`, kept as it is, with no
quoting, no `${OTHER}` expansion and no second line. That is the part of the
dotenv grammar every library agrees on, and anything else is refused with its
line number rather than read one library's way. A value belongs to every
profile of the block above it, so one that differs by profile goes in that
profile's own block:

```monkeys
@test,production
DATABASE_URL
@test
PORT=3000
@production
PORT=80
```

For one profile a key is a secret or a value, never both; the second line is
a duplicate and is refused.

### Where it is looked for

From the current directory upward, nearest first, stopping at the root of the
git checkout, so a file above the checkout is never read. Outside a checkout
only the current directory counts.

A checkout with no file of its own, such as a worktree on a branch cut before
the file was committed, reads the one on the default branch: `origin/HEAD`,
then `main`, then `master`. That file is only read. A command that would
change it says so and changes nothing, the vault included, because the change
belongs on the branch that has the file.

Where no file is found either way the commands take keys on the line, as they
do anywhere else.

### What it replaces

The [twelve-factor](https://12factor.net/config) habit of a `.env` that is
never committed, a `.env.example` that lists the same keys again by hand, and
a `.gitignore` line that keeps the two apart. `.monkeys` is one file, it is
committed, and the secrets are somewhere a repository cannot reach.

### Who writes it

You, or `unpack`, which writes it at the root of the checkout from a bundle;
`remember --public` adds a value line, and `eat` fills it from a `.env`. `doctor`
reads it whole and says what each profile still lacks.

## *.monsecrets

A `.monsecrets` file is one or more profiles, their keys and their secrets,
encrypted together so they can be handed to someone.

`pack` writes one, `a.monsecrets` unless you name it, and `unpack` reads it.
That is the only way a secret leaves the vault.

### Format

Two lines of text:

```
monkeys bundle 1 scrypt 17 8 1
<salt and sealed bytes, base64>
```

The first line names the format and the scrypt cost the key was derived
with, log2 N, r and p. A bundle therefore keeps opening after the default
cost rises. The
second is the salt followed by the sealed bytes, in
base64. Inside, the bundle keeps the
shape of the `.monkeys` file, namespace line and blocks, so `unpack` can write
the file back and remember each secret under its profile. The `KEY=value` lines of the
packed profiles follow, after a line that says `values`, and `unpack` writes
them back as lines. A bundle without that line was written before values
existed, and opens too.

### Security

The sealed bytes are
[ChaCha20-Poly1305](https://en.wikipedia.org/wiki/ChaCha20-Poly1305), the
AEAD of [RFC 8439](https://www.rfc-editor.org/rfc/rfc8439) that TLS 1.3,
WireGuard and OpenSSH use. A bundle that has been altered fails to open rather than opening
wrong, and a wrong passphrase fails the same way.

The key is derived from the passphrase with
[scrypt](https://en.wikipedia.org/wiki/Scrypt) ([RFC
7914](https://www.rfc-editor.org/rfc/rfc7914)) and a fresh 16-byte salt each
time, at N = 2^17, r = 8, p = 1. Deriving it costs 128 MiB of memory and a fraction of a
second, once for `pack` and once for `unpack`; that memory is what keeps a
guess from being cheap to run in parallel. The passphrase is the weakest part,
so it goes by another route than the file.

A header that asks for a cost outside a fixed range is refused before any
work is done, so a crafted file cannot make `unpack` run for hours.

### Sharing one

The file is safe to send over whatever you already use, and the passphrase
goes another way. `unpack` deletes the bundle once it has done its job; `pack`
writes it to `/tmp`, outside any repository. [pack](#pack) and
[unpack](#unpack) are the two halves. A bundle written before a
`move` still carries the old name, and unpacks to it.

### If one is committed

A bundle has no reason to be in a repository, and `.monkeys` needs no ignore
rule, since it is meant to be committed. If a bundle is committed by mistake
anyway, what leaked is a sealed file, and the passphrase it was sealed with is
the only thing standing in the way. That passphrase cannot be changed after
the fact: the copy that leaked stays readable by whoever guesses the one it
already carries, and scrypt only makes each guess cost about 128 MB.

Take the file out of the repository, and out of its history if it was pushed.
Then rotate the secrets it held, the way you would for any secret that has
been somewhere it should not be. A new passphrase protects the next bundle,
never the one that leaked.

# How it works

A name, a secret and a command sit in three different places. Which one a
thing is in decides who can read it.

| | holds | who can read it |
| --- | --- | --- |
| your repository | `.monkeys`: the key names, and the values that were never secret | anyone with the repository |
| this machine | the vault: the secrets themselves | you, and whatever runs as you |
| one command | both, in its environment | that command, while it runs |

### What each command moves

| | from | to |
| --- | --- | --- |
| `remember` | a prompt | the vault, and the name into `.monkeys` |
| `run` | the vault | one command's environment |
| `export` | — | a lookup line for your shell |
| `pack` · `unpack` | the vault | an encrypted file, and back |
| `forget` · `drop` | the vault | gone |

Nothing moves a secret to your screen, which is why there is no `get`.

### What run does

```mermaid
sequenceDiagram
    autonumber
    participant You
    participant monkeys
    participant Vault
    participant Command
    You->>monkeys: monkeys run ./deploy
    monkeys->>Vault: the keys .monkeys lists
    Vault-->>monkeys: their secrets
    monkeys->>Command: fork, exec, secrets in its environment
    Command-->>monkeys: stdout and stderr
    monkeys-->>You: the same, secrets swapped for [redacted KEY]
```

Nothing reaches the command line, so your shell history and the process table
see key names at most. The parent stays in front to read the output, and
carries the command's exit status and signals back as its own.

### What comes back

```sh
monkeys run OPENROUTER_API_KEY sh -c 'echo "key=$OPENROUTER_API_KEY"'
```

> ```
> key=[redacted OPENROUTER_API_KEY]
> ```

Only what could still be the start of a secret is held back, so output is not
buffered. A file the command opens itself never passes through `monkeys`.

### The vault, and what it is not

A secret is one keychain item on macOS, filed under the service `monkeys`, and
one Secret Service item on Linux. `monkeys` keeps nothing of its own anywhere,
so there is no database to back up or leak.

Anything running as you can read that vault, the same way it can read your
shell startup files. This takes secrets out of the repository, not out of
reach; the [caveats](#caveats) say where that line falls.

# Commands

`forget` and `drop` ask before the vault loses anything, since nothing else
holds a secret, so both want a terminal.

Every command takes a leading `@profile`, one the file declares;
`@namespace.profile` reaches a profile from anywhere, and a bare `@` means no
profile. Where several keys or profiles go, they are joined
with commas, `DATABASE_URL,STRIPE_SECRET_KEY` and `@test,production`, so one
word is one list. Giving no key means every key for `preview` and `export`, or the
project's keys inside a project. `run` asks to be told, since the keys are how
it knows what to check for and what to leave out.

Output is coloured only when it is going to a terminal, and never for
`export`, whose output a shell reads. `NO_COLOR` turns colour
off, `CLICOLOR_FORCE` turns it on for a pipe, and an empty value for either
counts as unset.

`run`, `export` and `pack` each check every key before doing anything, so a
key you never remembered stops them with nothing done. A command cannot start with
half of its secrets, a startup file cannot ask for a secret that is not there,
and a bundle cannot carry half of a profile.

## remember

Add a secret to the vault, or a value to `.monkeys`.

```sh
monkeys remember [@profile] <KEY> [--clipboard]
monkeys remember --public [@profile] <KEY> [--clipboard]
monkeys remember [@profile] [--all]
```

Reads a secret and remembers it under the key. On a terminal it prompts, and what
you paste is not echoed:

```sh
monkeys remember OPENROUTER_API_KEY
```

> ```
> secret:
> remembered OPENROUTER_API_KEY
> give it to a command with:
>   monkeys run OPENROUTER_API_KEY <command>
> ```

`--clipboard` takes the secret from the clipboard instead, through whichever
tool the desktop has, `pbpaste`, `wl-paste`, `xclip` or `xsel`, so a key
copied from a provider's console goes straight in:

```sh
monkeys remember GITHUB_TOKEN --clipboard
```

> ```
> remembered GITHUB_TOKEN
> give it to a command with:
>   monkeys run GITHUB_TOKEN <command>
> ```

When standard input is not a terminal, the secret is read from there, which
is how a script remembers one:

```sh
cat token.txt | monkeys remember GITHUB_TOKEN
```

Inside a project the key is remembered under the project's profile, so `monkeys
remember STRIPE_SECRET_KEY` there writes `foo.test/STRIPE_SECRET_KEY`. A leading
`@profile` picks another, `@namespace.profile` one of another project, and a
bare `@` no profile:

```sh
monkeys remember @production DATABASE_URL
```

> ```
> secret:
> remembered foo.production/DATABASE_URL
> give it to a command with:
>   monkeys run <command>
> ```

A key you already remembered is replaced, and nothing says so.

### What it writes into .monkeys

A key the project does not list is added to it, under the profile the secret
went to, so the command that needs it can find it:

```sh
monkeys remember STRIPE_SECRET_KEY
```

> ```
> secret:
> remembered foo.test/STRIPE_SECRET_KEY
> listed STRIPE_SECRET_KEY in .monkeys for @test
> ```

In a git checkout with no `.monkeys` at all, the first `remember` makes one at
the root of the checkout, named after that directory, with `test` as its first
profile:

```sh
monkeys remember DATABASE_URL
```

> ```
> made .monkeys for +foo @test
> remembered foo.test/DATABASE_URL
> listed DATABASE_URL in .monkeys for @test
> ```

The file is made only once there is a secret to put in it, so an answer you
abandon at the prompt leaves nothing behind. Outside a checkout nothing is
made and the key keeps no profile, and a bare `@` says so from inside one.

A profile the file does not declare is refused rather than added, since a
mistyped one would otherwise become a profile of its own.

### Walking a profile

With no key, inside a project, `remember` walks the profile's keys in the order the
file lists them and prompts for each one that has no secret yet. An empty
answer skips that key. At the end it shows the profile the way `doctor` does,
with what each key got, and exits non-zero while anything is still missing:

```sh
monkeys remember
```

> ```
> DATABASE_URL:
> STRIPE_SECRET_KEY:
> @test  default
>   ✓ DATABASE_URL  remembered
>   ✗ STRIPE_SECRET_KEY  skipped
> ```

A leading `@profile` walks that profile instead, one at a time; `@test,production`
is refused. `--all` prompts for every key, and a key that already has a secret
shows its mask in the prompt so Enter keeps it:

```sh
monkeys remember --all
```

> ```
> DATABASE_URL (al...e 18, Enter keeps):
> STRIPE_SECRET_KEY (br...e 18, Enter keeps):
> @test  default
>   ✓ DATABASE_URL  kept
>   ✓ STRIPE_SECRET_KEY  remembered
> ```

The walk reads from the terminal only. With standard input piped, or with
`--clipboard`, it says so and remembers nothing; both of those take one key.
Outside a project there is nothing to walk, and `monkeys remember` with no key says
a key is required.

Remembering is a human's job. An agent that types a secret puts it in its own
context before it reaches the vault, so the skill tells it to ask instead.

### --public

`--public` writes a value that is not secret, `PORT=3000` and the like, into
`.monkeys` as a `KEY=value` line instead of into the vault. It prompts with
`value:` and echoes what you type, since the value will be committed, and
from a pipe it reads the value the same way:

```sh
echo 3000 | monkeys remember --public PORT
echo 80 | monkeys remember --public @production PORT
```

> ```
> wrote PORT=3000 to .monkeys for @test
> wrote PORT=80 to .monkeys for @production
> ```

The line goes into the block that is that profile's alone, or into a new
block at the end. A value the profile already has is replaced in place. A
value the file sets for several profiles together is refused, since replacing
it would change them all; split the block by hand.

`--public` only works inside a project, because a value has nowhere to go
without `.monkeys`. It refuses a key the file lists as a secret for the
profile, and plain `remember` refuses a key the file holds as a value, each naming
the other form:

```sh
monkeys remember PORT
```

> ```
> monkeys: PORT is a value in .monkeys for @test; replace it with monkeys remember --public PORT, or forget it first
> ```

Turning one into the other is `forget` and then `remember`, so a secret
becomes a committed line by accident.

## forget

Remove a secret from the vault.

```sh
monkeys forget [@profile] <KEY>
monkeys forget @profile[,profile...]
monkeys forget +namespace
monkeys forget [@profile] --all --untracked
```

Deletes one secret from the vault, after asking, because nothing else holds
it. Inside a project the key is the project's; `@` reaches one with no profile
from there:

```sh
monkeys forget STRIPE_SECRET_KEY
```

> ```
> forget foo.test/STRIPE_SECRET_KEY, which nothing else holds. go ahead? [y/N] y
> forgot foo.test/STRIPE_SECRET_KEY
> ```

The question needs a terminal, so a script or an agent is refused rather than
answered for.

The `.monkeys` file is not touched: a project still lists the key, and
`doctor` reports it missing until someone remembers it again. To take the key
out of the file as well, see [drop](#drop).

A key that `.monkeys` holds as a value for the profile has its line deleted
instead, since the file says which of the two it is:

```sh
monkeys forget API_URL
```

> ```
> forgot API_URL from .monkeys for @test
> ```

That one is not asked about, since the line lives in a file git can give
back. A value the file sets for several profiles together is refused, the way
`remember --public` refuses it.

A profile on its own, with no key, forgets every secret remembered under it, and a
comma list forgets several. The names are all resolved before anything is
deleted, so a typo in the second name leaves the first untouched:

```sh
monkeys forget @test,production
```

> ```
> forget 5 secrets under @test, @production, which nothing else holds. go ahead? [y/N] y
> forgot @test: DATABASE_URL, STRIPE_SECRET_KEY
> forgot @production: DATABASE_URL, SENTRY_DSN, STRIPE_SECRET_KEY
> ```

A namespace forgets every profile under it, declared in a file or not:

```sh
monkeys forget +foo
```

> ```
> forget 5 secrets across 2 profiles under +foo, which nothing else holds. go ahead? [y/N] y
> forgot @foo.production: DATABASE_URL, SENTRY_DSN, STRIPE_SECRET_KEY
> forgot @foo.test: DATABASE_URL, STRIPE_SECRET_KEY
> ```

Neither form touches `.monkeys`: a project still declares the
profile, and `doctor` reports every key of it missing. A bare `@` is no profile
and is refused, so the secrets with no profile go one key at a time.

### --all --untracked

Remove only the vault keys that `.monkeys` does not track in this namespace:

```sh
monkeys forget --all --untracked
monkeys forget @test --all --untracked
```

Without `@profile`, this includes keys under profiles no longer declared in the
file. With `@profile`, it selects only that profile. The command lists the keys
and asks once before deleting them. Keys listed in `.monkeys`, public values,
other namespaces and keys with no profile are preserved. The file stays as it
is. Both flags are required, and a `.monkeys` file must be in reach.

When the file has no namespace, only its declared profiles are checked.

## drop

Remove a key from `.monkeys` and forget its secret.

```sh
monkeys drop [@profile] <KEY>
```

Forgets the secret and takes the key out of `.monkeys`, which is `forget`
followed by the edit you would otherwise make by hand:

```sh
monkeys drop STRIPE_SECRET_KEY
```

> ```
> forget foo.test/STRIPE_SECRET_KEY, which nothing else holds, and unlist it from .monkeys. go ahead? [y/N] y
> forgot foo.test/STRIPE_SECRET_KEY
> unlisted STRIPE_SECRET_KEY from .monkeys for @test
> ```

Where the vault has nothing under that key, the key is still unlisted, which
is how the `✗` that `doctor` shows for a key nobody has is cleared:

```sh
monkeys drop DATABASE_URL
```

> ```
> unlist DATABASE_URL from .monkeys, which the vault has nothing under. go ahead? [y/N] y
> unlisted DATABASE_URL from .monkeys for @test
> ```

The question says which of the two will happen, and both are checked before
either runs, so a key the file cannot unlist is refused with its secret still
in the vault.

A key the file holds as a value is deleted from the file, the same as
`forget`, since for a value the line is the whole of it.

A profile with no key is refused. Emptying a profile's vault is `forget`,
which leaves the file alone, because one person clearing their own machine
does not decide what the project needs:

```sh
monkeys drop @test
```

> ```
> monkeys: drop takes one key: monkeys drop @test <KEY>. to empty a profile's vault, monkeys forget @test
> ```

Outside a project, with no file to edit, `drop` is `forget`.

## move

Move a key, a profile or a namespace, in the vault and in `.monkeys`.

```sh
monkeys move [@source] <KEY> [@target] [NEW_KEY]
monkeys move @old @new
monkeys move +old +new
```

A key can move to another profile, take a new name, or both:

```sh
monkeys move OLD_KEY NEW_KEY
monkeys move @test DATABASE_URL @production
monkeys move @test OLD_KEY @production NEW_KEY
monkeys move @ API_KEY @test
monkeys move @test API_KEY @
```

The source defaults to the project's first profile, just as `remember` and
`forget` do. Outside a project it defaults to the keys with no profile. Without a
target profile, the key stays in its source profile. Without a new key name,
it keeps its name. A bare `@` selects the keys with no profile on either side.
A target key or public value that already exists is refused.

The reachable project's declaration moves with the key. A public `KEY=value`
entry can move between declared profiles too. A key in a block shared by several
profiles must have that block split before it can move for one profile alone.
Files in other projects are edited separately.

Moving a profile transfers every secret under it to the new name. Inside a project
it rewrites the `@` lines of `.monkeys` to match, so the vault and the file change
together. Old name first, then new, the way `mv` reads:

```sh
monkeys move @staging @preview
```

> ```
> moved @staging to @preview: DATABASE_URL, STRIPE_SECRET_KEY, SENTRY_DSN
> rewrote .monkeys: @staging is now @preview
> ```

Inside a project both names are the project's, and a prefix that fits only one
declared profile is enough for the old one, `@stag`. From anywhere, the full name works: `monkeys move @foo.staging
@foo.preview` moves the secrets and touches no file, since none is in reach.
A project that still names the old profile then has `doctor` report it
missing, until the file is edited or the name moved back.

A namespace is renamed the same way, for every profile under it, declared in
the file or not, and the `+` line of the project's file with it:

```sh
monkeys move +foo +bar
```

> ```
> moved @foo.production to @bar.production: DATABASE_URL, STRIPE_SECRET_KEY, SENTRY_DSN
> moved @foo.test to @bar.test: DATABASE_URL, STRIPE_SECRET_KEY
> rewrote .monkeys: +foo is now +bar
> ```

A target that already holds a key is refused, so a move never merges two
profiles:

> ```
> monkeys: @preview already holds DATABASE_URL; a move never merges two profiles. To merge, fill @preview --with @staging, then forget what @staging still holds
> ```

The vault has no transaction, so the secrets move one key at a time, remembered
under the new name and then removed from the old. At the first failure it
stops, names the keys that moved and the one that did not, and leaves the file
as it was; the file is rewritten only after the last key moved. A bare `@` selects
the keys with no profile when moving one key; it cannot name a whole profile
to move. No secret is printed.

## run

Run a command with the secrets it needs, and nothing else.

```sh
monkeys run [@profile] <KEY[,KEY...]> <command> [argument...]
monkeys run [@profile] --all <command> [argument...]
monkeys run <command> [argument...]                    # inside a project
```

Runs the command with the named secrets in its environment, and nowhere else.
Nothing in the line holds a secret, so nothing you write can spill one:

```sh
monkeys run OPENROUTER_API_KEY ./hello.sh
monkeys run OPENROUTER_API_KEY,GITHUB_TOKEN ./deploy
```

Once every secret is in place, `run` stays between the command and your
terminal to redact what comes back; the exit status and the signals are the
command's own.

### Inside a project

In a directory that holds a `.monkeys` file, or below it within the checkout,
`run` takes only the command and reads the file's keys from the default
profile. A leading `@profile` picks another declared one:

```sh
monkeys run ./hello.sh
monkeys run npm run dev
monkeys run @production ./deploy
```

A key the file already lists is refused rather than run as a program:

```sh
monkeys run STRIPE_SECRET_KEY ./hello.sh
```

> ```
> monkeys: ~/foo/.monkeys already lists STRIPE_SECRET_KEY for @test
> inside a project, run takes only the command: monkeys run <command>
> ```

The profile's values, the `KEY=value` lines of the file, go into the
environment as well, straight from the file:

```sh
monkeys run sh -c 'echo "$API_URL on port $PORT"'
```

> ```
> http://localhost:8080 on port 3000
> ```

### --all

`--all` means every key remembered under the profile, listed or not, for when you
would rather not say which:

```sh
monkeys run --all ./bench
```

Outside a project that is every key with no profile, which is the wide end
of the tool. Name the keys the command reads when you can.

### When a secret is missing

A key you have not remembered a secret for stops the run before it starts, and
says where it is missing from:

```sh
monkeys run OPENROUTER_API_KEY,SUPER_SECRET ./hello.sh
```

> ```
> monkeys: SUPER_SECRET is not remembered yet
> nothing happened. a human types the secret into:
>   monkeys remember SUPER_SECRET
> then try again.
> ```

Inside a project the message names the profile, and the `remember` it asks
works from any directory:

> ```
> monkeys: STRIPE_SECRET_KEY is not remembered yet in @foo.test
> nothing happened. a human types the secret into:
>   monkeys remember @foo.test STRIPE_SECRET_KEY
> then try again.
> ```

That message is written to be passed on. An agent that meets it knows which
keys are missing, that nothing happened, and what a human has to type.

### Where the variable is expanded

`run` sets the variable for the command it starts, so that command is what
expands it. Written into the `monkeys run` line itself, your own shell gets
there first, and yours does not have the secret:

```sh
monkeys run OPENROUTER_API_KEY curl -H "Authorization: Bearer $OPENROUTER_API_KEY" ...
# sends: Authorization: Bearer
```

Single quotes pass the text through untouched, so a shell that `run` starts is
the one that expands it:

```sh
monkeys run OPENROUTER_API_KEY sh -c 'curl -H "Authorization: Bearer $OPENROUTER_API_KEY" ...'
```

A script file works for the same reason, and reads better.

A variable the shell already exported is overridden for that command. Keys
you leave out are passed through untouched.

### What comes back

A remembered secret in the command's output comes back as `[redacted KEY]`:

```sh
monkeys run OPENROUTER_API_KEY sh -c 'echo "key=$OPENROUTER_API_KEY"'
```

> ```
> key=[redacted OPENROUTER_API_KEY]
> ```

That is the reflex this exists for. An agent that meets an empty variable will
`echo` it, and now the echo says which secret was there and nothing else. The
output is streamed as it arrives. A byte is held back only while it could
still be the start of a secret, and on a terminal that moment shows as `*`
until the next byte settles it.

It catches the secret written whole or in pieces, on stdout or stderr. It
does not catch the secret transformed, so `echo $KEY | base64` goes through;
this is for the reflex, not for someone trying.

A short secret is redacted wherever it appears, so remember secrets here and keep
`PORT=3000` as a value line in `.monkeys`, which is public and passes through
untouched.

### Writing a secret into a file

A file that has to end up with the secret in it takes the redirect inside the
command, where the secret goes from the child straight into the file and
never passes `monkeys`:

```sh
monkeys run OPENROUTER_API_KEY sh -c 'envsubst < template > config'
```

> ```
> token = <the secret>
> ```

Written the way a shell reads it first, with the redirect outside, the file
is `monkeys`'s own output and the redaction lands in it:

```sh
monkeys run OPENROUTER_API_KEY envsubst < template > config
```

> ```
> token = [redacted OPENROUTER_API_KEY]
> ```

A secret leaves through a command's own file descriptor, so which side of
`monkeys` the redirect sits on decides what the file gets.

### A shell with a profile

`monkeys run @production zsh` hands a whole profile to one shell, which forgets it on
exit. That is the way to work with a profile for a while without putting it
into every shell you open.

## pack

Seal a profile's secrets into one encrypted file.

```sh
monkeys pack [name] [--path DIR] [--ask] [--open] [--only [KEY[,KEY...]] [@profile[,profile...] [KEY[,KEY...]]]...]
```

Writes a project's secrets as one encrypted file, the only way they leave the
vault. With no arguments it takes every profile the `.monkeys` file declares:

```sh
monkeys pack
```

> ```
> wrote /tmp/a.monsecrets: +foo @test,production @production, 5 secrets
> copied its passphrase to your clipboard; send that the other way
> ```

Send the file however you like, and paste the passphrase into something else:
a different messenger, a call, a password manager's share. Both down one
channel is one leak away from being no encryption at all.

The file goes to `/tmp`, which is never inside a repository, and the message
shows the path. `--path` names a directory to write into, and the name before
`--only` names the file inside it. A name carries no directory of its own:

```sh
monkeys pack --path ~/Desktop
monkeys pack for-sam --path ~/Desktop
```

Inside a git checkout it asks first, since a bundle a commit can reach is a
bundle that can be published:

> ```
> a bundle into ~/code/shop/a.monsecrets, where a commit can take it. go ahead? [y/N] y
> ```

> ```
> wrote ~/Desktop/a.monsecrets: +foo @test,production @production, 5 secrets
> wrote ~/Desktop/for-sam.monsecrets: +foo @test,production @production, 5 secrets
> ```

It carries the project's namespace, each profile's name, the keys the project
lists for it, and their secrets, sealed with ChaCha20-Poly1305 under a key
scrypt derives from the passphrase. The values of the packed profiles, the
`KEY=value` lines, ride along whole, since they are public anyway, and the
message counts them:

> ```
> wrote /tmp/a.monsecrets: +foo @test, 2 secrets, 2 values
> ```

One bundle carries one project. The file is safe to send over whatever you
already use; the passphrase goes another way.

`--open` then reveals the file, in Finder with the file selected, or its
folder through `xdg-open` on Linux, since the next thing to do with a bundle
is to drag it somewhere.

A pack with a secret still missing refuses, since a bundle that fills half a
profile is a bug for whoever receives it.

A bundle that would carry `@personal` asks first, whichever way that profile
got in. The name is the convention for a key each person holds their own copy
of, so handing one over is a decision rather than a step, and the question
takes the word instead of a letter:

> ```
> @personal is yours, not the team's, and a bundle hands it to whoever opens it. [UNDERSTOOD/N] UNDERSTOOD
> ```

Anything else answers no, and so does a pack with nobody to answer: the
question needs a terminal, which is what keeps a script from bundling one
person's keys by itself. The refusal names the profiles the file has besides
it:

> ```
> monkeys: nothing written. to pack the rest: monkeys pack --only @test,production
> ```

### The passphrase

Everything else about the file is fixed, so the passphrase is the only part
anyone decides, and the only part an attacker can work on. A stolen bundle is
guessed at offline for as long as someone cares to, and scrypt's 128 MB a
guess buys time only in proportion to how hard the passphrase is to guess.

So `pack` does not ask for one. It draws 24 random characters and puts them on
your clipboard, and they are never printed, never stored and never in your
shell history. Paste that into whatever carries it to the other person, which
is not the thing carrying the file.

A clipboard manager keeps what it is given, sometimes for good. If you run
one, take the passphrase out of its history once the bundle has arrived.

`--ask` prompts for one you choose instead, and leaves the clipboard alone:

```sh
monkeys pack --ask
```

> ```
> passphrase:
> again:
> wrote /tmp/a.monsecrets: +foo @test,production @production, 5 secrets
> ```

Choose that way and the file is only as good as the passphrase, so take one
from a password manager rather than thinking one up. On a machine with no
clipboard tool `pack` says so and asks, since a file whose passphrase nobody
has is a file nobody can open. The passphrase is still read from standard
input when it is not a terminal, so a script that pipes one keeps working.

### --only

`--only` says which profiles and keys, and reads the way the file is written.
A `@profile` opens a block, `@a,b` opens one for several profiles at once, and
the keys after it belong to every profile in that block. A block with no keys
after it goes whole; keys before any `@` come from the default profile, the
first the file mentions. That is how a teammate gets test and never
production, or one key on its own:

```sh
monkeys pack --only @test
monkeys pack shared --only @test @production
monkeys pack --only DATABASE_URL
monkeys pack --only @test,production DATABASE_URL
monkeys pack --only @test DATABASE_URL @production SENTRY_DSN
```

> ```
> wrote /tmp/a.monsecrets: +foo @test, 2 secrets
> wrote shared.monsecrets: +foo @test @production, 5 secrets
> wrote /tmp/a.monsecrets: +foo @test, 1 secret
> wrote /tmp/a.monsecrets: +foo @test,production, 2 secrets
> wrote /tmp/a.monsecrets: +foo @test @production, 2 secrets
> ```

The bundle keeps that shape, block for block, and `unpack` writes it back as
the project file. The path goes before `--only`, which takes the rest of
the line. A key a profile does not list is refused rather than left
out.

Outside a project, `--only @foo.test` names a profile in full, and a bundle
made there carries its profiles under their full names, with no `+` line.

The passphrase is read from standard input when it is not a terminal, for the
rare script that needs to.

## unpack

Open an encrypted file into your own vault.

```sh
monkeys unpack <name> [directory] [--keep]
```

Reads a bundle, remembers its secrets in your vault under each profile, writes
the profiles and keys as a `.monkeys` file, and deletes the bundle:

```sh
monkeys unpack a
```

> ```
> passphrase:
> wrote .monkeys: +foo @test,production @production, 3 keys
> remembered foo.test/DATABASE_URL, foo.production/DATABASE_URL, foo.test/STRIPE_SECRET_KEY, foo.production/STRIPE_SECRET_KEY
> remembered foo.production/SENTRY_DSN
> removed a.monsecrets
> ```

`<name>` is the bundle, with or without its `.monsecrets` suffix; a path works
too. The bundle is deleted only once every secret is remembered and the file is
written. By then it has done its job, and a copy left behind is one more
thing to lose. `--keep` leaves it where it was, for a bundle you are handing
on to someone else, and the run says nothing about removing it:

```sh
monkeys unpack a --keep
```

> ```
> passphrase:
> wrote .monkeys: +foo @test,production @production, 3 keys
> remembered foo.test/DATABASE_URL, foo.production/DATABASE_URL
> remembered foo.production/SENTRY_DSN
> ```

The file goes at the root of the git checkout, the way `.gitignore` sits at
the root, so `monkeys run` works from any directory in it. Outside a checkout
it goes in the current directory, and a second argument names the directory
outright. When a `.monkeys` file is already there, `unpack` leaves it alone except for
one block at the end, carrying the keys the file does not yet list, grouped
the way the bundle groups them. A file that names another
project on its `+` line refuses the bundle, and the bundle stays.

A bundle that carries values writes them into `.monkeys` as `KEY=value` lines
the same way, adding the ones the file does not have and leaving the ones it
has:

> ```
> wrote .monkeys: +foo @test, 2 keys
> wrote .monkeys: 2 values
> remembered foo.test/DATABASE_URL, foo.test/STRIPE_SECRET_KEY
> removed /tmp/a.monsecrets
> ```

The passphrase is read from standard input when it is not a terminal.

## eat

Move the `.env` files here into the vault and `.monkeys`.

```sh
monkeys eat [+namespace] [@profile] [--public KEY[,KEY...]]
```

Moves a project's dotenv files into monkeys and deletes them. It reads `.env`,
`.env.local` and every `.env.<profile>` in the current directory, and asks one
question per key: secret or public. A secret's key goes into `.monkeys` and
its secret into the vault. A public one goes into `.monkeys` as it stands.

> ```
> namespace, +name (Enter for none): foo
> profile for .env [test]:
> DATABASE_URL @test,@production  [s]ecret or [p]ublic? s
> STRIPE_SECRET_KEY @test  [s]ecret or [p]ublic? s
> PORT @test,@production  [s]ecret or [p]ublic? p
>   public PORT=3000 for @test, into .monkeys
>   public PORT=80 for @production, into .monkeys
> SENTRY_DSN @production  [s]ecret or [p]ublic? s
> wrote .monkeys: +foo @test,production @test @production, 3 keys
> remembered @test: DATABASE_URL, STRIPE_SECRET_KEY
> remembered @production: DATABASE_URL, SENTRY_DSN
> public @test: PORT
> public @production: PORT
> removed .env, .env.production
> a .gitignore line for them is dead now and can go; monkeys leaves that file alone
> ```

That run started from `.env` and `.env.production` and left one file behind:

```monkeys
+foo
@test,production
DATABASE_URL
@test
STRIPE_SECRET_KEY
PORT=3000
@production
SENTRY_DSN
PORT=80
```

The files map to profiles the way dotenv already names them: `.env` and
`.env.local` go to the default profile, the first one in `.monkeys` when
the file exists and otherwise the one asked for, and `.env.<name>` goes to
`@<name>`. A key found in several files gets each file's value under that
file's profile, and its line in `.monkeys` lists those profiles together.
`.env.example` is left alone, since `.monkeys` is what it was standing in
for.

The secret answer is the default; Enter takes it. The value is shown only
for a public answer, since that is the moment it becomes a line in a file
that gets committed. A key the project already holds, in the vault or in `.monkeys`, asks before
it is replaced, and Enter keeps what is there. Answered as the other kind, it
is kept without asking and named in the summary, since turning one kind into
the other is
`forget` and then `remember`.

The grammar is the part of dotenv every library reads the same way: `KEY=value`,
`export KEY=value`, a value in single or double quotes with the quotes
stripped, `#` comment lines and blank lines. Three kinds of value are refused, with their file and line: one that spans
lines, one that expands another variable with `${...}`, and an unquoted one
followed by a `#` comment. Nothing is written until every file parses:

> ```
> monkeys: .env:2: DATABASE_URL expands another variable; monkeys keeps a value as it is; nothing was written
> ```

When no `.monkeys` exists yet, `eat` asks for a namespace once, Enter for
none, and writes the file at the root of the git checkout, where `unpack`
writes it. When one exists, its `+` line and its profiles stand, and the
keys are added to it the way `unpack` adds them. The dotenv files are
deleted only after every secret is remembered and the file is written. The
`.gitignore` lines that kept them out of git are left for you, and the last
line says so.

### --public

`--public` names the keys that are not secret, which answers every question
before it is asked. Those keys become `KEY=value` lines and every other key
becomes a secret in the vault. An existing entry is kept, never replaced. Nothing is asked, so no terminal is needed and an agent can run it
on a project it finds:

```sh
monkeys eat +foo --public PORT
```

> ```
>   public PORT=3000 for @test, into .monkeys
>   public PORT=80 for @production, into .monkeys
> wrote .monkeys: +foo @test,production @test @production, 3 keys
> remembered @test: DATABASE_URL, STRIPE_SECRET_KEY
> remembered @production: DATABASE_URL, SENTRY_DSN
> public @test: PORT
> public @production: PORT
> removed .env, .env.production
> a .gitignore line for them is dead now and can go; monkeys leaves that file alone
> ```

The secrets go from the files into the vault without passing through whatever
ran the command. `+namespace` and `@profile` stand in for the two questions a
first run would otherwise ask; a project that already has a `.monkeys` file
takes both from it. Without `--public` there are questions to ask, so `eat`
refuses to run with its input piped and says which flag to use.

## poo

Write a `.env` that carries keys and no secrets.

```sh
monkeys poo [@profile] [--path DIR] [--open]
monkeys poo @profile --WITH_SECRETS [--EXPAND_DANGEROUSLY] [--path DIR] [--open]
```

Writes a `.env` carrying the same list `.monkeys` does: every secret's key on a
line of its own, and every public value as it already stands. A key with
nothing after it sets nothing, so the file satisfies whatever wanted one while
the secrets keep arriving through `run`.

```sh
monkeys poo
```

> ```
> wrote /tmp/monkeys-jn4u9q/.env for @test: 2 keys, 1 value
> ```

```
# monkeys' poo @test. read https://monk3ys.dev/poo
DATABASE_URL
STRIPE_SECRET_KEY
PORT=3000
```

It lands in `/tmp` unless you say otherwise, so nothing appears in a project
that did not ask for it. The header names the profile when the project declares
more than one, since that is the profile `run` has to be given to match.

### Why a key carries no value

A placeholder would be worse than nothing. The three things that read a `.env`
treat a bare key and a `KEY=x` differently, and only the bare key is safe in
all three:

| what reads it | `DATABASE_URL` | `DATABASE_URL=x` |
| --- | --- | --- |
| dotenv, so Vite, SvelteKit, Next | ignored, the environment's value stands | ignored, the environment's value stands |
| Docker Compose `env_file:` | taken from the host environment | `x` goes into the container |
| `set -a; . .env` | the environment's value survives | overwritten with `x` |

The bottom two rows are the reason. A placeholder reaches a container or a
shell as a real value, so the program starts and fails later, at the first
call that uses the key, where the cause is no longer obvious.

> [!IMPORTANT]
> If you maintain a framework, please make its loader read `.monkeys`, taking
> each key's value from the operating system's vault. Have it replace `.env`,
> or sit between `.env` and the process environment.

### --path

`--path` names the directory to write into, and the file inside it is always
`.env`:

```sh
monkeys poo --path .
```

> ```
> a .env into ~/code/shop/.env, where a commit can take it. go ahead? [y/N] y
> wrote ~/code/shop/.env for @test: 2 keys, 1 value
> ```

Anywhere inside a git checkout it asks first, because that is where a commit
can find the file. Answer anything but `y` and nothing is written. `--open`
shows whatever it wrote in the file manager, wherever that was.

A `.env` that poo did not write is left alone:

> ```
> monkeys: ~/code/shop/.env was not written by poo: monkeys eat it first, or move it aside
> ```

### --WITH_SECRETS

A tool that wants the values, not only the keys, takes them as vault lookups:

```sh
monkeys poo @production --WITH_SECRETS
```

> ```
> wrote /tmp/monkeys-QA6tuw/.env for @production: 3 lookups, 1 value
> ```

```
# monkeys' poo @production, vault lookups. read https://monk3ys.dev/poo
DATABASE_URL="$(security find-generic-password -s monkeys -a shop.production/DATABASE_URL -w)"
STRIPE_SECRET_KEY="$(security find-generic-password -s monkeys -a shop.production/STRIPE_SECRET_KEY -w)"
SENTRY_DSN="$(security find-generic-password -s monkeys -a shop.production/SENTRY_DSN -w)"
PORT=8080
```

That is the line `export` writes, so nothing of the secret is on disk and the
file is as safe to keep as the keys were. The profile has to be named: the
lookup carries one profile's stored name, and the wrong one resolves to the
wrong secret rather than to nothing.

What resolves it is a shell:

```sh
set -a; . ./.env; set +a
```

> ```
> DATABASE_URL=postgres://user:pa$$w0rd@host/shop
> ```

---

### --EXPAND_DANGEROUSLY

> [!WARNING]
> This is the one command that writes secrets, in the open, to a file. Nothing
> else in `monkeys` does. Reach for it only when the tool cannot run a lookup,
> and delete what it wrote when you are done.

A reader that parses the file without running anything gets the text of the
lookup instead of the secret. Vite, SvelteKit, Next and Compose all read a
`.env` this way:

> ```
> vite got: "$(security find-generic-password -s monkeys -a shop.production/DATABASE_URL -w)"
> ```

Only then is there reason to put the secrets themselves in a file, which is
what this flag does. It runs the lookups and writes what they return:

```sh
monkeys poo @production --WITH_SECRETS --EXPAND_DANGEROUSLY
```

> ```
> wrote /tmp/monkeys-01mjsu/.env for @production: 3 secrets, 1 value
> the secrets are in the open in that file; delete it when the deploy is done
> ```

```
# monkeys' poo @production, secrets in the open. delete this file. read https://monk3ys.dev/poo
DATABASE_URL="postgres://user:pa\$\$w0rd@host/shop"
STRIPE_SECRET_KEY="sk-demo-live"
SENTRY_DSN="https://key@sentry.example.com/1"
PORT=8080
```

It is a fallback for the place that takes no vault and no command, such as a
deploy dashboard that wants the variables pasted in. That is a person's errand,
so the flag wants a terminal and refuses a pipe:

> ```
> monkeys: --EXPAND_DANGEROUSLY leaves secrets in a file for a person to paste, so it needs a terminal
> ```

`--path` still works, and inside a git checkout the question is no longer one
letter:

> ```
> plain secrets into ~/code/shop/.env, where a commit can take them. not recommended. [UNDERSTOOD/N] UNDERSTOOD
> ```

A `$` inside a secret is written `\$`, which both a shell and dotenv read back
as one character, so a password like `pa$$w0rd` arrives whole. A secret holding
a quote or a backslash is refused instead, since no dotenv line carries those
back unchanged.

### @profile

A profile names which list to write, the way it does everywhere else:

```sh
monkeys poo @production
```

One file is written, never one per profile. Which profile a program runs under
is `run`'s to decide, and a second place to decide it is a second place to get
it wrong.

## fill

Give a profile the secrets another one already has.

```sh
monkeys fill @profile --with @profile
```

Gives the first profile the keys it lacks, taking the secrets from the second.
Two profiles of one project usually share most of their secrets, and the
second is filled from the first:

```sh
monkeys fill @production --with @test
```

> ```
> filled @production from @test: STRIPE_SECRET_KEY
> kept 1 @production already had
> still missing in @production: SENTRY_DSN
> ```

`fill` moves only the keys the target lacks and never touches a secret it
already holds, so it is safe to run twice. It names every key it moved, since
a production profile filled from test is a decision to see written down, and
it exits non-zero while anything is still missing. No secret is printed.

Inside a project the keys are the ones the file lists for the target;
elsewhere they are whatever the source holds. Either side may be another
project's profile, `@bar.test`, which is how a secret shared by two projects
is remembered once and copied.

## list

Show every key the vault holds, by profile.

```sh
monkeys list
```

Prints the whole vault in the shape of a `.monkeys` file, one block per
profile, with every profile under its full name and the keys with no profile
first, under a bare `@`:

```sh
monkeys list
```

> ```monkeys
> @
> ANTHROPIC_API_KEY
>
> @foo.production
> DATABASE_URL
> SENTRY_DSN
>
> @foo.test
> DATABASE_URL
> STRIPE_SECRET_KEY
> ```

Two profiles that share a block in a project's file appear here as two
blocks, since the vault holds a secret per profile. `list` reads the whole
vault, so it shows every project at once, and prints nothing when the vault
is empty.

## preview

Show a secret masked, never in full.

```sh
monkeys preview [@profile] [KEY[,KEY...]]
```

Answers the question you usually have, which is whether the right secret is in
there, without printing it:

```sh
monkeys preview
```

> ```
> GITHUB_TOKEN        gh...f 40
> OPENROUTER_API_KEY  sk...2 73
> ```

It shows the first two characters, the last one, and the length. A secret is
masked whole whenever fewer than five characters would stay hidden, so nothing
under eight characters long gives any of itself away:

```sh
monkeys preview SHORT_ONE
```

> ```
> SHORT_ONE  ... 6
> ```

A length and a two-character prefix are enough to tell a secret pasted whole
from one that lost a character on the way, or one provider's from another's.

With no keys, `preview` shows every key in the profile: those with no profile
outside a project, the file's keys inside one. A value line is shown as it
is, after the secrets, since it is public:

```sh
monkeys preview
```

> ```
> DATABASE_URL       po...t 29
> STRIPE_SECRET_KEY  sk...p 34
> PORT               3000
> API_URL            http://localhost:8080
> ```

A leading `@profile` shows another one the file declares, which is how you
tell a production secret from the test one that shares its key:

```sh
monkeys preview @production
```

> ```
> DATABASE_URL  po...p 43
> SENTRY_DSN    ht...9 44
> ```

## doctor

Show what a profile has and lacks.

```sh
monkeys doctor [--short]
```

Reads the whole `.monkeys` file and shows every profile with what it has and
lacks, in colour on a terminal. It exits non-zero while anything is missing:

```sh
monkeys doctor
```

> ```
> @test  default
>   ✓ DATABASE_URL
>   ✓ STRIPE_SECRET_KEY
> @production
>   ✓ DATABASE_URL
>   ✗ STRIPE_SECRET_KEY
>   ✗ SENTRY_DSN
> ```

A value line counts as present and is shown with its value:

> ```
> @test  default
>   ✓ DATABASE_URL
>   ✓ STRIPE_SECRET_KEY
>   ✓ API_URL=http://localhost:8080
> ```

A vault key in the project's namespace that `.monkeys` does not track is shown
with `-`, including keys under profiles no longer declared in the file:

> ```
> @test  default
>   ✓ DATABASE_URL
>   - OLD_API_KEY
> @retired
>   - SENTRY_DSN
> ```

These keys do not make `doctor` exit non-zero. `forget --all --untracked` removes
only these keys after confirmation. Without a namespace, `doctor` checks for
untracked keys only in the file's declared profiles.

### --short

`--short` says only what is wrong: one line per profile with a problem, and
nothing at all when there is none. That is the form to hand a script or an
agent:

```sh
monkeys doctor --short
```

> ```
> missing @production: STRIPE_SECRET_KEY,SENTRY_DSN
> ```

The keys are joined with commas, one word per profile, so a line reads back
as the `remember` that would fix it.

## export

Write a vault lookup for your shell's startup file.

```sh
monkeys export [@profile] [KEY[,KEY...]]
```

For a secret that every shell should carry from startup, `export` writes the
lines and you paste them into your startup file:

```sh
monkeys export ANTHROPIC_API_KEY
```

On macOS:

> ```
> export ANTHROPIC_API_KEY="$(security find-generic-password -s monkeys -a ANTHROPIC_API_KEY -w)"
> ```

On Linux:

> ```
> export ANTHROPIC_API_KEY="$(secret-tool lookup service monkeys account ANTHROPIC_API_KEY)"
> ```

No secret is in either line. Each asks the vault when the shell starts, the
way you would have written it by hand, so a startup file written on one
machine is for that machine's vault. With no keys, inside a project, it writes
one line per key the file lists, each under the profile's full name:

```sh
monkeys export
```

> ```
> export DATABASE_URL="$(security find-generic-password -s monkeys -a foo.test/DATABASE_URL -w)"
> ```

`monkeys` writes nothing into your startup file for you: a secret that every
process on the machine inherits is a decision to make with the file open.

The keychain treats `security` as its own program, so the first shell that
runs the line asks once whether to allow it. Answer Always Allow and it stays
quiet.

# Q&A

### What is a .monkeys file?

A [`.monkeys`](#monkeys) file is a project's list of the environment variables
it needs, kept next to the code and committed with it. It holds the keys, never the secrets: `.env.example`
with the secrets left out, and the values that were never secret written in
beside their keys.

### Is .monkeys a file extension?

No. The whole name is `.monkeys`, the way `.env` is: nothing comes before the
dot. A project has one, at the root of the git checkout.

### Where does monkeys keep a secret?

In the [vault](#vault) the operating system already runs: the keychain on macOS, the
Secret Service on Linux, which is GNOME Keyring or KWallet. It keeps no file
of its own, so there is no database to back up or leak, and the desktop's own
tools list and delete what it stores.

### Can a coding agent read my secrets?

No command prints a stored secret, and [`monkeys run`](#run) replaces one with
`[redacted KEY]` when the command it started prints it back. An agent can give
a command the secrets it needs without the secret entering the conversation,
which is what the [skill](#skill) teaches it to do.

### How do I move a project off .env?

[`monkeys eat`](#eat) reads the `.env` files it finds, puts the secrets in your vault,
writes the keys into `.monkeys`, and deletes the files it read. Name the keys
that were never secret with `--public` and it writes those as values instead
of asking about each one.

### Does this work with...?

Yes. Anything that reads `process.env` gets what `run` hands it, and a `.env`
file is only one way to fill that environment, never a channel of its own.
Every loader that reads one reads the environment as well.

```sh
monkeys run bun run dev
monkeys run npm run build
```

The environment wins over the file, so a `.env` left behind cannot shadow what
`run` handed over. Prefix rules are untouched: only the names a framework
exports, `VITE_` or `PUBLIC_` or `NEXT_PUBLIC_`, reach the browser, wherever
the value came from.

For a tool that reads no environment at all, `poo` writes the `.env` it wants.

### How do I use this with Docker?

A container inherits nothing from the host, so name the variable and Docker
takes it from the environment [`run`](#run) made. A `-e` with no `=value` after it
means exactly that.

```sh
monkeys run OPENROUTER_API_KEY docker run -e OPENROUTER_API_KEY myimage
monkeys run docker compose up
```

In `compose.yaml` a bare name under `environment:` does the same:

```yaml
services:
  api:
    environment:
      - OPENROUTER_API_KEY
      - STRIPE_SECRET_KEY
```

Output that comes back through the container is still redacted, since
`monkeys` is in front of the `docker` command. A build takes a BuildKit secret
instead, which never lands in a layer:

```sh
monkeys run OPENROUTER_API_KEY \
  docker build --secret id=openrouter,env=OPENROUTER_API_KEY .
```

### What if a tool insists on a .env file?

[`monkeys poo`](#poo) writes one carrying the same keys `.monkeys` lists, with nothing
after them, so the file satisfies whatever wanted it while `run` keeps handing
over the values. It lands in `/tmp` unless `--path` says otherwise.

```sh
monkeys poo --path .
```

### How do I give a teammate the secrets?

[`monkeys pack`](#pack) writes every profile as one encrypted file and puts its
passphrase on your clipboard. They run [`monkeys unpack`](#unpack), which asks for the
passphrase, puts the secrets in their own vault, writes the project's
`.monkeys`, and deletes the file.

### What happens if I lose the machine?

The secrets are gone with the [vault](#vault), since nothing else holds them. Remember
them again from wherever they came from, or unpack a bundle a teammate still
has.

### Does monkeys work on Windows?

Monkeys hate windows. There is no native build: it speaks to the macOS
keychain and the Secret Service, and Windows runs neither. The Linux build
runs under WSL, which needs a Secret Service in that session the way any Linux
machine without a desktop does: `gnome-keyring` or KWallet, running and
unlocked.

### How is this different from direnv?

`direnv` loads a file into your shell when you enter a directory, so the
secrets live in a file and then in every process that shell starts. `monkeys`
keeps them in the vault and hands them to one command, and the file it commits
holds keys only.

### How is this different from 1Password CLI, Doppler or Infisical?

Those are services: an account, a server, a subscription, and a company that
can see what you store. `monkeys` is one binary that uses the vault already on
the machine, with nothing to sign into and nothing to host. What it gives up
is what a service is for, such as audit logs and taking access away from
someone centrally.

### Is monkeys free?

MIT, with no account and no server. The [source](https://github.com/eastriverlee/monkeys)
is the whole of it.

# Caveats

### What redaction can and cannot do

An agent that sets out to see a secret can see it. `run` hands the secret to
a process, and a process can do what it likes with what it holds: encode it,
split it, write it somewhere and read it back. Redaction catches the secret
written out as it is, which is what a reflex produces, and nothing here claims
more than that.

That is enough, because the reflex is the whole problem. An agent does not
read `.env` out of curiosity. It reads it because a variable was empty, the
task was stuck, and `cat .env` was the shortest path back to the task. Take the
shortest path away and give it a shorter one, and the urge goes with it: `run`
puts the secret where the task needs it, a missing key comes back as a message
that says what to ask for, `preview` and `doctor --short` answer "is it there"
without reading anything. The agent gets on with the task. What remains after
that is intent, and intent is a question for whoever runs the agent.

The same holds for people. A secret shared with a teammate stops being a paste
into a chat and becomes `pack` and `unpack`, sealed in transit and landing in
that person's vault. And a project's bookkeeping collapses into one file. A `.env` nobody commits,
a `.env.example` that drifts from it, a `.gitignore` line keeping the two apart:
all of it becomes one committed `.monkeys` that says what is needed and holds
nothing.
