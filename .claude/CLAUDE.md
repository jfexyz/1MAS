# CLAUDE.md

Notes for Claude Code working in this repository.

## Commits

This is a public repository. Commit as Felix with plain `git commit` (their own git identity), and
end every message with `Co-Authored-By: Claude <noreply@anthropic.com>`. Never use
`--author="Claude …"` here.

## Safety on hardware

- Never open the `OTA1` RFCOMM service, and never send the commands in `Command.forbidden` (firmware
  update, delete music). Both guards exist in code; do not weaken them.
- Before changing anything on the headphones (any write command), say what will be sent, and put the
  setting back afterwards.

## Docs

`docs/HARDWARE.md` is the record of what has been verified on real devices. Add to it in the same
commit as any change that rests on a new hardware finding.
