# Probes "__ANY__" auto-removal on the local ES (branch investigations/kibana-any).
$es = 'http://localhost:9200'
function q([string]$label, [string]$query, [string]$params) {
  $b = '{"query":' + ($query | ConvertTo-Json -Compress) + ',"params":' + $params + '}'
  try {
    $r = Invoke-WebRequest -Method POST -Uri "$es/_query?format=txt" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -UseBasicParsing
    $out = ($r.Content.Trim() -split "`n" | Select-Object -Skip 2) -join ' | '
  } catch {
    $msg = if ($_.ErrorDetails) { ($_.ErrorDetails.Message | ConvertFrom-Json).error.reason } else { $_.Exception.Message }
    $out = "ERROR: $msg"
  }
  "{0,-58} {1}" -f $label, $out
}
$c = '| STATS docs = COUNT(*)'
$any = '"__ANY__"'
q 'baseline all docs' "FROM any_demo $c" '[]'
q 'MV_INTERSECTS(?os, os) any' "FROM any_demo | WHERE MV_INTERSECTS(?os, os) $c" "[{`"os`": $any}]"
q 'MV_INTERSECTS(?os, os) linux' "FROM any_demo | WHERE MV_INTERSECTS(?os, os) $c" '[{"os": "linux"}]'
q 'MV_INTERSECTS(?tags, tags) [any]' "FROM any_demo | WHERE MV_INTERSECTS(?tags, tags) $c" "[{`"tags`": [$any]}]"
q 'MV_INTERSECTS(?tags, tags) [prod, beta]' "FROM any_demo | WHERE MV_INTERSECTS(?tags, tags) $c" '[{"tags": ["prod", "beta"]}]'
q 'os == ?os any' "FROM any_demo | WHERE os == ?os $c" "[{`"os`": $any}]"
q 'bytes > ?min any (no cast)' "FROM any_demo | WHERE bytes > ?min $c" "[{`"min`": $any}]"
q 'MV_GREATER(bytes, TO_LONG(?min)) any' "FROM any_demo | WHERE MV_GREATER(bytes, TO_LONG(?min)) $c" "[{`"min`": $any}]"
q 'CIDR_MATCH(client_ip, ?c) any' "FROM any_demo | WHERE CIDR_MATCH(client_ip, ?c) $c" "[{`"c`": $any}]"
q '??f == ?v both set' "FROM any_demo | WHERE ??f == ?v $c" '[{"f": "os"}, {"v": "linux"}]'
q '??f == ?v field any' "FROM any_demo | WHERE ??f == ?v $c" "[{`"f`": $any}, {`"v`": `"linux`"}]"
q '??f == ?v value any' "FROM any_demo | WHERE ??f == ?v $c" "[{`"f`": `"os`"}, {`"v`": $any}]"
q 'AND: os any, region eu-west' "FROM any_demo | WHERE MV_INTERSECTS(?os, os) AND region == ?r $c" "[{`"os`": $any}, {`"r`": `"eu-west`"}]"
q 'NOT MV_INTERSECTS any (NOT true)' "FROM any_demo | WHERE NOT MV_INTERSECTS(?os, os) $c" "[{`"os`": $any}]"
q 'old guard ?os IS NULL OR ... any' "FROM any_demo | WHERE ?os IS NULL OR MV_INTERSECTS(?os, os) $c" "[{`"os`": $any}]"
q 'old guard with null (unchanged)' "FROM any_demo | WHERE ?os IS NULL OR MV_INTERSECTS(?os, os) $c" '[{"os": null}]'
q 'STATS BY ??g any (global)' 'FROM any_demo | STATS docs = COUNT(*) BY ??g' "[{`"g`": $any}]"
q 'STATS BY bucket, ??g any' 'FROM any_demo | STATS docs = COUNT(*) BY b = BUCKET(bytes, 5000), ??g | SORT b' "[{`"g`": $any}]"
q 'STATS BY ??g os' 'FROM any_demo | STATS docs = COUNT(*) BY ??g | SORT docs DESC' '[{"g": "os"}]'
q 'agg filter COUNT(*) WHERE MV_INTERSECTS any' 'FROM any_demo | STATS c = COUNT(*) WHERE MV_INTERSECTS(?os, os)' "[{`"os`": $any}]"
q 'EVAL x = ?v any (error)' "FROM any_demo | EVAL x = ?v $c" "[{`"v`": $any}]"
q 'KEEP ??f any (error)' 'FROM any_demo | KEEP ??f | LIMIT 1' "[{`"f`": $any}]"
q 'literal "__ANY__" (no removal)' "FROM any_demo | WHERE os == `"__ANY__`" $c" '[]'
q 'FIELD_OR null still works' 'FROM any_demo | STATS docs = COUNT(*) BY g = FIELD_OR(??g, "all")' '[{"g": null}]'
q 'IN_SELECTION any' "FROM any_demo | WHERE IN_SELECTION(os, ?os) $c" "[{`"os`": $any}]"
