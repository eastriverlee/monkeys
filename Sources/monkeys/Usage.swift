struct CommandSummary {
    let verb: String
    let arguments: String
    let summary: String
}

let commandSummaries = [
    CommandSummary(verb: "remember", arguments: "<KEY> [--clipboard]",
                   summary: "remember a secret typed, piped or pasted"),
    CommandSummary(verb: "remember", arguments: "--public <KEY>",
                   summary: "write a plain value into .monkeys"),
    CommandSummary(verb: "remember", arguments: "[@profile] [--all]",
                   summary: "prompt for each key the profile lacks"),
    CommandSummary(verb: "forget", arguments: "<KEY>",
                   summary: "remove one remembered secret"),
    CommandSummary(verb: "forget", arguments: "@profile[,profile...]",
                   summary: "remove every secret of those profiles"),
    CommandSummary(verb: "forget", arguments: "+namespace",
                   summary: "the same for every profile under it"),
    CommandSummary(verb: "forget", arguments: "[@profile] --all --untracked",
                   summary: "remove vault keys the file does not track"),
    CommandSummary(verb: "drop", arguments: "<KEY>",
                   summary: "forget it and unlist it from .monkeys"),
    CommandSummary(verb: "move", arguments: "[@source] KEY [@target] [NEW_KEY]",
                   summary: "move a key, change its name, or both"),
    CommandSummary(verb: "move", arguments: "@old @new",
                   summary: "a profile's new name, vault and file"),
    CommandSummary(verb: "move", arguments: "+old +new",
                   summary: "the same for every profile of +old"),
    CommandSummary(verb: "run", arguments: "<KEY[,KEY...]> <command>",
                   summary: "run a command with those secrets set"),
    CommandSummary(verb: "run", arguments: "--all <command>",
                   summary: "the same, with every remembered secret"),
    CommandSummary(verb: "run", arguments: "<command>",
                   summary: "the same, keys read from .monkeys"),
    CommandSummary(verb: "pack", arguments: "[name] [--path DIR] [--only ...]",
                   summary: "one encrypted file of the profiles"),
    CommandSummary(verb: "unpack", arguments: "<name> [dir] [--keep]",
                   summary: "remember its secrets, write its .monkeys"),
    CommandSummary(verb: "eat", arguments: "[--public KEY[,KEY...]]",
                   summary: "move the .env files here into monkeys"),
    CommandSummary(verb: "poo", arguments: "[@profile] [--path DIR]",
                   summary: "a .env of keys, for tools that want one"),
    CommandSummary(verb: "poo", arguments: "@profile --WITH_SECRETS",
                   summary: "the same, each key a vault lookup"),
    CommandSummary(verb: "fill", arguments: "@a --with @b",
                   summary: "give @a the keys it lacks, from @b"),
    CommandSummary(verb: "list", arguments: "",
                   summary: "the whole vault, as blocks by profile"),
    CommandSummary(verb: "preview", arguments: "[KEY[,KEY...]]",
                   summary: "show each secret masked, with length"),
    CommandSummary(verb: "doctor", arguments: "[--short]",
                   summary: "what each profile has and lacks"),
    CommandSummary(verb: "export", arguments: "[KEY[,KEY...]]",
                   summary: "vault lookups for a startup file"),
]

private func plainInvocation(_ command: CommandSummary) -> String {
    command.arguments.isEmpty
        ? "monkeys \(command.verb)"
        : "monkeys \(command.verb) \(command.arguments)"
}

private func paintedInvocation(_ command: CommandSummary) -> String {
    let start = outputStyle("monkeys", .dim) + " " + outputStyle(command.verb, .bold)
    guard !command.arguments.isEmpty else { return start }
    return start + " " + outputStyle(command.arguments, .argument)
}

private var commandLines: [String] {
    let width = commandSummaries.map { plainInvocation($0).count }.max() ?? 0
    return commandSummaries.map { command in
        let gap = String(repeating: " ", count: width - plainInvocation(command).count + 2)
        return "  " + paintedInvocation(command) + gap + command.summary
    }
}

var usage: String {
    """
    \(outputStyle("monkeys", .bold, .brand)) - .env you can hand to an LLM, or git add

    \(commandLines.joined(separator: "\n"))

    Use a secret in one command:

      \(outputStyle("monkeys run OPENROUTER_API_KEY ./hello.sh", .argument))

    A project keeps its keys in \(projectFileName): the first line names the
    project, and each @ line opens a profile the keys below belong to:

      \(outputStyle("+foo", .argument))
      \(outputStyle("@test,production", .argument))
      \(outputStyle("DATABASE_URL", .argument))
      \(outputStyle("STRIPE_SECRET_KEY", .argument))
      \(outputStyle("@production", .argument))
      \(outputStyle("SENTRY_DSN", .argument))

    In that directory or below it within the checkout, run takes only the
    command, and remember, preview and forget read and write the first profile:

      \(outputStyle("monkeys run ./hello.sh", .argument))
      \(outputStyle("monkeys remember STRIPE_SECRET_KEY", .argument))      remembered as foo.test/STRIPE_SECRET_KEY
      \(outputStyle("monkeys remember", .argument))                        each key it lacks, one prompt each

    remember writes that file as it goes. A key it does not list is added
    under the profile, and in a checkout with no file at all the first
    remember makes one, named after the directory. forget removes the secret
    and leaves the key listed, which doctor then reports as missing; drop
    takes the key with it, and the project stops asking for it:

      \(outputStyle("monkeys forget STRIPE_SECRET_KEY", .argument))        the key stays in \(projectFileName)
      \(outputStyle("monkeys drop STRIPE_SECRET_KEY", .argument))          both go

    Both ask first, since the vault is the only place that secret exists, and
    the question needs a terminal.

    A value that is not secret, PORT=3000 and the like, is a KEY=value line in
    the same file, under the same @ block. run puts it in the environment
    straight from the file, and the vault never sees it:

      \(outputStyle("monkeys remember --public PORT", .argument))        value: 3000, written as PORT=3000

    Each profile gets the keys of every block that lists it, and the first
    profile in the file is the one run uses when none is given:

      \(outputStyle("monkeys run @production ./deploy", .argument))
      \(outputStyle("monkeys doctor", .argument))                     which profile lacks what

    Name them as you like. test, staging, production and personal are what
    projects usually mean. test goes at the top, even when it is added last,
    so the default is the harmless one; personal is a key each person holds
    their own copy of, so pack asks before a bundle carries it away.

    A profile that shares most of its secrets with another is filled from it.
    fill moves only the keys the target lacks, never a secret it already
    holds, and says which keys moved:

      \(outputStyle("monkeys fill @production --with @test", .argument))

    A profile's name changes in the vault and in the file at once, and a
    namespace's for every profile under it. move refuses a target that
    already holds a key, so two profiles never merge by accident:

      \(outputStyle("monkeys move @test DATABASE_URL @production", .argument))
      \(outputStyle("monkeys move OLD_KEY NEW_KEY", .argument))
      \(outputStyle("monkeys move @staging @preview", .argument))
      \(outputStyle("monkeys move +foo +bar", .argument))

    doctor marks vault keys the file does not track with -, including profiles
    no longer declared in this namespace. To remove only those keys:

      \(outputStyle("monkeys forget --all --untracked", .argument))

    A leading @profile picks another declared profile, and a prefix that fits
    only one of them is enough. From outside the project, or for another
    project's profile, say the namespace too, @namespace.profile:

      \(outputStyle("monkeys remember @production SENTRY_DSN", .argument))   remembered as foo.production/SENTRY_DSN
      \(outputStyle("monkeys remember @foo.production SENTRY_DSN", .argument))    the same, from anywhere

    A key remembered outside any project has no profile and needs no @. Inside
    a project every command is scoped to its profile, so a bare @ says no
    profile: it sets the file aside, keys are given again, and the keys with
    no profile are reached without leaving the directory:

      \(outputStyle("monkeys run ANTHROPIC_API_KEY claude", .argument))     outside a project
      \(outputStyle("monkeys run @ ANTHROPIC_API_KEY claude", .argument))   inside one, the same secret

    For a shell that should carry secrets from startup, export writes the lines
    to paste into your startup file yourself. Each asks this machine's vault
    for one secret when the shell starts; none of them holds one:

      \(outputStyle("monkeys export ANTHROPIC_API_KEY", .argument))
      \(outputStyle("monkeys export", .argument))                the project's keys

    Share the project's profiles as one encrypted file: every profile the
    file declares and every key, unless --only says which. After it, a
    @profile (or @a,b, several at once) opens a block and the keys after
    it belong to every profile in that block, the way the file is written;
    keys with no @ before them come from the default profile, the first
    the file mentions. The bundle keeps that shape, project and all, and
    unpack writes it back as the project file. It goes to /tmp/a.monsecrets,
    outside any repository; a path before --only puts it elsewhere, into a
    directory you name or at a file you name, and --open reveals it in your
    file manager, ready to drag.
    pack draws a passphrase and puts it on your clipboard, or asks for one
    with --ask; unpack asks for it, remembers the secrets,
    writes the keys into .monkeys at the root of the git checkout you are
    in, here when there is none, or in the directory you name, and deletes
    the bundle, since it has done its job; --keep leaves it:

      \(outputStyle("monkeys pack", .argument))                   /tmp/a.monsecrets
      \(outputStyle("monkeys pack ~/Desktop", .argument))         a.monsecrets, there
      \(outputStyle("monkeys pack --only @test", .argument))      the same, one profile
      \(outputStyle("monkeys pack --only OPENROUTER_API_KEY", .argument))
      \(outputStyle("monkeys pack --only @test,production DATABASE_URL", .argument))
      \(outputStyle("monkeys pack shared --only @test @production SENTRY_DSN", .argument))
      \(outputStyle("monkeys unpack a", .argument))

    A project that still has .env files moves them in with one command. eat
    asks, key by key, whether each one is a secret for the vault or a public
    value for .monkeys, writes the file, and deletes the .env files once
    everything is remembered. Naming the public keys answers every question up
    front, so it asks nothing and needs no terminal:

      \(outputStyle("monkeys eat", .argument))
      \(outputStyle("monkeys eat --public PORT,NODE_ENV", .argument))

    Some tools read a .env file rather than the environment, and some only
    want one to exist. poo writes one from the same list: the keys on their
    own, with no values beside them, and the public values as they stand. A
    key with nothing after it sets nothing, so the secrets still arrive
    through run and nothing in the file can shadow them:

      \(outputStyle("monkeys poo", .argument))
      \(outputStyle("monkeys poo @production", .argument))

    A tool that wants the values in the file takes them as vault lookups, the
    same shape export writes, so nothing of the secret is on disk. A shell
    that sources the file runs them; a reader that only parses, like dotenv
    or Compose, gets the text of the lookup instead, and only then is there
    reason to write the secrets out. Every one of them lands under /tmp unless
    --path names a directory, and inside a git checkout poo asks before it
    writes. The last one wants a terminal, since pasting is a person's errand:

      \(outputStyle("monkeys poo @production --WITH_SECRETS", .argument))
      \(outputStyle("monkeys poo @production --WITH_SECRETS --EXPAND_DANGEROUSLY", .argument))
      \(outputStyle("monkeys poo @production --WITH_SECRETS --EXPAND_DANGEROUSLY --open", .argument))

    \(styledAgentGuide)
    """
}
