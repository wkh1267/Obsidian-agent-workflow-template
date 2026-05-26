---
title: Log
tags:
  - meta
---

# 📝 System Log

```dataview
TABLE operation, source, length(pages_created) AS "Files Created"
FROM "log"
SORT date DESC, file.ctime DESC
```
