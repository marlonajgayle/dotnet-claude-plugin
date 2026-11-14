---
description: "Natural phrasing that should load the write-integration-tests skill rather than write-handler-tests."
tags: [skill-selection, tests, confusable]
max_turns: 4
timeout_seconds: 180
allowed_tools: [Read, Glob, Grep, Skill]
---

Write tests for Orders.CreateOrder that go through HTTP and check 401 for anonymous callers and 403 for the wrong role.
