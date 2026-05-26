---
title: Index
tags:
  - meta
updated: 2026-05-05
---

# 🧠 Knowledgebase Index

## 🛠️ Tools & Entities

```dataview
TABLE tags, updated
FROM "wiki/entities"
WHERE type = "entity"
SORT updated DESC
```

---

## 📚 Concepts

### Security

```dataview
LIST
FROM "wiki/concepts"
WHERE contains(tags, "security")
SORT file.name ASC
```

### Software & Infrastructure

```dataview
LIST
FROM "wiki/concepts"
WHERE contains(tags, "infrastructure") OR contains(tags, "software")
SORT file.name ASC
```

### Knowledge Management

```dataview
LIST
FROM "wiki/concepts"
WHERE contains(tags, "knowledge-management")
SORT file.name ASC
```
