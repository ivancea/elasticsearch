# ES|QL controls: four cases

Kibana sends `null` for an empty selection ("Any"). `[]` is already `null`.

Two proposals, for each case below:

1. **Helper functions.** The "Any" branch is inside the function. A `null` argument folds to `true` (or, for `BY`, to the fallback / no key).
2. **Auto-removal.** A `null` parameter makes that predicate `true`, only inside `MV_INTERSECTS`, `MV_CONTAINS`, or a comparison (`==`, `>`, …). In `BY`, a `null` `??group` drops that grouping key, or keeps the key with a `null` value (one group). A `null` parameter anywhere else is still an error.

   ```esql
   WHERE MV_INTERSECTS(?os, os)
   WHERE MV_CONTAINS(?tags, tags)
   WHERE os == ?os
   WHERE bytes > ?min
   BY ??group
   ```

   `?os = null` (and the same for the other `WHERE` parameters) makes that line `WHERE true`. A `null` `??group` removes the key, or leaves `BY group = null`.

Names (`IN_SELECTION`, `FIELD_OR`, `OPTIONAL`) are placeholders.

## 1. Single- or multi-value selector

One value or a list. Same filter. `MV_INTERSECTS` matches any shared value, including on a multi-valued field.

Today:

```esql
WHERE ?os IS NULL OR MV_INTERSECTS(?os, os)
```

Proposals:

1. Helper function

   ```esql
   WHERE IN_SELECTION(os, ?os)
   ```

2. Auto-removal

   ```esql
   WHERE MV_INTERSECTS(?os, os)
   ```

   `?os = null` makes this `true`. `?os = "linux"` or `?os = ["linux", "windows"]` is unchanged.

## 2. Selector with "(No value)"

"(No value)" means documents where the field is missing, alone or together with real values. Kibana adds that option on top of the dropdown values and shows it as "(No value)". The query still receives `?os = "__NULL__"`. Kibana does not do this today: a dropdown is either a fixed list or a query, and a query drops missing values, so the only workaround is to return the string `"__NULL__"`, which is what the user would read. String fields only, and a real value equal to `"__NULL__"` collides.

Today:

```esql
WHERE ?os IS NULL
   OR MV_INTERSECTS(?os, os)
   OR (os IS NULL AND MV_CONTAINS(?os, "__NULL__"))
```

Can be simplified with `COALESCE`, but it can't be pushed down to Lucene right now:

```esql
WHERE ?os IS NULL OR MV_INTERSECTS(?os, COALESCE(os, "__NULL__"))
```

Proposals:

1. Helper function

   ```esql
   WHERE IN_SELECTION(os, ?os, {"null_value": "__NULL__"})
   ```

2. Auto-removal

   ```esql
   WHERE MV_INTERSECTS(?os, os) OR (os IS NULL AND MV_CONTAINS(?os, "__NULL__"))
   ```

   `?os = null` makes `MV_INTERSECTS` `true`, so the filter matches every document. `?os = "__NULL__"` is a normal value: `MV_INTERSECTS` misses, and the second clause keeps documents where `os` is missing.

## 3. STATS BY group

`??group` is the field control. Clearing it fails: "Query parameter [??group] is null".

```esql
BY ??group
```

Today, one group when cleared:

```esql
BY group = CASE(?group == "os", os, ?group == "region", region, "all documents")
```

Proposals:

1. Helper functions. A `null` `??group` is accepted here.

   One group, column kept:

   ```esql
   BY group = FIELD_OR(??group, "all documents")
   ```

   Key dropped (global aggregation when it was the only key):

   ```esql
   BY OPTIONAL(??group)
   ```

2. Auto-removal. The query stays `BY ??group`. A `null` `??group` drops that key (and drops `BY` if it was the only one), or keeps the key with a `null` value, so every document falls in one group.

   ```esql
   BY ??group
   ```

## 4. Include / exclude

Classic (DSL) controls have an Include / Exclude toggle. Exclude keeps every document without a selected value, including documents where the field is missing (DSL `must_not`). ES|QL controls hide the toggle today. Kibana would show it and send the mode as a second parameter, here `?os_exclude` (boolean).

Today (`MV_INTERSECTS` is `false` for a missing field, so exclude keeps those documents):

```esql
WHERE ?os IS NULL OR MV_INTERSECTS(?os, os) != ?os_exclude
```

Proposals:

1. Helper function

   ```esql
   WHERE IN_SELECTION(os, ?os, {"exclude": ?os_exclude})
   ```

   `?os = null` is `true` in both modes. Combines with "(No value)": `{"null_value": "__NULL__", "exclude": ?os_exclude}`.

2. Auto-removal. Does not work as defined above, because the `MV_INTERSECTS` call becomes `true` and the negation flips it:

   ```esql
   WHERE NOT MV_INTERSECTS(?os, os)
   WHERE MV_INTERSECTS(?os, os) != ?os_exclude
   ```

   With `?os = null`, both become `false` in exclude mode (no rows). It would only work if the whole `WHERE` condition became `true`, not just the call. That is a broader rule, and it removes more than the author may expect.
