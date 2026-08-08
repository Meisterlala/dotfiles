---
name: plane-workboard
description: >-
  Use this skill whenever working with Plane through MCP as a shared AI-agent
  workboard: search, create, refine, triage, prioritize, claim, update, comment,
  block, hand off, reopen, cancel, or complete work items. It defines ticket
  writing, acceptance criteria, deduplication, state transitions, durable
  comments, and multi-agent coordination.
compatibility: opencode
metadata:
  system: plane
  interface: mcp
  audience: ai-agents
---

# Plane AI workboard

Use Plane as durable shared state for work spanning agents or sessions. Do not use it as a transcript of internal reasoning or every tool call.

## Configuration

- Default project ID: `b987cd75-93c3-4671-b892-252e9fd3fc09`
- Use another project only when the user or current task explicitly identifies one.
- Use the exact `agentgateway_plane_*` MCP tools named in this skill. Do not guess aliases or shortened tool names.
- Resolve opaque IDs instead of copying them from examples:
  - states: `agentgateway_plane_list_states`
  - labels: `agentgateway_plane_list_labels`
- Never infer an opaque UUID's meaning from an old example.
- Plane CE has no custom work-item types. Create generic work items without a
  `type_id`.

## Non-negotiable rules

1. Search before creating with `agentgateway_plane_search_work_items`; use `agentgateway_plane_list_work_items` when an exhaustive project listing is needed. Do not create duplicates.
2. One work item represents one independently verifiable outcome.
3. Backlog means not ready. Todo means ready. In Progress means actively claimed. Done means verified.
4. Before starting or changing an existing item, read it with `agentgateway_plane_retrieve_work_item` (or `agentgateway_plane_retrieve_work_item_by_identifier` when you have the human identifier), inspect `agentgateway_plane_list_work_item_comments`, and inspect relations with `agentgateway_plane_list_work_item_relations` when dependencies or duplication matter. Use `agentgateway_plane_list_work_item_activities` only when change history is relevant.
5. Keep the description as the current specification. Use comments for durable history and coordination.
6. Never put credentials, tokens, private keys, cookies, full sensitive logs, or other secrets in Plane.
7. Prefer Cancelled plus a reason over deletion. Delete only when explicitly requested and safe.
8. Do not mark Done merely because code was written. Verify acceptance criteria first.

## Decide whether to create a work item

Create or update an item when the work:

- will outlive the current conversation or agent run;
- needs coordination, prioritization, review, or a durable audit trail;
- is blocked and must be resumed later;
- is a distinct follow-up discovered during other work; or
- was explicitly requested to be tracked in Plane.

Do not create an item for:

- every command, file edit, or implementation step;
- a tiny incidental fix already completed and verified in the current task;
- a vague observation with no actionable outcome;
- a duplicate; or
- speculation with no evidence, decision, owner, or useful next action.

For autonomous findings, create in Backlog unless the item already satisfies the Definition of Ready and the user has clearly authorized scheduling it.

## Search and deduplicate

Before creating:

1. Search the project with `agentgateway_plane_search_work_items` using component names, important nouns, error text, and the intended outcome. If you truly need all project items, use `agentgateway_plane_list_work_items`.
2. Inspect plausible matches with `agentgateway_plane_retrieve_work_item` or `agentgateway_plane_retrieve_work_item_by_identifier`, including completed and cancelled items when relevant.
3. If the same outcome exists, update the canonical item with `agentgateway_plane_update_work_item` or add durable context with `agentgateway_plane_create_work_item_comment`.
4. If a duplicate was already created, resolve the relation type with `agentgateway_plane_list_work_item_relation_definitions` when needed, add the duplicate relation with `agentgateway_plane_create_work_item_relation`, then cancel the duplicate with `agentgateway_plane_update_work_item` and a short reason comment.
5. If related but independently actionable, create a separate item with `agentgateway_plane_create_work_item` and connect it using `agentgateway_plane_create_work_item_relation` as `relates_to`, `blocking`, or `blocked_by`.

Different wording does not imply different work.

## Writing work items

Create a new ticket with `agentgateway_plane_create_work_item`. Change its title, description, priority, or state later with `agentgateway_plane_update_work_item`.

### Titles

A title must identify one outcome or observable problem at a glance.

Rules:

- Keep it to one concise sentence, normally no more than about 100 characters.
- Use concrete nouns and a strong verb or observable failure.
- Include the component or trust boundary only when it disambiguates the work.
- Describe one outcome, not a list of tasks.
- Do not end with a period.
- Put priority, state, and agent identity in fields or labels, not prefixes such as `[BUG]`.
- Avoid vague titles such as `Fix auth`, `Cleanup`, `Monitoring issue`, `Investigate stuff`, or `Update config`.
- Avoid prescribing a specific implementation unless it is itself a requirement.

Preferred forms:

- Task or improvement: `<Verb> <capability/object> <scope or outcome>`
- Bug: `<Component> <observable failure> when <condition>`
- Security: `Prevent <unauthorized action or impact> across <trust boundary>`
- Investigation: `Determine <unknown> needed to decide <decision>`
- Removal: `Remove <obsolete thing> after <replacement/condition>`

Examples:

- Good: `Prevent shared MCP keys from authorizing Plane access`
- Good: `Probe the dedicated Plane MCP route independently`
- Good: `Homepage sync omits user-facing HTTPRoutes without exclusions`
- Good: `Determine safe memory limits for Jellyfin transcoding`
- Bad: `Plane MCP security`
- Bad: `Fix routes`
- Bad: `Various resource improvements`

### General HTML description

Omit irrelevant sections rather than leaving empty headings.

```html
<p><strong>Context</strong></p>
<p>What is happening, who or what is affected, and why the work matters.</p>

<p><strong>Desired outcome</strong></p>
<p>
  The externally observable result without unnecessarily prescribing
  implementation.
</p>

<p><strong>Scope</strong></p>
<ul>
  <li>Included responsibility or affected boundary.</li>
  <li>Another included responsibility.</li>
</ul>

<p><strong>Acceptance criteria</strong></p>
<ul>
  <li>A clear, testable condition that must be true.</li>
  <li>Another independently verifiable condition.</li>
</ul>

<p><strong>Constraints and non-goals</strong></p>
<ul>
  <li>Important compatibility, safety, or operational constraint.</li>
  <li>Something explicitly outside this item's scope.</li>
</ul>

<p><strong>Evidence and references</strong></p>
<ul>
  <li><code>path/to/file:line</code> — relevant observation.</li>
  <li>Related item, document, dashboard, commit, or external link.</li>
</ul>
```

Writing rules:

- Explain the problem and desired outcome before implementation details.
- State impact when it affects priority or scope.
- Include enough evidence for another agent to reproduce or verify the claim.
- Keep transient progress out of the description.
- When the specification changes, edit the description and comment with the material change and reason.
- Include only the smallest useful log excerpt and point to the source.
- Mark assumptions and uncertainty explicitly; do not overstate evidence.
- Never include credentials, tokens, cookies, private keys, or sensitive raw output.

### Bug additions

Include these sections when applicable:

```html
<p><strong>Observed behavior</strong></p>
<p>What actually happens.</p>

<p><strong>Expected behavior</strong></p>
<p>What should happen instead.</p>

<p><strong>Reproduction</strong></p>
<ol>
  <li>Minimal reproducible step.</li>
  <li>Next step.</li>
</ol>

<p><strong>Environment</strong></p>
<ul>
  <li>
    Relevant version, deployment, operating system, configuration, or feature
    flag.
  </li>
</ul>
```

If reproduction is unknown, say so and provide the evidence that proves or suggests the failure. Never invent steps.

### Investigation additions

Use an investigation to resolve an unknown, not to hide an oversized implementation task. Include:

- the exact question;
- the decision the answer unlocks;
- known evidence and constraints;
- a timebox or bounded search area when appropriate; and
- a required deliverable such as a recommendation, benchmark, threat model, or implementation plan.

Its acceptance criteria describe the evidence and decision output, not the later implementation.

### Acceptance criteria

Acceptance criteria define what must be true for this item to be accepted. They are not a chronological implementation checklist.

Each criterion must be:

- observable or objectively verifiable;
- outcome-focused;
- necessary to the requested outcome; and
- feasible within the item.

Prefer short checklist statements for technical work. Use Given/When/Then only when behavioral scenarios or edge cases benefit from it.

Avoid `properly`, `correctly`, `better`, `clean`, `robust`, or `works` unless followed by a measurable definition.

Bad:

```html
<li>Authentication works correctly.</li>
```

Good:

```html
<li>
  A client holding only a generic shared MCP key receives no Plane tools or
  Plane API access.
</li>
<li>
  A client holding the dedicated Plane credential can list work items in the
  intended workspace.
</li>
<li>
  An automated check fails when the shared and Plane authorization boundaries
  are no longer separated.
</li>
```

Acceptance criteria are item-specific. Global quality checks belong in the skill's Definition of Done and need not be copied into every ticket.

## Comment templates

Plane activity already records field changes. Comments should preserve information that fields cannot: agent identity behind shared credentials, questions, rationale, blockers, handoffs, and verification evidence.

Read existing comments with `agentgateway_plane_list_work_item_comments`. Add durable discussion with `agentgateway_plane_create_work_item_comment`. Use `agentgateway_plane_update_work_item_comment` only to correct or intentionally revise an existing comment; do not rewrite history to hide a changed decision.

### Comment when

- claiming work through a shared Plane identity;
- asking a blocking question;
- reporting a blocker or failed verification;
- recording a material decision and rationale;
- changing scope or acceptance criteria;
- handing work to another agent;
- providing a user-meaningful milestone on long work;
- completing the item with verification evidence; or
- explaining cancellation or reopening.

### Do not comment for

- every tool call, command, file edit, or test invocation;
- hidden reasoning or chain-of-thought;
- repeated `still working` messages;
- a field transition needing no explanation;
- information already represented accurately in the description or fields; or
- raw logs with no durable value.

Prefer one structured comment over several fragments. Edit a recent comment to fix a typo; create a new comment when preserving historical change matters.

### Material scope or criteria change

Update the description first, then comment:

```html
<p>
  <strong>Specification updated:</strong> Concise statement of what changed.
</p>
<p>
  <strong>Reason:</strong> New evidence, clarified intent, dependency change, or
  corrected assumption.
</p>
<p>
  <strong>Effect:</strong> Impact on scope, priority, acceptance, or existing
  work.
</p>
```

### Completion

```html
<p><strong>Changed:</strong></p>
<ul>
  <li>Concise outcome or implementation summary.</li>
</ul>
<p><strong>Verified:</strong></p>
<ul>
  <li><code>verification command or check</code> — result.</li>
  <li>Acceptance criterion or operational observation — result.</li>
</ul>
<p>
  <strong>References:</strong> Commit, pull request, deployment, dashboard, or
  linked item.
</p>
<p>
  <strong>Remaining work:</strong> None, or links to separately tracked
  follow-ups.
</p>
```

Never write `Remaining work: none` while a required acceptance criterion, review, deployment, or dependency is still pending.

### Cancellation

```html
<p>
  <strong>Cancelled because:</strong> Duplicate, invalid finding, obsolete
  requirement, superseded approach, or explicit decision.
</p>
<p>
  <strong>Canonical or superseding item:</strong> Human-readable Plane
  identifier when applicable.
</p>
<p><strong>Evidence:</strong> The fact or decision supporting cancellation.</p>
```

Add `duplicate_of` or another appropriate relation when available.

### Reopening

```html
<p>
  <strong>Reopened because:</strong> The failed acceptance criterion,
  regression, or invalid completion assumption.
</p>
<p>
  <strong>Evidence:</strong> Minimal reproduction, failing check, or observed
  result.
</p>
<p><strong>Next action:</strong> Concrete work now required.</p>
```

For a meaningfully separate regression, prefer a new linked bug over rewriting the history of the completed item.

## Definition of Ready

Move Backlog to Todo only when all applicable conditions are true. Resolve the Todo state with `agentgateway_plane_list_states`, then transition with `agentgateway_plane_update_work_item`:

- the title names one clear outcome or observable problem;
- context and desired outcome are understandable without the original chat;
- acceptance criteria are objectively testable;
- scope is bounded for one coherent owner or split into sub-items;
- important constraints, non-goals, dependencies, and required access are known;
- unresolved questions do not materially change correctness, scope, or safety;
- priority has a defensible reason;
- no canonical duplicate exists; and
- another capable agent could start without first asking what the ticket means.

If not ready, keep it in Backlog and discover or request the missing information.

## Workflow states

Use Plane state groups according to their meaning. Resolve the project's current state IDs with `agentgateway_plane_list_states`; perform transitions with `agentgateway_plane_update_work_item`. Never hardcode a state UUID from an old run:

| Visible state | Plane group | Meaning                                                         |
| ------------- | ----------- | --------------------------------------------------------------- |
| Backlog       | backlog     | Captured but not ready or not accepted for execution            |
| Todo          | unstarted   | Ready, prioritized, and available to claim                      |
| In Progress   | started     | An agent is actively working, blocked, or awaiting verification |
| Done          | completed   | Acceptance criteria and Definition of Done are verified         |
| Cancelled     | cancelled   | Duplicate, obsolete, invalid, declined, or no longer actionable |

Use only these built-in states. If work is blocked or awaiting review, keep it In Progress and add a concise comment that records the condition and next action. Never pretend it is Done.

## Transition rules

### Create → Backlog

Use for autonomous findings, incomplete requests, unscheduled ideas, and items needing triage or clarification.

### Backlog → Todo

Move only after the Definition of Ready is satisfied and the work is accepted/prioritized. Refining text alone does not schedule the item.

### Todo → In Progress

Move only when an agent is starting now. Do not move items merely because they are important, assigned, or likely to be worked on later.

### In Progress → Done

Move only after verifying every acceptance criterion and posting a concise completion comment. Keep the item In Progress while a dependency, review, deployment, or external check is pending. Done must never lack evidence.

### In Progress → Todo

Use for a clean pause or handoff when the item is ready for another agent and is not externally blocked. Add a handoff comment.

### Any active state → Backlog

Use when new information shows the item is no longer ready or its scope must be reconsidered. Explain why.

### Any non-completed state → Cancelled

Use for duplicates, invalid findings, obsolete work, superseded approaches, or an explicit decision not to proceed. Add a reason and link the canonical or superseding item when applicable.

Do not silently reopen Done. Comment with the failed criterion or regression, then move to an appropriate active state or create a linked bug when it is meaningfully separate work.

## Multi-agent claim protocol

Plane may be accessed through one shared MCP identity, so assignment alone may not identify the real agent. Use a stable agent name and run/session ID in coordination comments.

Before claiming:

1. Retrieve the item with `agentgateway_plane_retrieve_work_item` and read `agentgateway_plane_list_work_item_comments`.
2. Confirm it is Todo, ready, and not already claimed or blocked.
3. Check project members with `agentgateway_plane_get_project_members` only when assignment must be resolved, then inspect the current assignee and latest claim/handoff comment.
4. Resolve blocking relations with `agentgateway_plane_list_work_item_relations`.

To claim:

1. Set the assignee when meaningful with `agentgateway_plane_manage_work_item_assignee`.
2. Resolve In Progress with `agentgateway_plane_list_states` and move the item with `agentgateway_plane_update_work_item`.
3. Add one claim comment with `agentgateway_plane_create_work_item_comment`, including agent identity, run ID, intended outcome, and immediate plan.
4. Retrieve the item again with `agentgateway_plane_retrieve_work_item`. If another agent claimed it concurrently, do not duplicate work; coordinate or back out.

Do not take over an In Progress item merely because it appears idle. Take over only after explicit handoff, user instruction, or a configured stale-claim policy. Record why takeover is safe.

## Asking for more information

Investigate first: read the repository, documentation, current configuration, Plane history, and related items when available.

Ask only when missing information materially affects correctness, scope, safety, authorization, irreversible behavior, user-visible semantics, or acceptance. Typical reasons:

- plausible interpretations lead to substantially different outcomes;
- the target project, environment, user, or data boundary is unknown;
- a destructive or production-impacting action lacks authorization;
- a required credential or permission is unavailable;
- business intent cannot be inferred from technical evidence;
- acceptance criteria conflict; or
- only the user can make the required decision.

Do not ask when the answer is safely discoverable, an established convention decides it, a reversible low-risk default exists, or useful work can establish the answer.

When asking:

1. Bundle related questions into one `agentgateway_plane_create_work_item_comment`.
2. State what was checked and why the answer matters.
3. Offer concrete options and recommend one when evidence supports it.
4. Ask for the smallest answer that unblocks work.
5. Keep the item In Progress when no meaningful work can continue and record the blocker in a comment; otherwise proceed with a documented assumption.
6. Do not repeat the same unanswered question.

For a not-yet-started item missing essential information, leave it in Backlog instead of claiming and immediately blocking it.

## Priority

Use priority for urgency and impact, not interest or ease. Set it during `agentgateway_plane_create_work_item` or change it with `agentgateway_plane_update_work_item`:

- `urgent`: active outage, ongoing exploit, imminent data loss, or immediate safety/security incident requiring interruption of normal work.
- `high`: major impact, serious security/reliability risk, or blocker for important work that should be handled next.
- `medium`: normal planned work with meaningful value or risk reduction.
- `low`: cleanup, convenience, minor drift, or opportunistic improvement with limited near-term impact.
- `none`: not yet triaged or insufficient evidence to rank.

Do not mark every security, infrastructure, or agent-discovered item high. Explain unusual priority through impact and evidence.

## Split work and use relations

Split an item when it contains independently deliverable outcomes, unrelated components, separate rollout risks, or more work than one agent can coherently own.

Use a parent item or epic for the overall outcome and sub-items for concrete deliverables. A parent is not Done until required children and integration-level acceptance criteria are complete.

Use relations deliberately:

- `blocking`: this item prevents the related item;
- `blocked_by`: this item cannot finish until the related item does;
- `duplicate_of`: this item repeats the canonical item;
- `relates_to`: useful context without an execution dependency.

Inspect existing relations with `agentgateway_plane_list_work_item_relations`. Resolve available relation definitions with `agentgateway_plane_list_work_item_relation_definitions` when needed, then create the dependency with `agentgateway_plane_create_work_item_relation`. Do not encode dependencies only in prose when relations are available.

## Definition of Done

Move an implementation item to Done only when all applicable conditions are true:

- every acceptance criterion has been verified;
- relevant tests, validation, build, lint, or operational checks pass;
- documentation and configuration are updated when required;
- no unresolved blocker or incomplete required sub-item remains;
- no known untracked regression was introduced;
- useful commits, pull requests, deployments, dashboards, or evidence are linked or named;
- a completion comment records what changed and how it was verified; and
- no secret or sensitive output was placed in Plane.

A failed or unavailable verification is not a pass. Record it and keep the item out of Done unless the acceptance criteria explicitly allow the limitation.

## Safe MCP operation sequence

For an existing item:

1. Retrieve it with `agentgateway_plane_retrieve_work_item`; use `agentgateway_plane_retrieve_work_item_by_identifier` if you have a human-readable identifier rather than the UUID.
2. Read current discussion with `agentgateway_plane_list_work_item_comments`. Use `agentgateway_plane_list_work_item_activities` only when the history of changes matters.
3. If dependency, duplication, or handoff context matters, call `agentgateway_plane_list_work_item_relations`.
4. Resolve only the IDs you actually need:
   - state → `agentgateway_plane_list_states`
   - assignee → `agentgateway_plane_get_project_members`
   - label → `agentgateway_plane_list_labels`
5. Make the smallest mutation:
   - title, description, priority, state, or other core fields → `agentgateway_plane_update_work_item`
   - assignee → `agentgateway_plane_manage_work_item_assignee`
   - label → `agentgateway_plane_manage_work_item_label`
   - relation → `agentgateway_plane_create_work_item_relation`
6. When this policy requires durable discussion, use `agentgateway_plane_create_work_item_comment`.
7. Retrieve the item again with `agentgateway_plane_retrieve_work_item` to confirm the resulting state.

For a new item:

1. Search for duplicates with `agentgateway_plane_search_work_items`. Use `agentgateway_plane_list_work_items` only when you need an exhaustive list of project issues.
2. Resolve the intended state with `agentgateway_plane_list_states`; default to Backlog unless direct Todo placement is justified.
3. Create the generic item with `agentgateway_plane_create_work_item`, including a specific title, HTML description, defensible priority, and only necessary label fields. Do not send `type_id`.
4. Retrieve the created item with `agentgateway_plane_retrieve_work_item` and report its human-readable identifier.

For comments:

- list discussion → `agentgateway_plane_list_work_item_comments`
- add a durable comment → `agentgateway_plane_create_work_item_comment`
- correct an existing comment → `agentgateway_plane_update_work_item_comment`
- do not delete comments with `agentgateway_plane_delete_work_item_comment` merely to clean up history; delete only when explicitly requested or when sensitive data was accidentally posted and deletion is appropriate.

For relations:

- inspect dependencies → `agentgateway_plane_list_work_item_relations`
- inspect supported relation definitions when necessary → `agentgateway_plane_list_work_item_relation_definitions`
- add a dependency/duplicate/context relation → `agentgateway_plane_create_work_item_relation`
- remove a relation → `agentgateway_plane_remove_work_item_relation` only when it is wrong or no longer true.

Do not use project administration, state creation, label creation, cycles, modules, releases, customers, intake, estimates, work logs, or other Plane management tools during normal ticket work unless the user explicitly asks for that operation.

Never mutate project-wide states, labels, workflows, or configuration merely to complete a normal ticket unless explicitly requested.

## Final checks

Before creating or moving to Todo:

- Is the outcome clear and independently testable?
- Is it distinct from existing work?
- Is the state and priority honest?

Before moving to Done:

- Which evidence proves each acceptance criterion?
- What validation ran, and what was its result?
- Is any review, deployment, or dependency still pending?
- Are follow-ups truly separate and linked?

If a required answer is missing, do not mark Done.
