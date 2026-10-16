A one-element list should behave like its single value (as fixed for `CASE` in #157956). `CIDR_MATCH` and `STARTS_WITH` don't, and silently return no rows.

Kibana ES|QL multi-select controls hit this: they send an array param even when one option is selected.

### Reproducer

Verified on 9.5.1 and on a recent `main` snapshot.

```
PUT test
{"mappings": {"properties": {"ip": {"type": "ip"}, "host": {"type": "keyword"}}}}

POST test/_doc?refresh
{"ip": "192.168.1.1", "host": "web-01"}
```

```esql
FROM test | WHERE CIDR_MATCH(ip, ["192.168.0.0/16"])  // 0 rows, is_partial: true. Expected 1
FROM test | WHERE STARTS_WITH(host, ["web"])           // 0 rows. Expected 1
```

- `CIDR_MATCH`: the shard fails with `'[[31 39 32 ...]]' is not an IP string literal`. Only the pushdown fails: `EVAL m = CIDR_MATCH(ip, ["192.168.0.0/16"])` is `true`.
- `STARTS_WITH`: also wrong when evaluated (`false`).
- Same with a param: `"params": [{"p": ["web"]}]`.
- The scalar forms work, and so does `host == ["web-01"]`.

### Cause

`CIDRMatch.asQuery` and `StartsWith` use the folded value as a scalar, so the one-element `List` becomes the text `"[...]"`.
