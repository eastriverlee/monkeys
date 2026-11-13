private func wrapped(_ text: String, at width: Int = 78) -> String {
    var lines: [String] = []
    var line = ""
    for word in text.split(whereSeparator: \.isWhitespace) {
        if line.isEmpty {
            line = String(word)
        } else if line.count + 1 + word.count <= width {
            line += " " + word
        } else {
            lines.append(line)
            line = String(word)
        }
    }
    if !line.isEmpty { lines.append(line) }
    return lines.joined(separator: "\n")
}

private let maskingRule = wrapped("""
Preview shows at most the first \(previewLeadingCharacters) and the last
\(previewTrailingCharacters) characters, and only while at least
\(previewMinimumHiddenCharacters) of them stay hidden. A secret shorter than that
shows its length alone.
""")

var styledAgentGuide: String {
    let lines = agentGuide.split(separator: "\n", omittingEmptySubsequences: false)
    return lines.enumerated().map { position, line in
        if position == 0 { return outputStyle(String(line), .bold, .brand) }
        guard line.hasPrefix("  ") else { return String(line) }
        return "  " + outputStyle(String(line.dropFirst(2)), .argument)
    }.joined(separator: "\n")
}

private let agentGuide = """
monkeys for an automated caller

A remembered secret must never enter an agent's context or transcript. Anything
an agent reads stays in both, and a vault cannot take it back. No command
prints a remembered secret, so the only thing to get right is how one is used.

monkeys run puts the named secrets into one command's environment, and
nowhere else:

  monkeys run OPENROUTER_API_KEY ./hello.sh
  monkeys run OPENROUTER_API_KEY,GITHUB_TOKEN ./deploy

Nothing on that line holds a secret, so nothing an agent writes can spill
one. The exit status and the signals are the command's own. Its output comes
back through monkeys, and a remembered secret in it comes back as [redacted KEY],
so echo $KEY says which secret was there and never the secret. A file that
has to end up with the secret in it takes the redirect inside the command,
where the secret goes from the child straight into the file and never passes
monkeys:

  monkeys run OPENROUTER_API_KEY sh -c 'envsubst < template > config'

Written with the redirect outside, the file is monkeys's own output and the
redaction lands in it.

A project that has a .monkeys file has already listed the keys it needs, and
run there takes only the command:

  monkeys run ./hello.sh

A + line names the namespace the profiles live in, the @ lines scope every
key, and the first profile in the file is the one run uses unless @profile
says otherwise, so remember in that directory writes into the same profile the
command reads from. The file is the list; read it before adding a key.
Filling a profile from a shared .monsecrets bundle is monkeys unpack, which
asks for a passphrase, so that too is a human's job.

Name the keys the command actually reads. Naming them is how a missing secret
shows up, and it keeps the rest out of a process that has no business with
them. --all uses everything, for when the keys are not worth working out:

  monkeys run --all ./hello.sh

A key you named with no secret remembered stops the run before it starts, and
says what to ask for:

  monkeys: SUPER_SECRET is not remembered yet
  nothing happened. a human types the secret into:
    monkeys remember SUPER_SECRET
  then try again.

A key the .monkeys file lists does not stop it, since one command rarely reads
every key its project lists. run names the missing ones and goes ahead, and
when the command then fails it adds the same remember lines.

An agent passes those on. Remembering a secret is a human's job: an agent that
types one puts it in its own context before it reaches the vault.

To see what exists, read the keys with monkeys list, and their secrets' shape
with monkeys preview:

  $ monkeys preview
  GITHUB_TOKEN        gh...f 40
  OPENROUTER_API_KEY  sk...2 73

\(maskingRule)

A length and a two-character prefix confirm that the right secret arrived
without reading it.

monkeys export writes vault lookups for a startup file and holds no secret,
which is why it may print. A variable that already holds a secret is never
printed. Each of these puts a secret in front of whoever ran it:

  echo "$OPENROUTER_API_KEY"
  env
  printenv

So does writing one into a file, a log, a commit, or a bug report. Where a
config file wants the secret, write whatever reference its format offers, such
as ${OPENROUTER_API_KEY}, and let the program expand it.
"""
