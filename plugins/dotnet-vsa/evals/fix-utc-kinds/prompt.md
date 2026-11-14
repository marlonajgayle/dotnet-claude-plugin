---
description: "Natural phrasing that should load the fix-utc-kinds skill."
tags: [skill-selection, persistence]
max_turns: 4
timeout_seconds: 180
allowed_tools: [Read, Glob, Grep, Skill]
---

Dates in our API responses come back without a Z, and the mobile app shows them five hours off.
