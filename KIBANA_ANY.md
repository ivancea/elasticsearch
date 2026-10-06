# ES|QL controls: "Any" selection

Analysis of [elasticsearch#136735](https://github.com/elastic/elasticsearch/issues/136735)
("Add ANY option to named parameters") from the Kibana side.

Related:

- [elasticsearch#137554](https://github.com/elastic/elasticsearch/issues/137554): macro-like `IS_DEFINED` construct (the preferred direction so far).
- [elasticsearch#144289](https://github.com/elastic/elasticsearch/issues/144289): expand list-valued params in `IN (?p)`.
- [elasticsearch#147448](https://github.com/elastic/elasticsearch/issues/147448) / [PR #147748](https://github.com/elastic/elasticsearch/pull/147748): empty list `[]` in named params is now a 400.
- [elasticsearch#134529](https://github.com/elastic/elasticsearch/issues/134529): Lucene pushdown for `MV_CONTAINS`.
- Kibana: [kibana#241603](https://github.com/elastic/kibana/issues/241603) (forced selection), [kibana#243618](https://github.com/elastic/kibana/issues/243618) (can't save a control with no values), [kibana#265744](https://github.com/elastic/kibana/issues/265744) (user request), [kibana#237228](https://github.com/elastic/kibana/issues/237228) (multi-select via `MV_CONTAINS`).
- Customers: [enhancements#26524](https://github.com/elastic/enhancements/issues/26524) (Vanguard), [kibana-team#2093](https://github.com/elastic/kibana-team/issues/2093) (user insights), [integrations#19758](https://github.com/elastic/integrations/pull/19758) (OTel RUM dashboards sending `null` as a workaround).

## 1. Problems

### 1.1 Main problem

An ES|QL control cannot express "Any": "don't apply this control, show everything". Classic (DSL) controls
can: with no selection, no filter is added. Consequences:

- Kibana forces at least one selected value ([kibana#241603](https://github.com/elastic/kibana/issues/241603)).
- A control whose values query returns nothing can't be saved ([kibana#243618](https://github.com/elastic/kibana/issues/243618)).
- There is no "unselect all"; going from "Select all" back to one value means removing values one by one.
- Shipped dashboards (integrations) can't pick a valid default because they don't know the user's data.
- Customers duplicate panels or whole dashboards, one copy with the control and one without.

"Select all" is not "Any". The option list can be truncated, new values may appear later, and "Any" must also
keep documents where the field is blank or missing.

### 1.2 Current Kibana behaviour

In `src/platform/plugins/shared/controls/public/controls/esql_control/esql_control_manager.ts`
(`getEsqlVariable`), an empty selection is sent as:

- `''` for single-select, which filters on the empty string and returns nothing (verified on 9.5.1);
- `[]` for multi-select. [#147748](https://github.com/elastic/elasticsearch/pull/147748) made this a 400 in
  April 2026, but [#152098](https://github.com/elastic/elasticsearch/pull/152098) (June 2026) changed it to be
  treated as `null`. On 9.5.1, `[]` behaves like `null` (verified).

Single-select must change to `null`. Multi-select already reaches ES as "no value", so any query written as
`?x IS NULL OR ...` already treats it as "Any".

### 1.3 Special cases and requirements

**R1. Single-value filter.** `WHERE host == ?host`. With "Any", the filter should not apply. On a multi-valued
field, `==` returns `null` (with a warning) and drops the document, unlike classic controls; see the note under D.

**R2. Multi-select filter.** Kibana's guidance today is `WHERE MV_CONTAINS(?host, host)`. Verified on 9.5.1:

- `MV_CONTAINS(?host, host)` is true when `host` is missing, so a `host IS NOT NULL` guard is needed.
- It means "all of the document's values are selected". A document with `host: [a, b]` doesn't match a
  selection of `[a]`, whereas classic (DSL) controls match any shared value.
- `MV_INTERSECTS(?host, host)` (available in 9.5, and already linked from Kibana's control flyout) means "any
  shared value", like DSL controls, and is false for missing values. It's the better building block.
- Both functions require exact type matches, with no implicit cast: an integer param against a `long` field, or a
  string param against an `ip` field, is a 400. ES types small JSON numbers as `integer`, so a multi-select on a
  `long` field (common, e.g. status codes) fails today. Kibana must add a cast based on the field type
  (`TO_LONG(?x)`, `TO_IP(?x)`), or ES must widen types. `==` casts implicitly, so single-select is fine.
- `host IN (?host)` with a list param returns no rows, without an error. The fix PR
  ([#144290](https://github.com/elastic/elasticsearch/pull/144290)) for
  [#144289](https://github.com/elastic/elasticsearch/issues/144289) was closed without merging.
- Pushdown: on 9.5.1 neither function is pushed down to Lucene (runs as a `FilterOperator`). On `main`,
  `MV_INTERSECTS` is pushed down as a `terms` query in either argument order. `MV_CONTAINS` is only pushed down
  as `MV_CONTAINS(field, list)` ([#150193](https://github.com/elastic/elasticsearch/pull/150193)), not in the
  order controls use.

How classic (DSL) options-list controls filter (`filter_utils.ts`): one value builds `buildPhraseFilter` (a
`match_phrase`); several values build `buildPhrasesFilter`, a `bool` / `should` with one `match_phrase` per value
(`kbn-es-query` `phrases_filter.ts`). A document matches if any of its values equals any selected value, so it's
"any", not "all". Exclude negates the whole filter (`meta.negate`, a `must_not`).

The three possible meanings in ES|QL, and which one matches classic controls (verified on 9.5.1):

| Query | Meaning | Selection `[a, b]`, field `[a, c]` | Field missing | Classic-control equivalent |
|---|---|---|---|---|
| `MV_INTERSECTS(?sel, field)` | At least one value appears on both sides (argument order doesn't matter) | true | false | Yes: phrases filter |
| `MV_CONTAINS(?sel, field)` | All of the field's values are selected | false | true (needs an `IS NOT NULL` guard) | No |
| `MV_CONTAINS(field, ?sel)` | The field has all the selected values | false | false | No |

So the classic-control equivalents are `MV_INTERSECTS(?sel, field)` for a selection, and
`NOT MV_INTERSECTS(?sel, field)` for Exclude (which keeps documents without the field, like DSL `must_not`).

**R3. "Any" keeps nulls.** Documents with the field blank or missing must stay. Replacing the parameter with a
"match everything" value (e.g. `LIKE "*"`) drops them.

**R4. Complex predicates.** The parameter can appear anywhere in an expression: `LIKE`, ranges, `NOT`, `OR`,
or nested in functions. The meaning of "Any" can't be derived automatically:

- `x AND CASE(x, a, ?host)`: replacing the `CASE` with `true` also throws away `a`.
- `CONCAT(x, MV_CONCAT(?host)) == "foo"`: there is no sensible "removed" form.
- `NOT host == ?host`: replacing the comparison with `true` gives `NOT true`, which filters everything.

So any solution that removes parts of the query automatically only works for a fixed list of simple shapes. The
author has to say what "Any" means.

**R5. Removing a `STATS BY` key.** Breakdown controls use `STATS ... BY ??field`. "None" should drop that
grouping key, and if it was the only key the query becomes a global aggregation. Unlike `WHERE`, this needs a
structural change, but in one well-defined place (a whole grouping key).

ES|QL has two parameter markers:

- `?x` means whatever the request declares: `{"x": "host"}` is a value, `{"x": {"identifier": "host"}}` a
  field or function name, `{"x": {"pattern": "host*"}}` a name pattern.
- `??x` (the "double parameter marker", `doubleParameter` in `EsqlBaseParser.g4`) is always a name, even when
  the request sends a plain string.

Kibana uses `??` for field and function controls and `?` for value controls. Neither form can carry "no field"
today: a `null` `??x` is a parse error ("Query parameter [??x] is null", `ExpressionBuilder.visitDoubleParam`),
and `RequestXContent` requires a string for `?x` declared as an identifier.

**R6. Lens and Discover column binding.** Lens stores a breakdown dimension as `??variable` rather than as a
field name. It finds the column by matching the column name to the variable's current value
(`mapVariableToColumn` in `kbn-esql-utils`, `mapToOriginalColumnsTextBased` in Lens). Discover does the same in
`replaceColumnsWithVariableDriven`, and the Discover grouped-documents layout (`cascaded_documents_helpers`)
reads `STATS BY ??field` to build per-group sub-queries. If the column disappears or is renamed, these break. It's
unverified how the XY chart renders when the bound breakdown column is missing.

OpenSearch Dashboards handles a renamed column differently: saved charts bind axes by column name, and when a
name is missing, `reuseAxesMapping` refills that axis with an unused column of the same type (see 6.2). Kibana
could do the same instead of matching by variable value.

**R7. Blank selection.** Users may want to filter on "no value", alone or together with values (e.g. `true` +
blank on a boolean field). Neither control type offers this:

- ES|QL controls drop `null` rows from the values query (`getESQLSingleColumnValues`).
- Classic (DSL) controls have no blank option. "Exists" and values are mutually exclusive
  (`selection_utils.ts`, `filter_utils.ts`). The only way to get blanks is Exclude + Exists ("does not
  exist"). "true + blank" is only reachable as Exclude `false`, which relies on knowing every other value and
  drops documents with `[true, false]`.

`null` can't mean both "Any" and "blank", so blank needs a second signal.

**R8. Exists / Exclude, as in classic controls.** Classic controls offer Exists (`field IS NOT NULL`) and Exclude
(negate). ES|QL controls hide both (`hide_exists: true`, `hide_exclude: true` in `get_esql_control_factory.tsx`).
Exclude in DSL (`must_not` around the phrases filter) drops every document that has any selected value, and keeps
documents with no value. In ES|QL, `NOT MV_INTERSECTS(?host, host)` does the same: `MV_INTERSECTS` returns `false`
(not `null`) for a missing field, so `NOT` keeps those documents (verified, section 7). By contrast,
`NOT host IN (...)` or `host != ?host` drop them, because comparisons with `null` are never true.

**R9. Every consumer.** Variables are used by:

- Lens ES|QL charts;
- Discover panels and the Discover app;
- Vega;
- custom content panels;
- CSV export;
- change point;
- the Metrics experience;
- controls whose values query uses another control;
- alerting rules.

A solution that needs Kibana to rewrite queries has to be built into each of them.

**R10. Text form for alerting.** Alert rules have no controls, and a v2 rule stores only a query string. The
executor binds only `_tstart`/`_tend` (`RESERVED_ESQL_PARAMS`). When a rule is created from Discover or a
visualization, Kibana inlines the current control values into the query text. In
`x-pack/platform/packages/shared/response-ops/alerting-v2-rule-form/utils/esql_rule_utils.ts`
(`inlineEsqlVariables`) this is done with Composer, the query builder in `@elastic/esql`:
`esql(query, params).inlineParams().print()`. The legacy "create rule from visualization" path uses string
replacement instead (`parseEsqlVariables`). Any parameter left unresolved blocks saving. So "Any" (and
"None" for `??field`) must have a valid text form, or rules must store params next to the query.

**R11. Existing queries.** Saved dashboards already use `== ?x`, `MV_CONTAINS(?x, f)` and `BY ??field`. Making
them work unchanged would be a bonus, not a must.

**R12. Pushdown.** The resulting filter should still be pushed down to Lucene.

**R13. Kibana editor support.** Any new syntax needs Kibana's parser, validation and autocomplete, and the
"create control from query" flow, to recognise it. That flow currently looks for `MV_CONTAINS` to default to
multi-select.

**Special positions:**

- **PromQL label matchers** (`{host=?host}`) can take a value control. "Any" there means dropping the matcher
  or using `=~".*"`, which in PromQL also matches series without the label.
- **Out of scope:**
  - `??function` controls (`STATS ??agg(x)`) and time-literal controls (`BUCKET(@timestamp, ?interval)`):
    "Any" has no meaning there.
  - Queries Kibana builds itself (Discover histogram breakdown, Metrics grid dimensions): Kibana can simply
    omit the part, so no ES support is needed.

## 2. Solutions

### A. Kibana rewrites the query

Before sending, Kibana uses the ES|QL syntax tree to drop the filter or `BY` key that uses an "Any" parameter.

- Pros:
  - No ES change.
  - Existing queries work unchanged.
- Cons:
  - It's automatic removal, so it fails for complex predicates (R4).
  - It must be implemented in every consumer (R9), including server-side ones such as CSV export and alerting.
  - Composer inlining needs the same logic (R10).
  - API users get nothing.
  - The query that runs differs from the one the user wrote, which is confusing when debugging.

### B. `WHERE host LIKE ?host` with `*` for "Any"

- Pros:
  - Simple.
  - Works today for keyword fields.
- Cons:
  - Single values only.
  - Drops nulls (R3).
  - Doesn't work for non-string types.
  - Existing `==` queries must be rewritten.
  - Doesn't help `BY`.

### C. A magic `ANY` / "anti-null" value

A special value that makes any comparison true.

- Pros:
  - Existing queries would work unchanged.
- Cons:
  - Unsound under `NOT`/`OR` and inside functions (R4).
  - Unclear in `STATS BY`.
  - Explicitly rejected by the ES team.

### D. `CASE` + `null` (or the simpler `OR` form)

Kibana sends `null` for "Any", and the author writes the "Any" branch explicitly. No `CASE` is needed; a plain
`OR` folds the same way (verified):

```esql
WHERE ?host IS NULL OR host == ?host              // single-select
WHERE ?host IS NULL OR MV_INTERSECTS(?host, host) // multi-select
```

This is the same pattern Azure Data Explorer documents (`where x in (_x) or isempty(_x)`). The `CASE` form
also works: `WHERE CASE(?host IS NULL, true, MV_INTERSECTS(?host, host))`.

Verified on 9.5.1 (section 7): all `?params` are literals, so the optimizer folds the condition. With "Any", the
filter disappears entirely (no Lucene query, no filter operator). With a value, single-select becomes a Lucene
`term` query. Multi-select runs as a filter operator on 9.5.1; on the 9.6 snapshot, `MV_INTERSECTS` is pushed
down to Lucene for both a single value and a list (verified).

`==` versus `MV_INTERSECTS` for single-select: on a multi-valued field, `field == ?x` drops every document with
more than one value (verified on the 9.6 snapshot: `tags == "prod"` matches 187 documents, none multi-valued;
`MV_INTERSECTS("prod", tags)` matches 575, of which 388 multi-valued). So the form that matches classic controls
is `MV_INTERSECTS` for single-select too:

```esql
WHERE ?host IS NULL OR MV_INTERSECTS(?host, host)                 // single- or multi-select, keyword
WHERE ?status IS NULL OR MV_INTERSECTS(TO_LONG(?status), status)  // non-keyword fields need a cast
```

The cast is needed because `MV_INTERSECTS` requires exact types, whereas `==` casts implicitly. On
single-valued fields both forms return the same rows.

- Pros:
  - Works today; no ES change.
  - The author decides what "Any" means, so complex predicates are fine (R4).
  - Works in every consumer (R9).
  - Inlines naturally as `null` for alerting (R10), with one small Kibana change (see Kibana work).
  - Single-select pushes down today; multi-select pushes down once `MV_INTERSECTS` pushdown ships.
- Cons:
  - Less natural than a plain filter, and hard to discover without Kibana generating it.
  - Existing queries must be edited.
  - Cannot remove a `BY ??field` key: identifier params can't be `null`, and an unset `??field` fails
    resolution even in the unused `CASE` branch.
  - No blank, Exists or Exclude support (R7, R8) on its own.
- Kibana work:
  - Send `null` instead of `''` for an empty single-select (`[]` is already treated as `null`).
  - Allow `null` in `esqlControlVariableIsComposerInlinable`, which currently accepts only strings, numbers and
    non-empty arrays.
  - Recommend `MV_INTERSECTS` instead of `MV_CONTAINS` for multi-select, with a cast for non-keyword fields.
  - Optionally, have "create control" generate the snippet for the user.

### D+. `CASE` + `null` + flag params

Like D, plus a second signal per control for blank / Exists / Exclude. ES rejects `null` entries and mixed types
in list params, so the second signal is one of:

- **a boolean param from a separate control** (e.g. `?host_blank`): works for every field type and can't collide
  with real data;
- **a sentinel string in the list** (e.g. `"__blank__"`): string fields only, and can collide with a real value; or
- **a companion boolean param derived from the same control** (`?host__nulls`): the "(No value)" option sits in the
  values dropdown like the sentinel, but Kibana sends it as a separate boolean. Works for every field type.

Boolean flag (a separate "include documents without a value" control):

```esql
WHERE ?host IS NULL OR MV_INTERSECTS(?host, host) OR (?host_blank AND host IS NULL)
```

The flag only widens an actual selection. With the values control on "Any" it has no effect, because "Any" already
includes blanks. An earlier version treated the flag as one more selected option, so flag on + "Any" showed only
blanks; in the demo that read as a bug, because a separate control set to "Any" is understood as "don't filter on
this field".

Sentinel (string fields only), with "(No value)" as an option inside the values dropdown:

```esql
WHERE ?host IS NULL OR (MV_CONTAINS(?host, "__blank__") AND host IS NULL) OR MV_INTERSECTS(?host, host)
```

Flag versus sentinel: the flag is type-safe and simple, but it can't express "only documents without a value"
(that would contradict "Any"). The sentinel can, because "(No value)" is an explicit choice in the same dropdown,
alone or with values. That's the case for the "(No value)" option: it covers "blanks only", which a separate flag
can't express unambiguously.

Companion param (any field type), with "(No value)" as an option inside the values dropdown:

```esql
WHERE (?host IS NULL AND NOT ?host__nulls)
   OR MV_INTERSECTS(?host, host)
   OR (?host__nulls AND host IS NULL)
```

- The control has an "include a (No value) option" setting. Kibana keeps the marker option out of `?host` and
  sends whether it's selected as `?host__nulls` (always `true`/`false`). Nothing selected sends `null` + `false`
  ("Any"). "(No value)" alone sends `null` + `true` (blanks only). Values + "(No value)" sends both.
- It has the sentinel's semantics without its limits: `?host` keeps the field's type (numbers stay numbers, a
  boolean field can offer `true` + "(No value)", which classic controls can't), and no real value can collide.
- **Naming:** parameter names only allow letters, digits and `_` (lexer rule `NAMED_OR_POSITIONAL_PARAM` and the
  request-side name check), so `?host.nulls` is invalid; `?host__nulls` is the closest readable form. Kibana only
  adds it when the query references it. If a control is literally named `host__nulls`, that control wins.
- If the query references `?host__nulls` but Kibana doesn't send it, ES fails with "Unknown query parameter",
  which surfaces a misconfigured control instead of silently filtering.
- With "Any" the condition folds to `true` and disappears; values + "(No value)" is pushed down to Lucene entirely
  (verified on the 9.6 snapshot, section 7).

Exclude, keeping blanks like DSL `must_not`, and Exists:

```esql
WHERE ?host IS NULL OR NOT MV_INTERSECTS(?host, host)                // Exclude (keeps blanks)
WHERE host IS NOT NULL                                                // Exists
```

Verified on 9.5.1 (section 7): every combination returns the expected rows (Any; values; blank only;
values + blank; Exclude). The section 7 checks used the earlier flag semantics ("blank only" via the flag); the
current flag form was verified on the 9.6 snapshot: "Any" gives 2,000 with the flag on or off, `prod` 575,
`prod` + flag 1,076. Both forms fold to a plain filter such as `host IS NULL OR MV_INTERSECTS(...)`. The
sentinel collision is real: a document whose `host` is literally `"__blank__"` also matched.

- Pros:
  - Everything D gives.
  - Blank, Exists and Exclude, including "value + blank", which DSL controls can't do.
  - Exclude can keep blanks, matching DSL behaviour.
- Cons:
  - Even more verbose.
  - Kibana sends more than one variable per control, and the naming convention (`?host_blank`, `?host__nulls`,
    ...) must be defined and documented.
  - Still no `BY` removal.
- Kibana work: as D, plus UI for blank / Exists / Exclude in ES|QL controls and sending the extra params. For the
  companion param: a control setting, the marker option, and deriving `?<name>__nulls` in `getNamedParams` (the
  demo does this in about 40 lines). Alert inlining must also inline the companion.

### E. `IS_DEFINED(?p, if_present, if_absent)` as an expression ([#137554](https://github.com/elastic/elasticsearch/issues/137554))

```esql
WHERE IS_DEFINED(?host, host IN (?host), true)
```

It can be shorthand for D, plus support for an "unset" parameter: absent from the request, or an explicit
marker, which is different from a real `null`. ES picks the branch before resolving names, so the unused branch
may reference an unset `??field`. Today a parameter used in the query but absent from the request is a 400
("Unknown query parameter [host]", verified), so ES must accept absent parameters for this.

- Pros:
  - Shorter and clearer than `CASE`.
  - Author-defined semantics (R4).
  - Works in every consumer.
  - It's a local rewrite of the call itself, not of the surrounding query, so it avoids the problems of
    automatic removal.
- Cons:
  - New language construct.
  - Doesn't remove a `BY` key on its own (needs F or G).
  - Blank / Exists / Exclude still need D+-style flags.
- Kibana work: the macro must also exist on the Kibana side:
  - **Editor support:** parser, validation and autocomplete must learn `IS_DEFINED`. The grammar is shared, but
    validation and autocomplete are hand-written.
  - **Alerting text form:** Composer can't inline "unset". Either Composer implements the same branch-picking
    rule (a second implementation of the macro, which must stay in sync with ES, including whether `null`
    counts as defined), or rules store params next to the query and the executor sends them (an alerting
    schema change).
  - **Create control:** the flow must recognise `IS_DEFINED` positions.

### F. `IS_DEFINED` around a whole clause

```esql
STATS c = COUNT(*) IS_DEFINED(??field, BY ??field, EMPTY)
```

- Pros: removes a `BY` key, or the whole `BY`, cleanly (R5).
- Cons:
  - Grammar-level macro; rough estimate about 8 weeks.
  - The output columns change, so Lens and Discover must handle a missing breakdown column (R6).
  - Same Kibana-side macro work as E: editor support and Composer/alerting.

### F2. Optional grouping key (a narrower F)

A marker only allowed on a top-level `BY` key (name to be decided):

```esql
STATS c = COUNT(*) BY OPTIONAL(??field)
```

When the parameter is unset, ES drops that key, and drops `BY` entirely if it was the only key.

- Pros:
  - Gives the semantics users expect ("no breakdown"), unlike G's single constant group.
  - It removes a structural part, but only in one place (a whole grouping key), so the AND/OR/CASE problem of R4
    doesn't arise. That should make it much cheaper than F's general clause macro.
- Cons:
  - New syntax, plus support for an unset `??` parameter (a `null` `??x` is a parse error today).
  - The output columns change, as with F (R6).
  - Kibana editor support for the new marker; Composer must drop the key when inlining for alerting.

### G. `IS_DEFINED` + group by a constant

```esql
STATS c = COUNT(*) BY g = IS_DEFINED(??field, ??field, null)
```

Grouping by a constant works in plain `STATS` (verified: `STATS c = COUNT(*) BY g = null` returns one row,
also combined with other keys). For a value parameter, `BY g = CASE(?f IS NULL, null, host)` already works
today. For `??field` it can't, because a `null` `??f` fails at parse time, so this needs E's "unset" support.

- Pros:
  - Expression-level only; no clause macro.
  - The result keeps a stable set of columns.
- Cons:
  - Returns one group (a single series) instead of no breakdown.
  - The column name becomes fixed (`g`) instead of following the field, so Lens and Discover must stop binding
    the column by the variable's value (R6), and labels show `g`. Re-binding by column type, as OpenSearch
    Dashboards does (6.2), would soften this.
  - Same Kibana-side macro work as E.

### H. Filter-parameter function

Inspired by Looker templated filters and Metabase field filters (see 6.3): one function takes the field and a
structured parameter describing the whole control state, and evaluates to the matching filter.

```esql
WHERE MATCHES_CONTROL(host, ?host)
```

`?host` would be, for example, `{"any": true}` or `{"values": ["a", "b"], "blank": true, "exclude": false}`. The
function name and parameter shape are placeholders.

- Pros:
  - One parameter per control covers Any, values, blank, Exists and Exclude for every field type (R1–R3, R7,
    R8), with no flag-naming convention.
  - It's an expression, so it folds to a plain filter: no query parts are removed (R4) and pushdown is kept.
  - It could be inlined for alerting as an ES|QL map literal (functions such as `MATCH` already take map
    options) (R10).
  - Kibana can generate `WHERE MATCHES_CONTROL(field, ?var)` when a control is created, and the editor only has
    to learn one function.
- Cons:
  - New function plus a structured parameter type on the ES side; the semantics of each mode need to be
    specified. Today a param object only accepts one of `value`, `identifier` or `pattern` (verified), so the
    request format must be extended.
  - Filters only; doesn't help `BY` removal (needs F or G).
  - The field is fixed in the query, so complex predicates still need D/E.

### X. Dropped: automatic removal of query parts based on an "unset" parameter

ES would replace each top-level `AND` part of a `WHERE` that references the parameter with `true`, and remove
`BY` keys that reference it. Dropped because it's only correct for simple filter shapes; see R4.

### Complementary work (not a solution for "Any" by itself)

- `MV_INTERSECTS` pushdown: on `main`, pushed down as a `terms` query in either argument order. Make sure it
  ships (or is backported), since it's the multi-select building block.
- Type widening in `MV_INTERSECTS` / `MV_CONTAINS` (integer param against `long` field, string param against
  `ip`), or Kibana adds casts. Without it, multi-select on `long` and `ip` fields fails.
- [#144289](https://github.com/elastic/elasticsearch/issues/144289): `host IN (?host)` expanding list params.
  Its PR was closed unmerged; today the query silently returns nothing. Either fix it or make it an error.
- [#147448](https://github.com/elastic/elasticsearch/issues/147448): `[]` is now treated as `null`
  ([#152098](https://github.com/elastic/elasticsearch/pull/152098)). Done.
- [#134529](https://github.com/elastic/elasticsearch/issues/134529): closed; pushes down `MV_CONTAINS(field,
  list)` only, not the `MV_CONTAINS(list, field)` order controls use.

### Templates and syntactic sugar per case

The "Template today" column works with no ES change and is what the demo dashboards use (section 8). The sugar
column is a proposal: one function that expands to exactly that template. `IN_SELECTION(field, ?param [, options])`
is a placeholder name (alternatives: `MATCHES_CONTROL`, `PARAM_FILTER`); it's a narrower, flat-param variant of H.

| Case | Control and params | Template today (`WHERE ...`) | Sugar proposal (`WHERE ...`) |
|---|---|---|---|
| Single value, keyword | `?os`: value or `null` | `?os IS NULL OR MV_INTERSECTS(?os, os)` | `IN_SELECTION(os, ?os)` |
| Single value, other types | `?status`: number or `null` | `?status IS NULL OR MV_INTERSECTS(TO_LONG(?status), status)` | `IN_SELECTION(status, ?status)` (casts to the field type) |
| Multivalue | `?tags`: list or `null` | `?tags IS NULL OR MV_INTERSECTS(?tags, tags)` | `IN_SELECTION(tags, ?tags)` |
| Blank flag (separate control) | `?tags` + `?tags_blank` | `?tags IS NULL OR MV_INTERSECTS(?tags, tags) OR (?tags_blank AND tags IS NULL)` | `IN_SELECTION(tags, ?tags, {"include_nulls": ?tags_blank})` |
| "(No value)" via sentinel (strings only) | `?tags` may contain `"__NULL__"` | `?tags IS NULL OR MV_INTERSECTS(?tags, tags) OR (tags IS NULL AND MV_CONTAINS(?tags, "__NULL__"))` | `IN_SELECTION(tags, ?tags, {"null_value": "__NULL__"})` |
| "(No value)" via companion (any type) | `?p` + derived `?p__nulls` | `(?p IS NULL AND NOT ?p__nulls) OR MV_INTERSECTS(?p, priority) OR (?p__nulls AND priority IS NULL)` | `IN_SELECTION(priority, ?p, {"nulls": ?p__nulls})` |
| Include / exclude | `?os` + `?os_mode` | `?os IS NULL OR (COALESCE(?os_mode, "include") == "include") == (MV_INTERSECTS(?os, os) OR ...)` | `IN_SELECTION(os, ?os, {"nulls": ?os__nulls, "exclude": ?os_mode == "exclude"})` |
| Text pattern | `?t`: pattern or `null` | `?t IS NULL OR host LIKE COALESCE(?t, "*")` | `IN_SELECTION(host, ?t, {"match": "like"})` |
| Range | `?lo`, `?hi`: bound or `null` | `?lo IS NULL OR MV_IN_RANGE(status, TO_LONG(?lo), TO_LONG(?hi))` | `IN_RANGE_SELECTION(status, ?lo, ?hi)` (`null` bound = unbounded) |
| Breakdown, one group (G) | `?bd`: field name as a value | `EVAL group = CASE(?bd == "os", os, ?bd == "region", region, "all documents")`, then `BY group` | `BY group = FIELD_OR(??bd, "all documents")` |
| Breakdown, no key (F2) | `??bd`: identifier or unset | Not possible today | `BY OPTIONAL(??bd)` |

Notes:

- **Shared semantics:** the sentinel and companion rows mean the same thing ("(No value)" is one more selected
  option, so it can be chosen alone), and so does `nulls` in the sugar. Only the transport differs: the
  companion keeps `?p` in the field's type. `include_nulls` is different on purpose: it only widens a selection and
  has no effect on "Any", because it comes from a separate control.
- **What the sugar adds beyond shorter text:**
  - `null` (or `[]`) is "Any", so the call folds to `true`.
  - Any-value semantics, like classic controls.
  - Casts the parameter to the field type, which removes today's strict-typing errors.
  - Folds to the same pushed-down Lucene query as the expanded template.
- **Open points for the sugar:**
  - Map options are literals today, so parameters such as `{"nulls": ?p__nulls}` would have to be allowed.
  - Whether `null` means "Any" inside the function, or only an explicit "unset" marker.
  - `FIELD_OR` and `OPTIONAL` need an unset or `null` `??` parameter to be accepted in that one position (a parse
    error today).

## 3. Coverage

Legend: Yes = covered, Partial = partially or with extra work, No = not covered, n/a = not applicable.

| Proposal | `== ?x` Any (R1) | Multi-select Any (R2) | Any keeps nulls (R3) | Complex predicates (R4) | `BY` key removal (R5) | Lens/Discover column binding (R6) | Blank selection (R7) | Exists / Exclude (R8) | All consumers, no Kibana rewrite (R9) | Text form for alerting (R10) | Existing queries unchanged (R11) | Pushdown (R12) | Ready soon |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A. Kibana rewrites the query | Yes | Yes | Yes | No | Yes | Partial: column disappears | Partial | Partial | No | Partial: Composer copy | Yes | Yes | Partial: Kibana work |
| B. `LIKE ?x` with `*` | Partial: keyword only | No | No | No | No | n/a | No | No | Yes | Yes | No | Partial | Partial |
| C. Magic `ANY` value | Yes | Yes | Partial | No | Partial | Partial | No | No | Yes | Partial | Yes | Partial | No: rejected |
| D. `CASE` + null | Yes | Yes | Yes | Yes | No | n/a | No | No | Yes | Partial: allow `null` | No | Partial | Yes |
| D+. `CASE` + null + flag params | Yes | Yes | Yes | Yes | No | n/a | Yes | Yes | Yes | Partial: allow `null` | No | Partial | Yes |
| E. `IS_DEFINED` expression | Yes | Yes | Yes | Yes | No | n/a | Partial: needs D+ flags | Partial: needs D+ flags | Yes | Partial | No | Yes | Partial |
| F. `IS_DEFINED` around a whole clause | Yes | Yes | Yes | Yes | Yes | Partial: column disappears | Partial: needs D+ flags | Partial: needs D+ flags | Yes | Partial | No | Yes | No: ~8 weeks |
| F2. Optional grouping key | n/a | n/a | n/a | n/a | Yes | Partial: column disappears | n/a | n/a | Yes | Partial: Composer drops key | No | n/a | Partial: new syntax |
| G. `IS_DEFINED` + constant group | Yes | Yes | Yes | Yes | Partial: one group | Partial: column renamed | Partial: needs D+ flags | Partial: needs D+ flags | Yes | Partial | No | Yes | Partial |
| H. Filter-parameter function | Yes | Yes | Yes | Partial: simple field filters only | No | n/a | Yes | Yes | Yes | Partial: map literal | No | Yes | Partial: new function |

Notes on some cells:

- **Pushdown, D/D+:** verified: the "Any" condition folds away entirely, and single-select becomes a Lucene
  `term` query. Multi-select with `MV_INTERSECTS` isn't pushed down on 9.5.1 but is on `main`. The `OR ... IS
  NULL` part of D+ blank is evaluated as a filter.
- **F2:** only addresses `BY`; combine with D/D+/H for filters.
- **Text form for alerting, D/D+:** one-line change in `esqlControlVariableIsComposerInlinable` to accept `null`.
- **Text form for alerting, E/F/G:** Composer resolves `IS_DEFINED` while inlining, or rules store params.
- **Column binding:** F requires Lens and Discover to cope with a missing column. G requires them to stop
  matching the column by the field name.
- **H, complex predicates:** H covers "field matches the control"; anything more complex still needs D/E.

## 4. Recommendation

1. Now, Kibana, no ES change (verified on 9.5.1):
   - Send `null` for an empty single-select (`[]` already works as `null`).
   - Generate filters as `?x IS NULL OR MV_INTERSECTS(?x, field)` for both single- and multi-select, with a cast
     for non-keyword fields (`TO_LONG`, `TO_IP`, ...). `field == ?x` drops multi-valued documents.
   - Replace the `MV_CONTAINS` guidance: it uses "all values" semantics, matches missing values, and fails on
     `long` fields.
   - Allow `null` when inlining for alerts.
2. Now, ES:
   - Ship `MV_INTERSECTS` pushdown (on `main`).
   - Widen types in `MV_INTERSECTS`/`MV_CONTAINS`, or document the casts.
   - Make `field IN (?list)` work or fail loudly; it silently returns nothing today.
3. Next: blank / Exists / Exclude, either with D+ (no ES change, naming convention needed; verified) or with H
   (one structured parameter per control; new function and param format). Within D+, the companion param
   `?x__nulls` is the best fit for a "(No value)" option: type-agnostic, no collisions, and "blanks only" is
   expressible.
4. Later, breakdown "None": F2 (optional grouping key) for "no breakdown", or G (constant group) as the cheaper
   alternative. Which one depends on how Lens handles a missing breakdown column, still to be checked in a
   running Kibana. Budget the Kibana-side work: editor support, and Composer or rule params for alerting.

Other tools (section 6) back this order. The in-language pattern of D is Microsoft's documented approach for
Azure Data Explorer. Text-level preprocessors (Metabase, Superset) are popular but produce invalid queries and
break static analysis. Nobody handles a breakdown of "None" well, so F/G would put ES|QL ahead rather than
catching up.

## 5. Open questions

- `BY` removal: when "None" is picked, should the breakdown column disappear (F2/F; Lens and Discover handle a
  missing column) or stay as a single constant group (G; column binding stops relying on the field name)?
- What does Lens render when a bound `??breakdown` column is missing from the response? Partly answered (section
  8.1): a data table bound to `??x` just drops the column, with no error. Charts with a missing `breakdown_by`
  column are still unchecked.
- Blank signal: boolean flag from a separate control, sentinel string (string fields only), or companion param
  `?x__nulls` derived from the control (all types; preferred so far)?
- Alerting: implement `IS_DEFINED` resolution in Composer, or let rules store params next to the query?
- Should "unset" be "parameter absent from the request", an explicit marker, or `null`? This decides whether a
  real `null` value can still be passed.
- Blank / Exists / Exclude: D+ flags or H (filter-parameter function)?

## 6. How other tools do it

Researched October 2026 from public documentation, community threads and, for OpenSearch Dashboards, its
source code.

### 6.1 Four approaches

1. **Text substitution plus a special "All" value** (Grafana variables, OpenSearch Dashboards, Splunk, Azure
   Workbooks). The tool pastes the value into the query text. "All" becomes every option joined together, or a
   custom wildcard (`.*` for Prometheus, `*` for Lucene and Splunk). Wildcards usually lose blanks. Comparable
   to option B.
2. **The author writes the "All" branch in the query language** (Azure Data Explorer, Azure Workbooks, Power BI
   with Kusto, Looker `_is_filtered`). Comparable to options D/E.
3. **A template preprocessor removes or generates query parts** (Metabase, Looker, Superset). A text-level macro;
   the closest relatives of E/F, but working on text rather than on the parsed query.
4. **The tool injects filters and grouping by understanding the language** (Grafana "Filter and Group by").
   Comparable to option A.

### 6.2 Per tool

**Grafana** ([variables](https://grafana.com/docs/grafana/latest/dashboards/variables/add-template-variables/),
[Filter and Group by](https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/filter-group-by/))

- "Include All option": "All" is every option joined, formatted per data source: `(a|b|c)` for Prometheus and
  InfluxDB, `("a" OR "b")` for Elasticsearch Lucene, `{a,b}` for Graphite. Grafana warns this "can become very
  long and can have performance problems".
- "Custom all value": a wildcard used instead (`.*`, `*`). It's never escaped, so it must be valid for the data
  source.
- "Filter and Group by" (formerly ad hoc filters, renamed in Grafana 13.1): key/value filters automatically added
  to every query of a data source. Filters work for Prometheus, Loki, InfluxDB, Elasticsearch and OpenSearch;
  group-by only for Prometheus and Loki. Each data source needs its own rewriting code.
- Open issues show the same problems we have:
  - [grafana#102236](https://github.com/grafana/grafana/issues/102236) tabulates, per query language, how to
    express "equals", "label not defined" and "any value including not defined". They differ everywhere. The
    author asked for conditional logic in queries, then backed off because templating "break[s] the capability to
    do static analysis of dashboard queries".
  - [grafana#102229](https://github.com/grafana/grafana/issues/102229): no way to select "empty"/undefined in a
    variable; "Allow custom values" rejects an empty string.
- PromQL is the only language with these semantics built in: `label=""` means "label missing", `label=~".*"`
  means "any value, including missing".

**OpenSearch Dashboards (PPL)** ([variables docs](https://docs.opensearch.org/latest/dashboards/visualize/visualization-editor/dashboard-variables/using-variables/);
source read at `main` `950d888`, 2026-09-29)

- Variables are raw text: `VariableInterpolationService.interpolate` regex-replaces `$name` / `${name}` in the
  query string. There is no value-versus-field distinction; the author decides by quoting (`'$service'` for a
  value, `` `$group_by` `` for a field). Single values get PPL escaping only (doubled single quotes, escaped
  backslashes). Multi-select becomes `('a', 'b')`, or `(1, 2)` for numbers and booleans, for use with
  `IN $var`.
- "All" is UI-only: a `__all__` pseudo-option (multi-select only) that selects every loaded option. The query
  receives the full list.
  - Options are capped at `MAX_DISPLAY_OPTIONS = 100`, so with more than 100 distinct values "All" silently
    filters out the rest.
  - `null` values are dropped when loading options, so "All" excludes blank documents and there is no blank
    option.
- An empty multi-select becomes `('')`, which matches nothing useful; an empty single-select becomes an empty
  string. A variable without a value defaults to its first option.
- `stats count() by $group_by` with `region` selected becomes `stats count() by region`, so the result column
  follows the selected field. There is no "None": an empty value gives invalid `by `, and "All" on a grouping
  variable gives invalid `by ('region', 'service')`.
- Saved charts bind axes by column name (`axesMapping`). When `$group_by` renames the column, `isValidMapping`
  fails and `reuseAxesMapping` keeps the surviving columns and refills the missing axis with an unused column of
  the same type. If no rule matches, the panel fails with "Cannot load saved visualization".

**Splunk** ([field searches](https://help.splunk.com/en/splunk-enterprise/search/search-manual/9.4/retrieve-events/use-fields-to-retrieve-events))

- Inputs use an "All" choice with value `*`, and `valuePrefix` / `valueSuffix` / `delimiter` to build
  `host="a" OR host="b"` (Dashboard Studio: comma delimiter, use with `IN`).
- `field=*` only matches events where the field exists, so "All" as `*` drops events without the field.
  `NOT field=*` finds them. The usual community workaround is an empty token so the filter disappears.
- Removing "All" when another value is picked, and restoring it when the selection becomes empty, needs custom
  `<change>` eval logic or JavaScript.

**Azure Data Explorer dashboards** ([parameters](https://learn.microsoft.com/en-us/azure/data-explorer/dashboard-parameters))

- "Add a Select all value": when selected, the parameter arrives as an empty array, and the documented query
  pattern is:

  ```kusto
  StormEvents
  | where State in (_state) or isempty(_state)
  ```

  This is option D, documented as the official approach.

**Azure Monitor Workbooks** ([dropdown parameters](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-dropdowns))

- Multi-select formatting via "Delimiter" and "Quote with" settings (default `'a', 'b'`).
- "All" can have a special value, e.g. `[]`, used as
  `let selection = dynamic([{Selection}]); ... | where array_length(selection) == 0 or SomeField in (selection)`.
  An empty selection is also treated as "All".

**Power BI**

- With Kusto dynamic parameters, "Select all" sends a marker (`__SelectAll__`), and the function checks
  `"__SelectAll__" in (param) or EventType in (param)`.
- Field parameters (switching the field of an axis or legend) document a limitation: "There's no way for your
  report users to select the 'none' or no fields option. Selecting no fields in the slicer or filter card is the
  same as selecting all fields." The workaround is a dummy "None" field plus visual-level filter measures
  ([field parameters](https://learn.microsoft.com/en-us/power-bi/create-reports/power-bi-field-parameters)).

**Metabase** ([optional clauses](https://www.metabase.com/docs/latest/questions/native-editor/optional-variables),
[field filters](https://www.metabase.com/docs/latest/questions/native-editor/field-filters))

- Optional clauses: `[[AND category = {{cat}}]]` is dropped when the variable has no value. The docs spend a
  section on keeping the query valid without the clause (e.g. `WHERE TRUE` before optional `AND` clauses).
- Field filters: `WHERE {{state}}`, with no column or operator. Metabase generates the whole predicate (single
  value, multiple values, ranges, dates) and compiles an empty filter to `1 = 1`
  ([metabase#20503](https://github.com/metabase/metabase/pull/20503)). Field-filter operators include
  empty/not-empty and null/not-null.

**Looker** ([templated filters](https://cloud.google.com/looker/docs/templated-filters))

- `{% condition region %} order.region {% endcondition %}` always produces a logical expression; with no value it
  becomes `1=1`. It can be combined with `NOT (...)` and other logic.
- `{% if filter._is_filtered %} ... {% else %} ... {% endif %}` checks whether a filter is set, much like
  `IS_DEFINED`.
- Liquid parameters (`{% parameter x %}`, `type: unquoted`) insert raw values such as function or table names.

**Apache Superset** ([SQL templating](https://superset.apache.org/admin-docs/configuration/sql-templating/))

- Jinja templates: `{% if filter_values('x') %} AND x IN {{ filter_values('x')|where_in }} {% endif %}`.
  Without the guard, an empty filter produces invalid `IN ()`.
- `get_filters('x')` exposes the operator (`IN` / `NOT IN`), which is how "inverse selection" (Exclude) is
  handled.

### 6.3 Takeaways for ES|QL

- **D/D+ is mainstream.** Microsoft documents it for Azure Data Explorer, Workbooks and Power BI. The main
  drawback is length, which Kibana can hide by generating the snippet when a control is created.
- **Text preprocessors are popular but fragile.** Metabase, Superset and Looker remove or generate query text;
  the tools themselves report invalid queries, and the Grafana discussion reports lost static analysis. Kibana
  analyses ES|QL heavily (Lens column mapping, autocomplete, alert inlining), so an in-language construct (E)
  is better than a text macro.
- **Predicate-generating parameters are valued.** Looker templated filters and Metabase field filters let the
  user's selection produce the whole predicate, including null and exclude. That's the idea behind option H.
- **Blanks are a common gap.** Splunk `field=*`, Grafana wildcards and OpenSearch Dashboards all drop missing
  values with "All"; only PromQL handles them natively. Treating blank as its own selectable state (D+/H) would
  go beyond most tools.
- **Breakdown "None" is unsolved almost everywhere.** Power BI documents it as a limitation, OpenSearch
  Dashboards has no way to express it, and only Grafana does it, by query rewriting for two data sources.
- **Re-binding a renamed column by type** (OpenSearch Dashboards `reuseAxesMapping`) is a cheap way to keep
  charts working when a field variable changes the result column.

### 6.4 Requirements compared across tools

Based on the documentation, community threads and code reading in 6.2. The Power BI and Superset blank/exists
cells come from general product knowledge rather than a detailed check.

| Tool / proposal | "Any" (no filter) | "Any" keeps blanks | Multi-select, any value | Blank selection | Exclude | Exists | Author-defined complex predicates | Breakdown "None" | Typed values (no text injection) | Query stays analysable |
|---|---|---|---|---|---|---|---|---|---|---|
| Kibana classic (DSL) controls | Yes | Yes | Yes (phrases filter) | Partial: Exists + Exclude only | Yes | Yes | No: fixed filters | n/a | Yes | Yes |
| Kibana ES\|QL controls today | No: forced selection | n/a | Partial: `MV_CONTAINS` is "all values"; type errors | No | No | No | Yes | No | Yes | Yes |
| Grafana variables | Partial: joined list or wildcard | Partial: PromQL `.*` only | Yes | No ([#102229](https://github.com/grafana/grafana/issues/102229)) | Partial: author writes `!~` | No | Partial: text, no branching | No | No: text substitution | Partial |
| Grafana Filter and Group by | Yes | Yes | Yes | Partial: per data source | Yes | Partial | No: injected `AND` only | Partial: Prometheus/Loki only | Yes | Yes |
| OpenSearch Dashboards (PPL) | No: list of up to 100 values | No: nulls dropped | Yes (`IN`) | No | No | No | Partial: text, no branching | No | No: text substitution | Partial |
| Splunk | Partial: `*` or empty token | Partial: `*` drops, empty token keeps | Yes | Partial: hand-written `NOT field=*` | Partial: hand-written | Partial: `field=*` | Partial: token eval logic | Partial: token tricks | No | No |
| Azure Data Explorer | Yes: empty array + `isempty` | Yes | Yes (`in`) | No | Partial: author writes it | No | Yes | No | Yes | Yes |
| Azure Workbooks | Yes: special value or empty array | Yes | Yes | No | Partial: author writes it | No | Yes | No | No: text substitution | Partial |
| Power BI | Yes | Yes | Yes | Yes: "(Blank)" item | Partial: filter pane | Partial: filter pane | Partial: DAX `ISFILTERED` | No: documented limitation | Yes | Yes |
| Metabase | Yes: optional clause / `1 = 1` | Yes | Yes (field filter) | Partial: "is empty" operator | Yes (field filter) | Yes (field filter) | Partial: optional clauses only | Partial: text clauses | Partial: field filters only | No: templated text |
| Looker | Yes: `1=1` | Yes | Yes | Yes: `NULL` / `EMPTY` expressions | Yes (`-value`) | Yes (`-NULL`) | Yes (`_is_filtered`) | Partial: Liquid parameters | Partial | No: Liquid templating |
| Superset | Yes: Jinja `{% if %}` | Partial: author writes it | Yes | Partial: author writes it | Yes (`get_filters` op) | Partial | Yes (Jinja) | Partial: Jinja | No | No: Jinja templating |
| **D.** `?x IS NULL OR MV_INTERSECTS(?x, f)` | Yes | Yes | Yes | No | Partial: separate generated query | No | Yes | No | Yes | Yes |
| **D+.** D + flag params | Yes | Yes | Yes | Yes | Yes | Yes | Yes | No | Yes | Yes |
| **H.** Filter-parameter function | Yes | Yes | Yes | Yes | Yes | Yes | Partial: falls back to D | No | Yes | Yes |
| **F2.** Optional grouping key | n/a | n/a | n/a | n/a | n/a | n/a | n/a | Yes: column disappears | Yes | Yes |
| **G.** Constant group | n/a | n/a | n/a | n/a | n/a | n/a | n/a | Partial: one group | Yes | Yes |

What stands out:

- Only Looker, and Kibana's own classic controls, come close on the filter side; D+ or H would match them while
  keeping typed parameters and an analysable query, which no templating tool does.
- Breakdown "None" is the weakest column everywhere: only Grafana (for two data sources) does it properly. F2
  would be ahead of the field.

## 7. Validation on Elasticsearch 9.5.1

Run on October 1, 2026 against a 9.5.1 cloud cluster. The scripts are in `kibana_any_tests/` (`setup.ps1`
creates the index; `t1`–`t5` run the checks).

Test index `kibana_any_test` (`host` keyword, `flag` boolean, `n` integer, `l` long, `ip` ip), with documents
for: single values `a`, `b`, `c`; a document without the fields; a document with explicit `null`s; a
multi-valued document `host: [a, b]`; and a document whose `host` is literally `"__blank__"`.

| Check | Result |
|---|---|
| `?host IS NULL OR host == ?host`, `host: null` | All 7 rows, including blanks |
| Same, `host: "a"` | Row `a` only; pushed down as a Lucene `term` query |
| Same, `host: ""` (what Kibana sends today) | No rows |
| `?host IS NULL OR MV_INTERSECTS(?host, host)`, `null` and `[]` | All 7 rows; no filter at all in the plan |
| Same, `["a"]` | `a` and `[a, b]`; filter operator (no pushdown on 9.5.1) |
| `CASE(?host IS NULL, true, ...)` form | Same results and plans as the `OR` form |
| `MV_CONTAINS(?host, host)`, `["a"]` | `a` plus both blank documents; not `[a, b]` |
| `MV_CONTAINS(null, host)` | True only for blank documents |
| `host IN (?host)`, `["a", "b"]` | No rows, no error |
| `[]` param | Treated as `null` |
| List with a `null` entry; list mixing number and string | 400 |
| Parameter used in the query but absent from the request | 400 "Unknown query parameter" |
| Structured param object (`{"values": [...], "blank": true}`) | 400: only `value`, `identifier`, `pattern` allowed |
| D+ boolean flag: Any / values / blank only / values + blank | Expected rows in every case |
| D+ sentinel `["a", "__blank__"]` | Expected rows, plus the document whose value is literally `"__blank__"` |
| Exclude `?host IS NULL OR host IS NULL OR NOT MV_INTERSECTS(?host, host)`, `["a"]` | `b`, `c`, blanks, `"__blank__"` |
| Exclude without the guard, `NOT MV_INTERSECTS(?host, host)`, `["a"]` | Same rows: `MV_INTERSECTS` is `false` for missing values, so `NOT` keeps them |
| `MV_INTERSECTS(?sel, field)` / `MV_CONTAINS(?sel, field)` / `MV_CONTAINS(field, ?sel)`, selection `[a, b]`, field `[a, c]` | `true` / `false` / `false` |
| `MV_INTERSECTS` on integer and boolean fields, matching param type | Works |
| `MV_INTERSECTS`/`MV_CONTAINS`, integer param on a `long` field | 400; works with `TO_LONG(?l)` |
| `MV_INTERSECTS`, string param on an `ip` field | 400; works with `TO_IP(?ip)` |
| Inlined text `CASE(null IS NULL, true, ...)` | Valid; all rows |
| `STATS c = COUNT(*) BY g = null` (also `= "all"`, also with another key) | One group per remaining key |
| `STATS ... BY g = CASE(?f IS NULL, null, host)`, `f: null` | One group |
| `BY ??f` with `f: null`; `BY ?f` with `{"identifier": null}` | 400 (parse error / request error) |

On a local 9.6.0-SNAPSHOT built from this workspace (`./gradlew run`), with the `any_demo` index (2,000 documents,
multi-valued `tags`, ~15–25% missing values per field; script `kibana_any_tests/demo_data.ps1`, checks in `t6`):

| Check | Result |
|---|---|
| `?tag IS NULL OR tags == ?tag`, `"prod"` | 187 documents, none multi-valued; pushed down (`term`) |
| `?tag IS NULL OR MV_INTERSECTS(?tag, tags)`, `"prod"` | 575 documents, 388 multi-valued; pushed down to Lucene |
| Same, `["prod", "beta"]` | Pushed down to Lucene |
| Same, `null` | No filter in the plan |
| `status == ?s` (`long` field), `404` | 252 documents |
| `MV_INTERSECTS(?s, status)`, `404` | 400: integer against long |
| `MV_INTERSECTS(TO_LONG(?s), status)`, `404` | 252 documents |

"(No value)" sentinel variant (checks in `t7`), filter
`?x IS NULL OR MV_INTERSECTS(?x, f) OR (f IS NULL AND MV_CONTAINS(?x, "__NULL__"))`:

| Check | Result |
|---|---|
| Values query `STATS BY os \| EVAL os = COALESCE(os, "__NULL__")` | Options `__NULL__`, `linux`, `macos`, `windows` |
| OS = `"__NULL__"` | 278 (all documents without `os`) |
| Tags = `["prod", "__NULL__"]` | 1,076 (575 + 501) |
| Tags = `["__NULL__"]` | 501 |
| Exclude `["prod", "__NULL__"]` (negated filter) | 924 (2,000 − 575 − 501) |

"(No value)" companion variant, filter
`(?x IS NULL AND NOT ?x__nulls) OR MV_INTERSECTS(?x, f) OR (?x__nulls AND f IS NULL)`. `t9` uses a small
`nulls_demo` index (boolean `flag`, long `code`, one document without either, one multi-valued). `t10` runs the
scenarios dashboard's section 5 filter (keyword `os`, integer `priority`, boolean `secure`, all three filters
combined) on `any_demo` and compares each count with a direct query:

| Check | Result |
|---|---|
| Boolean: Any / `[true]` / "(No value)" only / `[true]` + "(No value)" | All 5 / `true` and `[false, true]` / the blank one / both plus the blank one |
| Long (`TO_LONG(?x)`): Any / `[404]` / `[404]` + "(No value)" / "(No value)" only | Expected rows in each case |
| `?x__nulls` referenced but not sent | 400 "Unknown query parameter [x__nulls]" |
| Section 5 filter on `any_demo`: Any; Priority `[1, 2]`; "(No value)" only; `[4]` + "(No value)"; Secure `["true"]` + "(No value)" (`TO_BOOLEAN`); Secure `["false"]`; OS `linux` + "(No value)" with Priority `[1]` | 2,000; 822; 365; 768; 1,440; 560; 177: each equals the direct query |
| Profile, Any | Folds away: a plain `LuceneCountOperator`, no filter |
| Profile, `[1]` + "(No value)" | Pushed down entirely: `LuceneCountOperator` with the query, no filter operator |

Not verified yet:

- Lens charts (`xy` with `breakdown_by`) when the bound breakdown column is missing; data tables were checked
  (section 8.1).

## 8. Kibana demo

A working demo of D on Kibana `main` (9.6.0, commit `ec5a1110af7`) against the 9.6 snapshot above.

- **Environment:**
  - Kibana dev mode runs in a Docker container (`kibana-any-dev`, source in volume `kibana-src`), because Kibana
    no longer bootstraps natively on Windows.
  - It connects to the Windows ES through `host.docker.internal:9200`.
  - Scripts and config are in `kibana_any_tests/`.
- **Kibana patch** (working tree only, also in `C:/kibana`):
  - ES|QL controls can be cleared: the last value can be deselected, "Deselect all" works, a single-select
    toggles off, and the "Clear control" action is enabled.
  - An empty selection is sent as `null`, and the empty control shows "Any".
  - A `__NULL__` option is shown as "(No value)" (formatter in `esql_control/constants.ts`).
  - Companion param: an ES|QL control setting `include_no_value_option` (schema in `options_list_schema.ts`, kept by
    the server transform). The control prepends a marker option shown as "(No value)", keeps it out of the value,
    and publishes `meta.nulls`. `getNamedParams` (`kbn-esql-utils`), which builds params for every consumer,
    adds `?<name>__nulls` as a boolean when the query references it.
- **Query format:** all panel queries are written one command per line, with long conditions continued on indented
  lines. The control-driven part is wrapped in `// Filter start` / `// Filter end` (or `// Breakdown start` /
  `// Breakdown end` for the `CASE` grouping). ES|QL accepts `//` comments between pipes, and the Dashboards API and
  Lens keep comments and line breaks in the stored query (verified).
- **Current dashboards:** "1. ES|QL controls: Any - scenarios" (main demo), "2. ES|QL controls: Any - functions"
  (section 8.1) and "3. ES|QL controls: Any + include/exclude".
- **Removed dashboards:** "ES|QL controls: Any" and "ES|QL controls: Any + (No value)" were superseded by the
  scenarios dashboard (sections 1–2 and 4) and deleted. Their scripts (`create_dashboard.ps1`,
  `create_dashboard_null.ps1`) still recreate them. A finding from them, also covered by scenarios section 4:
  - `prod` + "(No value)" (`__NULL__` sentinel) gave 1,075 documents in the 7-day window.
  - The sentinel only works for string fields (a list param can't mix types), and collides with a real
    `"__NULL__"` value.
- **Dashboard "1. ES|QL controls: Any - scenarios"** (`create_dashboard_scenarios.ps1`): one collapsible section per
  scenario. Controls sit inside their section, and panels only use their own section's variables, so sections
  don't affect each other.
  1. **Single value (os):** "Any" via `?sv_os IS NULL OR MV_INTERSECTS(?sv_os, os)`.
  2. **Multivalue (tags):** "Any" and the "include docs without tags" flag (D+ with a flag). The flag only adds
     blanks to an actual selection; with Tags on "Any" everything is shown. "Blanks only" is section 4's
     "(No value)" option.
  3. **STATS BY:**
     - A value control holding a field name, mapped with
       `EVAL group = CASE(?bd_field == "os", os, ..., "all documents")`. Cleared, it gives a single "all documents"
       group: option G, working today with no ES change. The column name stays `group`.
     - A `??field` control next to it shows the gap: clearing it makes its panel fail with
       "Query parameter [??bd_ident] is null".
  4. **"(No value)" label:** the `__NULL__` sentinel on a single-value control (OS) and a multivalue control
     (Tags).
  5. **"(No value)" via the companion param:** OS (keyword), Priority (integer) and Secure (boolean), each a
     multi-select with `include_no_value_option`, filtered with the `?x__nulls` template (`TO_BOOLEAN(?nv_secure)`
     because controls send non-numeric values as strings). `priority` and `secure` were added to `any_demo` with
     ~18% and ~14% missing values (`demo_data_nulls.ps1`, derived from `bytes`, so earlier counts are unchanged).
     Shows what the sentinel can't: "(No value)" on numeric and boolean fields, e.g. Secure `true` + "(No value)".
  - The Dashboards API accepts `esql_control` panels inside sections (verified), not only as pinned controls.
- **Dashboard "3. ES|QL controls: Any + include/exclude"** (`create_dashboard_exclude.ps1`): include/exclude is
  not part of the issue, but classic controls have an Exclude toggle, so it lives in its own dashboard. The other
  dashboards always include.
  - OS, Region and Tags each offer "Any" and "(No value)", plus their own mode control (include / exclude), like
    the per-control Exclude toggle of classic controls.
  - Each filter keeps its size with a boolean comparison instead of repeating the match:

    ```esql
    | WHERE ?x IS NULL
         OR (COALESCE(?x_mode, "include") == "include") == (MV_INTERSECTS(?x, f) OR (f IS NULL AND MV_CONTAINS(?x, "__NULL__")))
    ```

    The match is never `null` when `?x` is set, so include keeps matching documents and exclude keeps the rest,
    including documents without the field (like DSL `must_not`). A cleared mode control acts as include.
  - Verified (`t8`): OS include/exclude `linux` gives 560 / 1,440; exclude "(No value)" gives 1,722; Tags exclude
    `[prod, (No value)]` gives 924; excluding `linux` while including `prod` combines correctly (427).

### 8.1 Prototype of the syntactic sugar (ES change, working tree only)

The sugar from "Templates and syntactic sugar per case" (section 2) is prototyped in this workspace, with no tests or
docs: just enough to run a dashboard. Each function is an `OnlySurrogateExpression` (like `CLAMP`): the logical
optimizer replaces it with the expanded template before anything else sees it, so there is no evaluator,
serialization or transport version.

- **`IN_SELECTION(field, ?sel [, {options}])`** (`scalar/conditional/InSelection.java`): expands to
  `?sel IS NULL OR MV_INTERSECTS(cast(?sel), field)`, with the cast to the field type added automatically. Options:
  - `nulls` (companion): expands to `(?sel IS NULL AND NOT n) OR ... OR (n AND field IS NULL)`.
  - `include_nulls` (separate flag control): adds `OR (flag AND field IS NULL)`.
  - `null_value` (sentinel): adds `OR (field IS NULL AND MV_CONTAINS(?sel, sentinel))`.

  Boolean options accept `"true"`/`"false"` strings, and `null` counts as `false`. Map values can be parameters
  today (`constant` includes `parameter` in the grammar), so `{"nulls": ?x__nulls}` needed no parser change.
- **`IN_RANGE_SELECTION(field, ?lo, ?hi)`** (`InRangeSelection.java`): a `null` bound is unbounded. It becomes
  `true`, `MV_GREATER`/`MV_LESS` with `include_bound`, or `MV_IN_RANGE`.
- **`FIELD_OR(??f, fallback)`** (`FieldOr.java`): becomes the field, or the fallback when `??f` is `null`.
- **`BY OPTIONAL(??f)`**: parser only (`ExpressionBuilder.visitGrouping`). The key is dropped when `??f` is
  `null`, and `STATS` becomes a global aggregation if it was the only key.
- **Parser:** a `null` `??x` is accepted only as the first argument of `FIELD_OR`/`OPTIONAL`, where it becomes a
  `null` literal. Everywhere else it's still "Query parameter [??x] is null" (verified).

Verified on the 9.6 snapshot (`t11_functions.ps1`):

- 17 filter cases each return the same count as the hand-written template: single value, multivalue, integer
  param on a `long` field (no cast needed), the flag, the sentinel, the companion param on `boolean`/`integer`,
  and the range in all four forms.
- Profiles show the same plans as the templates: "Any" folds away, and values (plus "(No value)") push down to
  Lucene entirely.

**Dashboard "2. ES|QL controls: Any - functions"** (`create_dashboard_functions.ps1`): the scenarios dashboard with
every control-driven part replaced by a function. Section 3 has a single `??fn_bd` control:

| Section | Query part |
|---|---|
| 1 | `WHERE IN_SELECTION(os, ?sv_os)` |
| 2 | `WHERE IN_SELECTION(tags, ?mv_tags, {"include_nulls": ?mv_blank})` |
| 3 | `BY ..., group = FIELD_OR(??fn_bd, "all documents")` and `BY OPTIONAL(??fn_bd)` |
| 4 | `WHERE IN_SELECTION(os, ?nl_os, {"null_value": "__NULL__"})` |
| 5 | `WHERE IN_SELECTION(secure, ?nv_secure, {"nulls": ?nv_secure__nulls})` (no `TO_BOOLEAN` needed) |

Results in the browser match the scenarios dashboard (e.g. Secure `true` + "(No value)": 1,413 = 1,147 + 266).
Two side findings:

- Kibana found `?x__nulls` inside the map literal and sent it.
- A Lens data table bound to `??fn_bd`, with the column dropped by `OPTIONAL`, renders just `docs` (one row), with
  no error. With `os` selected, it shows the `os` column again.

## 9. Coverage of the issue conversation and related discussions

Checked on October 2, 2026: every comment on [#136735](https://github.com/elastic/elasticsearch/issues/136735)
and [#137554](https://github.com/elastic/elasticsearch/issues/137554), the linked Kibana issues, and Slack threads
mentioning the issue or the problem. "Covered" means covered by D/D+ (validated) plus the Kibana demo patch.

### 9.1 Issue and linked items

| Source | Ask | Covered? | How / gap |
|---|---|---|---|
| Issue body (Stratoula) | "Any" for `WHERE host == ?host` | Yes | `?host IS NULL OR MV_INTERSECTS(?host, host)`; Kibana sends `null` |
| Alex (issue) | What does "Any" mean for `host != ?host`? | Yes | The author writes the "Any" branch, so semantics are explicit |
| Alex (issue) | `STATS BY`: can Kibana remove the `BY`? | Partly | Today: value control + `CASE` gives one group (option G, demo section 3). Real "no breakdown" needs F2 (or Kibana rewriting) |
| Stratoula (issue) | `LIKE` doesn't take params | Partly | `LIKE ?t` works on 9.6, but a `null` pattern param is a parse error, even inside `CASE`. Workaround verified: `?t IS NULL OR f LIKE COALESCE(?t, "*")`. Small ES ask: accept `null` pattern params |
| Teresa (issue) | "Any" with multi-select (`MV_CONTAINS`) | Yes | `MV_INTERSECTS` (any-value, like DSL); `[]` is already `null` ([#152098](https://github.com/elastic/elasticsearch/pull/152098)) |
| Teresa (issue) | "Any" includes blank and existing values | Yes | `?x IS NULL OR ...` keeps documents without the field (verified) |
| quackaplop (issue) | Short term `CASE`, long term `IS_DEFINED`; `STATS` open | Yes for filters | D is the short-term path, validated; `IS_DEFINED` optional sugar; `STATS` via G today, F2 later |
| Hawk (issue) | Magic `ANY` rejected; macro ~8 weeks | Consistent | No magic value; D needs no ES change for filters |
| Miguel (issue) | Unselect all; default to "Any" | Yes (demo patch) | Kibana patch allows deselecting, "Deselect all", empty default shown as "Any" |
| Alex (#137554) | `IS_DEFINED` as `CASE` sugar; `STATS BY` a constant | Yes | Grouping by a constant verified (option G) |
| [kibana#241603](https://github.com/elastic/kibana/issues/241603) | Enforce one value until "Any" exists | Yes | The patch removes that enforcement |
| [kibana#243618](https://github.com/elastic/kibana/issues/243618) | Save a control whose values query returns nothing | No | Control-editor validation, not part of the demo; Kibana work item |
| [kibana#265744](https://github.com/elastic/kibana/issues/265744) | Default to "all" | Yes | Default is "Any" (empty selection), which also covers new or unlisted values |
| [Vanguard](https://github.com/elastic/enhancements/issues/26524) | Blank control = all results | Yes | Same as above |
| Vanguard | `LIKE` with a control token | Partly | See the `LIKE` row |
| Vanguard | Type a custom value | No | Not related to "Any"; [kibana#181696](https://github.com/elastic/kibana/issues/181696) |
| [integrations#19758](https://github.com/elastic/integrations/pull/19758) | Integration dashboards with no known default | Yes | Ship controls with an empty selection; queries use `?x IS NULL OR ...` |
| [#144289](https://github.com/elastic/elasticsearch/issues/144289) | `IN (?list)` | Not needed | `MV_INTERSECTS` instead; `IN (?list)` silently returning nothing is still a bug to fix or reject |
| sdh-kibana#5889 | (Customer SDH) | Unknown | Not accessible |

### 9.2 Slack

- **#kibana, Oct 2025, where the issue was created** (Jo Ann De Leon, Stratoula): a customer migrating from Splunk
  wanted a default of "show me all/any" instead of the first value. Covered. The same thread asked for **label /
  value mapping** on control options (show "SQL Server", send `mssql123`): not part of this issue, though the
  "(No value)" formatter is a small instance of it.
- **#kibana, June 2025** (Gil Raphaelli): worked around it with a second toggle control,
  `| WHERE NOT should_filter1 OR filter1` (our D+ flag), and Bill Easton suggested a sentinel value (our
  "(No value)" demo). Gil also asked for custom values. This confirms D+ and the sentinel are what users already
  reach for.
- **#esql, June 2026** (Ty Bekiares, Stratoula, Teresa, Alex, Oleg, David Luna), about the OTel RUM integration
  dashboard:
  - Integration dashboards can't know values at install time, so first load must show data.
  - Ty: "ANY" as "select all" misses new values. Covered: `null` means "no filter", not "all listed values".
  - Kibana deliberately blocks empty values "waiting for the ANY" (Stratoula). The patch removes that block.
  - Alex: `null` is a valid named-param value and will stay accepted. `[]` became `null` (#152098) after this
    thread.
  - Oleg: he doesn't believe "anything that looks like an array should automatically have MV semantics… even less
    parameters". D uses explicit `MV_INTERSECTS`, so it doesn't rely on implicit list semantics; this argues
    against implicit `IN (?list)` expansion and should be kept in mind for H's structured params.
- **#esql, July 2026** (Camille, Miguel, SLB): after "Select all" there's no way back. Covered by the patch.
- **#esql, Jan 2026** (David Erickson, Pierre Gayvallet, Tyler): **Agent Builder** ES|QL tools need optional
  filters (10 optional filters means a combinatorial explosion of tools). D covers optional filters if the tool
  sends `null` for an omitted param (Agent Builder already has default values for optional params,
  [kibana#238472](https://github.com/elastic/kibana/pull/238472)). Pierre also asked for command-level
  conditionals ("if condition then [list of commands]"), which D does not cover (F-like, out of scope). Tyler
  noted the main open question was syntax.
- **#esql-ergonomics, July–Sept 2026** (Oleg, William):
  - Oleg framed the related work as filling out the `MV_` set with DSL-like semantics plus Lucene pushdowns
    ([esql-planning#1655–1657](https://github.com/elastic/esql-planning/issues/1655): `MV_GREATER`/`MV_LESS`,
    `MV_IN_RANGE`, any-value `CIDR_MATCH`). These functions return `false` (never `null`) for missing values,
    like `MV_INTERSECTS`, so they combine with the same "Any" pattern. Verified on the 9.6 snapshot:
    `?lo IS NULL OR MV_IN_RANGE(status, TO_LONG(?lo), TO_LONG(?hi))` gives 743 for 400–599 and 2,000 for "Any"
    (same strict typing: casts needed).
  - William's plan: one-day investigation, then a session with Stratoula and Teresa, then implementation. This
    document is that investigation.

### 9.3 Remaining gaps

1. **Breakdown "None"**: works today as a single group (G); real "no breakdown" needs F2. A plain `BY ??x` with
   the control cleared fails with "Query parameter [??x] is null" (demo section 3). A `null` identifier param is a
   parse error, and Kibana can't send anything that means "no field". The options:
   - **Today, no ES change (G):** a value control holding the field name, plus
     `EVAL group = CASE(?bd == "os", os, ..., "all documents")`. Cleared, it gives one "all documents" group. The
     field list is repeated in the query, and the column is always named `group`.
   - **ES prototype (section 8.1):** `BY OPTIONAL(??x)` drops the key ("no breakdown"; a Lens data table then shows
     only the metric, with no error), and `BY group = FIELD_OR(??x, "all documents")` gives one group. Both are
     opt-in per query, so a plain `BY ??x` keeps failing loudly.
   - **Kibana only:** don't let field controls be cleared (today's behaviour of always requiring a value). It
     avoids the error, but gives no "None".
   - **Rejected:** making a `null` `??x` in `BY` drop the key implicitly, with no `OPTIONAL`. It's easy to
     implement, but it's implicit, it silently changes the output columns of existing queries, and a `null` `??x`
     anywhere else would still have to be an error.
2. **`LIKE`/`RLIKE` with a `null` pattern param**: parse error; workaround with `COALESCE(?t, "*")`. Small ES fix.
3. **Strict typing** in `MV_INTERSECTS`, `MV_CONTAINS`, `MV_IN_RANGE`: integer params against `long` fields and
   string params against `ip` fields fail. Kibana must cast from the field type, or ES widens types.
4. **Kibana work not in the demo**: saving a control whose values query returns nothing (kibana#243618),
   generating the filter snippet when creating a control, and allowing `null` when inlining for alert rules.
5. **Out of scope but raised alongside**: custom values (kibana#181696), label/value mapping for options, and
   command-level conditionals for Agent Builder.
