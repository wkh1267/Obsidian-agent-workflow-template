---
name: defuddle
description: Extract clean markdown content from web pages using Defuddle CLI, removing clutter and navigation to save tokens. Use instead of WebFetch when the user provides a URL to read or analyze, for online documentation, articles, blog posts, or any standard web page. Do NOT use for URLs ending in .md — those are already markdown, use WebFetch directly.
---

# Defuddle

Use Defuddle CLI to extract clean readable content from web pages. Prefer over WebFetch for standard web pages — it removes navigation, ads, and clutter, reducing token usage.

If not installed: `npm install -g defuddle`

## Usage

Always use `--md` for markdown output.

**On Windows** — the bash wrapper mangles paths; use PowerShell with `defuddle.cmd`:

```powershell
defuddle.cmd parse <url> --md
```

**On macOS / Linux** — use bash normally:

```bash
defuddle parse <url> --md
```

Detect the platform from the environment context (`Platform: win32` → PowerShell; otherwise Bash).

Save to file (Windows):

```powershell
defuddle.cmd parse <url> --md -o content.md
```

Save to file (macOS / Linux):

```bash
defuddle parse <url> --md -o content.md
```

Extract specific metadata (Windows):

```powershell
defuddle.cmd parse <url> -p title
defuddle.cmd parse <url> -p description
defuddle.cmd parse <url> -p domain
```

## Output formats

| Flag | Format |
|------|--------|
| `--md` | Markdown (default choice) |
| `--json` | JSON with both HTML and markdown |
| (none) | HTML |
| `-p <name>` | Specific metadata property |
