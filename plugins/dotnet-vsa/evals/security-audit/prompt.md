---
description: "Natural phrasing that should load the security-audit skill rather than package-health."
tags: [skill-selection, security, confusable]
max_turns: 4
timeout_seconds: 180
allowed_tools: [Read, Glob, Grep, Skill]
---

Do a full security audit of this whole codebase: secrets, authentication setup, CORS and OWASP issues.
