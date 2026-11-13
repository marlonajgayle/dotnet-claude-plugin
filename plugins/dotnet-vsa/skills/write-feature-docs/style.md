# Style guide for feature guides

Adapted from the conventions of DigitalOcean's community tutorials, for Markdown rendered on GitHub.

## Structure

- **Title**: `How To <Do Something> with <Feature>`, in title case, naming the reader's task, not the code (`How To Issue Refunds`, not `RefundOrder Slice`).
- **Order**: Introduction, Key Takeaways, Prerequisites, Steps, How It Works, Reference, Troubleshooting, FAQs, Conclusion. Readers learn to find things in the same place on every page.
- **Steps**: `## Step N — <Gerund Phrase>` with an em dash (—). One goal per step. Each step opens with why, shows one action, shows the result, and explains it.
- **Introduction** ends with "In this guide, you will…", so readers know what they will have at the end.
- **Prerequisites** are a list, each item with a link to how to satisfy it. Nothing the reader needs may appear for the first time in a step.
- **Conclusion** recaps what the reader did and links to what to read next.

## Voice

- Second person and present tense: "You send a request", "The API returns". Use "we" only for things you and the reader do together ("Now we'll check the result").
- Explain why before how. A command without a reason is not documentation.
- Plain, specific words. No "simply", "just", "easy", "obviously": they make readers who are stuck feel worse.
- Name things exactly as the code does in code font (`InvoiceErrors.NotFound`), and describe them in plain words the first time.
- Short paragraphs: one idea each, at most four sentences.

## Code and output

- Every code block has a language: `bash`, `json`, `csharp`, `text`, `mermaid`.
- One command per block, so it can be copied and run alone. Show the full command, never `...` inside it.
- Values the reader must replace are written `<like-this>` and explained right after the block the first time they appear.
- Show the file a snippet belongs to in bold code font on the line above the block: **`src/Api/appsettings.Local.json`**. Show only the lines that matter, and say where they go.
- Output goes under a bold **Output** label in its own block, so readers can tell what they type from what they see.
- Examples match the code exactly: property names, casing, status codes, error codes. Use realistic but fake data; never real secrets, tokens, emails or customer data.

## Callouts

Use GitHub alerts, sparingly, at most one per step:

- `> [!NOTE]` for useful context that is not required.
- `> [!TIP]` for a better way to do something.
- `> [!IMPORTANT]` for something the reader must do or the step fails.
- `> [!WARNING]` for data loss, security risk, or effects on other users.

## Diagrams and tables

- Use Mermaid, which GitHub renders: `sequenceDiagram` for request flows, `flowchart` for decisions and states, `erDiagram` for data models. Show the real components by their names in the code. No screenshots of code.
- Use tables for reference material that readers scan: endpoints, fields, errors, configuration. Use prose for anything that needs explaining.
- Screenshots are for UI only. Save them under `<DOCS_DIR>/images/<slug>/`, give each one alt text that says what it shows, and keep them current.

## Links

- Relative links between docs pages (`../features/orders.md`); absolute links for external sites.
- Link the first mention of a concept, not every mention.
- Link text says where it goes ("the authorization policies guide"), never "here" or "this link".

## Accuracy

- Document behaviour that exists on the branch, not what the spec hoped for. Where they differ, the code wins, and the difference is worth a note.
- Mark unconfirmed facts with `<!-- TODO: confirm ... -->` rather than guessing.
- `last_validated` is a claim that every example was run on that date. Only set it when that is true.
