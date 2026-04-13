# Contributing

Thanks for considering a contribution.

## Before Opening A PR

- Open an issue first for significant feature work or architectural changes.
- Keep changes focused and avoid unrelated cleanup in the same pull request.
- If your change affects detection logic, include a short note about how you tested it on macOS.

## Local Setup

```bash
npm install
npm run dev
```

For the native app:

```bash
npm run menubar:build
```

## Pull Request Guidelines

- Describe the user-facing problem first.
- Summarize the implementation briefly.
- Mention validation steps you actually ran.
- Include screenshots if you changed the UI.
- Do not replace files in `release/` unless the change is specifically about the release artifacts.

## Style

- Prefer small, readable changes over broad refactors.
- Keep macOS-specific behavior explicit.
- Do not introduce telemetry or remote services without discussion.
