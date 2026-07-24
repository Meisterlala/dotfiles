---
name: generate-skill
description: Create an OpenCode skill from a successfully verified reusable workflow. Use when the user asks to create or save a skill, or approves a proactive skill proposal.
---

# Generate Skill

Create a concise, evidence-based skill only after the user approves it. Capture the reusable solution, not the history of the conversation or investigation.

## Workflow

1. Read the current OpenCode skill documentation at `https://opencode.ai/docs/skills/`.
2. Inspect existing repository and global skills to avoid duplicates.
3. Determine the scope:
   - Use `.opencode/skills/<name>/SKILL.md` for repository-specific commands, architecture, infrastructure, or conventions.
   - Use `~/.config/opencode/skills/<name>/SKILL.md` only for workflows portable across unrelated repositories.
   - Prefer repository scope when uncertain. Ask one concise question if the correct scope is unclear.
4. Generalize the successfully verified solution into the shortest procedure that would help with the same task again.
5. Include verification steps when success is not self-evident.
6. Include common errors only when they reveal a durable constraint or non-obvious part of the workflow.
7. Create the skill and validate its location, frontmatter, name, and description against the documentation.

## Requirements

- Keep the first version brief; expand it only after later use reveals missing details.
- Use a lowercase hyphen-separated name matching the containing directory.
- Write a specific description that states what task the skill performs and when it should be loaded.
- Keep every instruction relevant to performing or verifying that task.
- Include only stable, reusable knowledge. Generalize repository-specific details without removing details required for the workflow to work.
- Do not include credentials, private data, conversation history, temporary paths, transient system state, missing local tools, irrelevant debugging history, or unverified assumptions.
- Do not preserve failed attempts unless they expose a durable and likely recurring pitfall.
- Do not create a duplicate or overwrite an existing skill without explicit approval.
