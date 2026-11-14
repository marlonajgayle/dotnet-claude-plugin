---
description: "Natural phrasing that should load the audit-authorization skill rather than security-audit."
tags: [skill-selection, security, confusable]
max_turns: 4
timeout_seconds: 180
allowed_tools: [Read, Glob, Grep, Skill]
---

List every endpoint with the policy that protects it, and flag anything that looks like an IDOR.
