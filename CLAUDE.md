# Clipstack

@AGENTS.md

## Claude Code notes

- Use `./build.sh --run` to verify a change end to end; `swift build` alone is enough for a
  compile check. Report build output faithfully, including warnings.
- `build/` and `.build/` are gitignored. Never commit them or `history.json` test data.
- When changing `HistoryView.swift`, describe the visual result in the summary; there is no
  automated screenshot pipeline.
- Commit messages: imperative summary line under 60 characters, then a body that explains why.
