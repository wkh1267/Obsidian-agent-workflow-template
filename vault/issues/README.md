---
title: Issues
type: meta
tags:
  - meta
  - issues
created: 2026-05-07
updated: 2026-05-15
status: evergreen
sources:
  - "[[docs/issue-workflow]]"
---

# Issues

Feature work tracked via bounded subagents. Each issue is a numbered directory under `issues/NNNN-slug/`.

Full workflow: [[docs/issue-workflow]].

Open a new issue: `/issue <description>` or say "open an issue for X".

```dataviewjs
const issuePages = dv.pages('"issues"')
  .where(p => /^issues\/\d{4}-[^/]+\/README\.md$/.test(p.file.path))
  .array()
  .sort((a, b) => String(a.issue ?? a.file.folder).localeCompare(String(b.issue ?? b.file.folder)));

const terminalStatuses = new Set(["accepted", "abandoned"]);

function issueNumber(page) {
  const folder = page.file.folder.split("/").pop();
  const match = folder.match(/^(\d{4})-/);
  return String(page.issue ?? match?.[1] ?? folder);
}

function updated(page) {
  const value = page.updated ?? page.file.mtime;
  return value?.toFormat ? value.toFormat("yyyy-MM-dd") : String(value ?? "");
}

function row(page) {
  const issue = issueNumber(page);
  return [
    dv.fileLink(page.file.path, false, issue),
    page.status ?? "unknown",
    page.title ?? page.file.folder.split("/").pop(),
    updated(page),
  ];
}

if (issuePages.length === 0) {
  dv.paragraph("No issues found.");
} else {
  const statusCounts = Object.entries(
    issuePages.reduce((counts, page) => {
      const status = page.status ?? "unknown";
      counts[status] = (counts[status] ?? 0) + 1;
      return counts;
    }, {})
  ).sort((a, b) => a[0].localeCompare(b[0]));

  dv.header(3, "Status Summary");
  dv.table(["Status", "Count"], statusCounts);

  const inFlight = issuePages.filter(p => !terminalStatuses.has(p.status ?? "unknown"));
  dv.header(3, inFlight.length + " in-flight issue(s)");
  if (inFlight.length === 0) {
    dv.paragraph("No in-flight issues.");
  } else {
    dv.table(["Issue", "Status", "Title", "Updated"], inFlight.map(row));
  }

  dv.header(3, "All Issues");
  dv.table(["Issue", "Status", "Title", "Updated"], issuePages.slice().reverse().map(row));
}
```

## See Also

- [[docs/issue-workflow]]
- [[docs/operations]]
