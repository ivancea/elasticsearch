# "Any" for ES|QL controls: presentation script (~25 min)

Background doc: `KIBANA_ANY.md`. Numbers are for the default 7-day window and drift slightly over time (≈).

**Dashboards:**

- **Scenarios** ("1. ES|QL controls: Any - scenarios"): templates, no ES change.
  http://localhost:5601/app/dashboards#/view/ab0a31b0-e2f1-4140-b942-60bc7c9be5e6
- **Functions** ("2. ES|QL controls: Any - functions"): the same sections, with the prototype ES functions.
  http://localhost:5601/app/dashboards#/view/bb7f531b-bc9f-41d8-9859-b3c3c63e6d1c
- **Include/exclude** ("3. ES|QL controls: Any + include/exclude"): optional, only if asked.

**Setup:** open each dashboard, hard-reload, then More → Reset changes. Collapse every section except the one
you're presenting.

**How to show things:**

- **The query behind a panel:** panel menu (⋮) → Edit visualization, show the ES|QL, then Cancel.
- **The params Kibana sends:** panel menu (⋮) → Inspect → View: Requests → Request tab, then look at `params`.

---

## 1. Why (2 min, no dashboard)

- ES|QL controls can't say "Any". Kibana forces a value, so dashboards open pre-filtered, integration dashboards
  can't ship a neutral default, and "Select all" misses values that appear later. Issue #136735 plus Slack.
- What "Any" should mean: no filter, documents without the field kept, any-value matching on multivalued fields.
  For breakdowns, "no breakdown".
- Constraint: it has to work in Lens, Discover, alerts and Agent Builder, without Kibana rewriting queries.

## 2. The idea (1 min, no dashboard)

"Any" is `null`, and the author writes the "Any" branch:

```esql
| WHERE ?os IS NULL OR MV_INTERSECTS(?os, os)
```

- No ES change needed. For "Any", ES removes the filter entirely; for values, it pushes it down to Lucene.
- `MV_INTERSECTS` = any shared value, like classic controls. `==` drops multivalued documents, and `MV_CONTAINS`
  means "all values selected".

## 3. Demo: Scenarios dashboard (10 min)

Kibana demo patch, to mention once: controls can be cleared, an empty control sends `null` and shows "Any", and
there's an optional "(No value)" option.

### Section 1 "Single value field (os)"

1. Show that the **Single value · OS** control reads "Any" (empty).
   - **Matching documents** ≈ 1,970 (all documents). Its secondary number ≈ 274 is the documents without `os`,
     so "Any" keeps blanks.
   - **Documents by OS** lists macos, linux, windows and "(no os)".
2. Open **Documents by OS** → Edit visualization. Show the `// Filter start` … `// Filter end` block: one line,
   `?sv_os IS NULL OR MV_INTERSECTS(?sv_os, os)`. Cancel.
3. Select `linux` in **Single value · OS**. Matching documents ≈ 552, and the table shows only linux.
4. Click `linux` again to clear it, and everything comes back. Point out that this is a single-select that can be
   cleared, which Kibana blocks today.

### Section 2 "Multivalue field (tags): Any and blank flag"

1. **Multivalue · Tags** = "Any": **Documents by tag combination** includes "(no tags)" ≈ 493 and combinations
   like "beta, prod".
2. Select `prod` in **Multivalue · Tags**. The table keeps every combination containing prod ("prod", "beta,
   prod", …): that's any-value matching on a multivalued field.
3. Set **Multivalue · Include docs without tags** to `true`. "(no tags)" comes back next to the prod rows
   (Matching ≈ prod + 493).
4. Clear **Multivalue · Tags** with the flag still `true`: everything is shown, and the flag has no effect.
   - Why: "Any" already includes blanks. A separate flag can't express "blanks only"; sections 4 and 5 solve that.
5. Optional: Edit visualization on **Documents by tag combination** to show the 3-line `WHERE`.

### Section 3 "STATS BY: breakdown with 'Any' (one group) and the ??field gap"

1. **Breakdown · Group by (value control + CASE)** = "Any": **Documents over time by group** shows one series,
   and **Documents by group** shows one row, "all documents".
2. Select `os` in that control. The chart splits by OS, and the table lists OS values.
3. Edit visualization on **Documents by group**: `EVAL group = CASE(?bd_field == "os", os, …, "all documents")`.
   - Why it works: it's a value control, so `null` is fine.
   - The cost: the field list is repeated in the query, and the column is always named `group`.
4. Now **Breakdown · Group by (??field; clearing shows the gap)** (preset to `host`): **Documents BY ??field**
   groups by host. Clear the control, and the panel errors with "Query parameter [??bd_ident] is null".
   - That's the real gap: `??field` can't be "unset" today. ES work, shown in step 5 of this script.
5. Select `host` again, to leave the panel in a working state.

### Section 4 "'(No value)' option via the __NULL__ sentinel"

1. Open **Null label · Tags (multivalue)**. The list has "(No value)", which is the Kibana label for the sentinel
   `__NULL__` that the control's values query adds.
2. Select `prod` + "(No value)": **Documents by tag combination** shows prod rows plus "(no tags)".
3. Clear it, then select only "(No value)": only "(no tags)" ≈ 493. "Blanks only" is now expressible.
4. Caveat to say out loud: the sentinel is a string, so this only works for string fields, and it would also match
   a real `"__NULL__"` value. Clear the control.

### Section 5 "'(No value)' option via the ?x__nulls companion param"

1. Open **Companion · Secure (boolean)**: "(No value)", `false`, `true`. Select `true` + "(No value)".
   - **Documents by secure** shows `true` ≈ 1,147 and "(no secure)" ≈ 266, and **Matching documents** ≈ 1,413.
   - "true or blank" on a boolean, which classic DSL controls can't do.
2. Panel menu on **Documents by secure** → Inspect → Requests → Request. Show `params`: `nv_secure: ["true"]`
   plus `nv_secure__nulls: true`. Kibana derives the second param from the control.
3. Edit visualization: `(?x IS NULL AND NOT ?x__nulls) OR MV_INTERSECTS(...) OR (?x__nulls AND f IS NULL)`.
   - Why `x__nulls`: param names only allow letters, digits and `_`, so `x.nulls` isn't possible.
   - Kibana only sends it when the query references it.
4. Clear Secure, then select only "(No value)" in **Companion · Priority (integer)**. **Documents by priority**
   shows only "(no priority)", a numeric field with "blanks only". Clear it.

## 4. Discarded alternatives (3 min, when someone asks)

| Idea | Why we thought of it | Why discarded / not needed |
|---|---|---|
| Magic `ANY` value | Simplest for users | Already rejected by ES. It's ambiguous (`!= ANY`?), and `null` + an explicit branch covers it |
| Kibana removes query parts when "Any" | Grafana, Metabase and Superset do it | Unsafe beyond a simple `AND`, e.g. `x AND CASE(...)` or `CONCAT(x, MV_CONCAT(?h))`. Every consumer would need it, alerts included |
| Macros (`IS_DEFINED(?p, a, b)`, or around clauses) | Short, and can handle an unset `??field` | About 8 weeks for clauses, plus a second implementation in Kibana (editor, Composer for alerts) that must stay in sync. `null` covers filters, and `OPTIONAL` covers `BY` |
| `LIKE ?x` with `*` | Works for keyword fields | Strings only, no multi-select, and a `null` pattern is a parse error |
| One structured param per control | One param for every mode | New request format and function; the companion param + sugar gives the same |

## 5. Demo: Functions dashboard (5 min)

Why: the templates work but are verbose. The prototype functions just expand to the same templates, so results
and Lucene pushdown are identical (verified on 17 cases).

1. Section 1: Edit visualization on **Documents by OS**. The filter is now `WHERE IN_SELECTION(os, ?sv_os)`.
   Select `linux` and get the same ≈ 552 as on the Scenarios dashboard.
2. Section 5: Edit visualization on **Documents by secure**:
   `IN_SELECTION(secure, ?nv_secure, {"nulls": ?nv_secure__nulls})`, with no `TO_BOOLEAN` because the function
   casts. Select `true` + "(No value)" in **Companion · Secure (boolean)**: ≈ 1,413, as before. Clear it.
3. Section 3 "STATS BY: FIELD_OR … and OPTIONAL …", with the **Breakdown · Group by (??field)** control:
   - Cleared: **Documents by FIELD_OR group** shows one row, "all documents". **Documents BY OPTIONAL(??fn_bd)**
     shows only `docs`, with no error: the key is dropped, and Lens copes.
   - Select `os`: both tables and **Documents over time by FIELD_OR group** split by OS, and the OPTIONAL table
     gains an `os` column.
   - Edit visualization on both: `BY group = FIELD_OR(??fn_bd, "all documents")` and `BY OPTIONAL(??fn_bd)`.
   - It's opt-in per query: a plain `BY ??x` still errors when cleared (Scenarios dashboard, section 3).
4. Clear the control. Optionally mention `IN_RANGE_SELECTION(f, ?lo, ?hi)` (a `null` bound is unbounded).

## 6. Optional: Include/exclude dashboard (only if asked)

- Not part of the issue, but classic controls have Exclude.
- Select `linux` in **OS** and `exclude` in **OS mode**: everything except linux, including documents without
  `os`, like DSL `must_not`.
- Edit visualization: one boolean comparison per filter, `(mode == "include") == (match)`.

## 7. Asks (2 min)

**Kibana:**

- Allow clearing controls, send `null`, and label empty controls "Any".
- Allow `null` in alert inlining (`esqlControlVariableIsComposerInlinable`).
- Optional "(No value)" option that sends `?x__nulls`.
- Generate the filter snippet when creating a control.

**ES:**

- Ship `MV_INTERSECTS` pushdown (on `main`).
- Type widening, or document the casts.
- Decide on the sugar (`IN_SELECTION`, `OPTIONAL`/`FIELD_OR`).
- Small fixes: `null` pattern in `LIKE`, and make `IN (?list)` work or fail loudly.

## 8. Questions to leave with them (1 min)

- Breakdown "None": drop the key (`OPTIONAL`), or keep one constant group (`FIELD_OR`)? Lens tables cope with a
  missing column; charts are still unchecked.
- "(No value)": adopt the companion param `?x__nulls` now, or later?
- Should Kibana generate the sugar (or the template) when users create a control?
