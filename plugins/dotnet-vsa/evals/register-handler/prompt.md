---
description: "Natural phrasing that should load the register-handler skill."
tags: [skill-selection, smoke, scaffold]
max_turns: 4
timeout_seconds: 180
allowed_tools: [Read, Glob, Grep, Skill]
---

Calling POST /orders/{id}/cancel fails with "Unable to resolve service for type CancelOrderHandler". Fix the wiring.
