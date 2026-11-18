# Edge cases of "__ANY__" auto-removal on the local ES (branch investigations/kibana-any, merged with main).
# Each line: label, expected (what a user would want), actual result.
$es = 'http://localhost:9200'
function call([string]$method, [string]$path, [string]$body, [string]$ct = 'application/json') {
  try {
    [byte[]]$bytes = $null
    if ($body) { $bytes = [Text.Encoding]::UTF8.GetBytes($body) }
    return (Invoke-WebRequest -Method $method -Uri "$es$path" -ContentType $ct -Body $bytes -UseBasicParsing).Content
  } catch {
    $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    return "HTTP ${code}: $($_.ErrorDetails.Message)"
  }
}
function q([string]$label, [string]$query, [string]$params, [string]$expect) {
  $b = '{"query":' + ($query | ConvertTo-Json -Compress) + ',"params":' + $params + '}'
  try {
    $r = Invoke-WebRequest -Method POST -Uri "$es/_query?format=txt" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -UseBasicParsing
    $out = ($r.Content.Trim() -split "`n" | Select-Object -Skip 2 | ForEach-Object { ($_ -replace '\s+', ' ').Trim() }) -join ' | '
  } catch {
    $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    $err = try { ($_.ErrorDetails.Message | ConvertFrom-Json).error } catch { $null }
    $reason = if ($err) { "$($err.type): $($err.reason)" } else { $_.Exception.Message }
    $out = "ERROR $code $($reason -replace '\s+', ' ')"
  }
  "{0,-52} want: {1,-22} got: {2}" -f $label, $expect, $out
}

if ($args -contains 'setup') {
  call DELETE '/any_edge' | Out-Null
  call DELETE '/any_lookup' | Out-Null
  call PUT '/any_edge' '{"mappings":{"properties":{"id":{"type":"integer"},"os":{"type":"keyword"},"region":{"type":"keyword"},"bytes":{"type":"long"},"flag":{"type":"boolean"},"msg":{"type":"text"},"@timestamp":{"type":"date"}}}}' | Out-Null
  call PUT '/any_lookup' '{"settings":{"index.mode":"lookup"},"mappings":{"properties":{"os":{"type":"keyword"},"family":{"type":"keyword"}}}}' | Out-Null
  $bulk = @'
{"index":{"_index":"any_edge","_id":"1"}}
{"id":1,"os":"linux","region":"eu","bytes":100,"flag":true,"msg":"disk full","@timestamp":"2026-11-01T00:00:00Z"}
{"index":{"_index":"any_edge","_id":"2"}}
{"id":2,"os":"mac","region":"us","bytes":2000,"flag":false,"msg":"login ok","@timestamp":"2026-11-02T00:00:00Z"}
{"index":{"_index":"any_edge","_id":"3"}}
{"id":3,"os":"windows","region":"eu","bytes":50000,"flag":true,"msg":"disk slow","@timestamp":"2026-11-03T00:00:00Z"}
{"index":{"_index":"any_edge","_id":"4"}}
{"id":4,"region":"us","bytes":10,"msg":"no os","@timestamp":"2026-11-04T00:00:00Z"}
{"index":{"_index":"any_edge","_id":"5"}}
{"id":5,"os":["linux","mac"],"region":"eu","bytes":700,"flag":false,"msg":"multi os","@timestamp":"2026-11-05T00:00:00Z"}
{"index":{"_index":"any_edge","_id":"6"}}
{"id":6,"os":"__ANY__","region":"us","bytes":5,"flag":true,"msg":"literal reserved value","@timestamp":"2026-11-06T00:00:00Z"}
{"index":{"_index":"any_lookup","_id":"1"}}
{"os":"linux","family":"unix"}
{"index":{"_index":"any_lookup","_id":"2"}}
{"os":"mac","family":"unix"}
{"index":{"_index":"any_lookup","_id":"3"}}
{"os":"windows","family":"nt"}
'@
  $r = call POST '/_bulk?refresh=true' (($bulk -replace "`r`n", "`n") + "`n") 'application/x-ndjson'
  if ($r -like 'HTTP*') { $r } else { "bulk errors: " + ($r | ConvertFrom-Json).errors }
}

$F = 'FROM any_edge'
$c = '| STATS docs = COUNT(*)'
$A = '"__ANY__"'
$os = "[{`"os`": $A}]"

'== Baseline (6 docs; 3 in eu; linux matches ids 1 and 5)'
q 'all docs' "$F $c" '[]' '6'
q 'region == "eu"' "$F | WHERE region == `"eu`" $c" '[]' '3'
q 'os == ?os any' "$F | WHERE os == ?os $c" $os '6'

'== Inverted boolean contexts: "Any" becomes "match nothing"'
q 'NOT (os == ?os)' "$F | WHERE NOT (os == ?os) $c" $os '6 (or error)'
q 'os NOT IN (?os)' "$F | WHERE os NOT IN (?os) $c" $os '6 (or error)'
q 'os != ?os' "$F | WHERE os != ?os $c" $os '6 (or error)'
q '(os == ?os) == false' "$F | WHERE (os == ?os) == false $c" $os '6 (or error)'
q 'MV_CONTAINS(?os, os) == false' "$F | WHERE MV_CONTAINS(?os, os) == false $c" $os '6 (or error)'
q 'CASE(os == ?os, false, true)' "$F | WHERE CASE(os == ?os, false, true) $c" $os '6 (or error)'
q 'NOT (os == ?os OR region == "us")' "$F | WHERE NOT (os == ?os OR region == `"us`") $c" $os '3 (eu) or error'
q 'EVAL m = os == ?os | WHERE NOT m' "$F | EVAL m = os == ?os | WHERE NOT m $c" $os '6 (or error)'
q 'EVAL m = os == ?os | WHERE m == false' "$F | EVAL m = os == ?os | WHERE m == false $c" $os '6 (or error)'
q 'COALESCE(os == ?os, false) == false' "$F | WHERE COALESCE(os == ?os, false) == false $c" $os '6 (or error)'

'== Bare boolean parameter: the whole AND/OR is replaced'
$fl = "[{`"f`": $A}]"
q '?f alone' "$F | WHERE ?f $c" $fl '6 (or error)'
q '?f AND region == "eu"' "$F | WHERE ?f AND region == `"eu`" $c" $fl '3'
q 'region == "eu" AND ?f' "$F | WHERE region == `"eu`" AND ?f $c" $fl '3'
q '?f OR region == "eu"' "$F | WHERE ?f OR region == `"eu`" $c" $fl '6'
q 'NOT ?f AND region == "eu"' "$F | WHERE NOT ?f AND region == `"eu`" $c" $fl '3 (or error)'
q '?f::boolean AND region == "eu"' "$F | WHERE ?f::boolean AND region == `"eu`" $c" $fl '3'
q 'flag == ?f AND region == "eu"' "$F | WHERE flag == ?f AND region == `"eu`" $c" $fl '3'
q 'COALESCE(?f, false) AND region == "eu"' "$F | WHERE COALESCE(?f, false) AND region == `"eu`" $c" $fl '3'
q 'CASE(region == "eu", ?f, false)' "$F | WHERE CASE(region == `"eu`", ?f, false) $c" $fl '3'
q 'STATS c = COUNT(*) WHERE ?f AND region=="eu"' "$F | STATS c = COUNT(*) WHERE ?f AND region == `"eu`"" $fl '3'

'== Boolean results used as values'
q 'EVAL m = os == ?os | STATS BY m' "$F | EVAL m = os == ?os | STATS c = COUNT(*) BY m" $os 'm=true 6'
q 'SUM(CASE(os == ?os, 1, 0))' "$F | STATS matching = SUM(CASE(os == ?os, 1, 0))" $os '6'
q 'COUNT(*) WHERE os == ?os (agg filter)' "$F | STATS c = COUNT(*) WHERE os == ?os" $os '6'
q 'EVAL label = CASE(os == ?os, "sel", "other")' "$F | EVAL l = CASE(os == ?os, `"sel`", `"other`") | STATS c = COUNT(*) BY l" $os 'sel 6'
q 'SORT os == ?os' "$F | SORT os == ?os DESC, id | KEEP id | LIMIT 2" $os '1 | 2'

'== BY keys'
$g = "[{`"g`": {`"identifier`": $A}}]"
q 'STATS c BY ??g' "$F | STATS c = COUNT(*) BY ??g" $g '6'
q 'STATS BY ??g (no aggs)' "$F | STATS BY ??g" $g 'error'
q 'STATS c BY name = ??g' "$F | STATS c = COUNT(*) BY name = ??g" $g 'error (step 1)'
q 'STATS c BY ??g | SORT ??g' "$F | STATS c = COUNT(*) BY ??g | SORT ??g" $g '6 (or clear error)'
q 'STATS c BY ??g | KEEP c, ??g' "$F | STATS c = COUNT(*) BY ??g | KEEP c, ??g" $g '6 (or clear error)'
q 'STATS c BY ??g, ??h (both any)' "$F | STATS c = COUNT(*) BY ??g, ??h" "[{`"g`": {`"identifier`": $A}}, {`"h`": {`"identifier`": $A}}]" '6'
q 'STATS c BY ??g, region' "$F | STATS c = COUNT(*) BY ??g, region | SORT region" $g 'eu 3 | us 3'
q 'STATS c BY TO_UPPER(??g)' "$F | STATS c = COUNT(*) BY TO_UPPER(??g)" $g 'error'
q 'STATS c BY ??g == "x"' "$F | STATS c = COUNT(*) BY ??g == `"x`"" $g 'error?'
q 'INLINE STATS c BY ??g' "$F | INLINE STATS c = COUNT(*) BY ??g | KEEP id, c | SORT id | LIMIT 2" $g 'c=6 per row'
q 'STATS c BY ??g, value form (no identifier)' "$F | STATS c = COUNT(*) BY ??g" "[{`"g`": $A}]" '6'
q 'STATS c BY ?g (single ?)' "$F | STATS c = COUNT(*) BY ?g" "[{`"g`": $A}]" '6 or error'

'== Parameter shapes'
q '[__ANY__] list' "$F | WHERE os == ?os $c" "[{`"os`": [$A]}]" '6'
q '[__ANY__, linux] list' "$F | WHERE MV_INTERSECTS(?os, os) $c" "[{`"os`": [$A, `"linux`"]}]" '2 + lit doc? (no Any)'
q '[__ANY__, __ANY__] list' "$F | WHERE MV_INTERSECTS(?os, os) $c" "[{`"os`": [$A, $A]}]" '6?'
q 'lowercase __any__' "$F | WHERE os == ?os $c" '[{"os": "__any__"}]' '0 (normal string)'
q 'positional ?' "$F | WHERE os == ? $c" "[$A]" '6'
q 'positional ?1' "$F | WHERE os == ?1 $c" "[$A]" '6'
q 'literal "__ANY__" in query' "$F | WHERE os == `"__ANY__`" $c" '[]' '1 (doc 6)'
q 'select real value "__ANY__" (doc 6)' "$F | WHERE os == ?os $c" $os '1? impossible'
q 'numeric field, any' "$F | WHERE bytes == ?b $c" "[{`"b`": $A}]" '6'
q 'date field, any' "$F | WHERE @timestamp >= ?t $c" "[{`"t`": $A}]" '6'

'== Same parameter used outside a condition'
q 'WHERE os == ?os | EVAL sel = ?os' "$F | WHERE os == ?os | EVAL sel = ?os $c" $os '6 (or clear error)'
q 'EVAL sel = COALESCE(?os, "all")' "$F | EVAL sel = COALESCE(?os, `"all`") | KEEP sel | LIMIT 1" $os 'clear error'
q 'EVAL key = ?os | WHERE os == key' "$F | EVAL key = ?os | WHERE os == key $c" $os 'clear error'

'== Commands and options'
q 'LIMIT ?n' "$F | LIMIT ?n $c" "[{`"n`": $A}]" 'clear 400 error'
q 'SAMPLE ?p' "$F | SAMPLE ?p $c" "[{`"p`": $A}]" 'clear 400 error'
q 'ROW x = ?v' 'ROW x = ?v' "[{`"v`": $A}]" 'clear 400 error'
q 'MV_EXPAND ??f' "$F | MV_EXPAND ??f $c" "[{`"f`": {`"identifier`": $A}}]" 'clear 400 error'
q 'RENAME ??f AS x' "$F | RENAME ??f AS x $c" "[{`"f`": {`"identifier`": $A}}]" 'clear 400 error'
q 'DROP ??f' "$F | DROP ??f $c" "[{`"f`": {`"identifier`": $A}}]" 'clear 400 error'
q 'DISSECT ??f' "$F | DISSECT ??f `"%{a} %{b}`" $c" "[{`"f`": {`"identifier`": $A}}]" 'clear 400 error'
q 'MATCH options {"operator": ?op}' "$F | WHERE MATCH(msg, `"disk full`", {`"operator`": ?op}) $c" "[{`"op`": $A}]" 'clear error'
q 'MATCH(msg, ?q)' "$F | WHERE MATCH(msg, ?q) $c" "[{`"q`": $A}]" '6'
q 'MATCH(msg, ?q) OR region == "eu"' "$F | WHERE MATCH(msg, ?q) OR region == `"eu`" $c" "[{`"q`": $A}]" '6'
q 'KQL(?q)' "$F | WHERE KQL(?q) $c" "[{`"q`": $A}]" '6'
q 'QSTR(?q)' "$F | WHERE QSTR(?q) $c" "[{`"q`": $A}]" '6'
q 'msg : ?q (match operator)' "$F | WHERE msg : ?q $c" "[{`"q`": $A}]" '6'
q 'os RLIKE ?p' "$F | WHERE os RLIKE ?p $c" "[{`"p`": $A}]" '6 or error'
q 'BUCKET(bytes, ?n, 0, 100000)' "$F | STATS c = COUNT(*) BY b = BUCKET(bytes, ?n, 0, 100000)" "[{`"n`": $A}]" 'clear error'
q 'DATE_DIFF(?u, @timestamp, NOW()) > 0' "$F | WHERE DATE_DIFF(?u, @timestamp, NOW()) > 0 $c" "[{`"u`": $A}]" '6'
q 'unknown column with any' "$F | WHERE nope == ?os $c" $os 'Unknown column [nope]'

'== Joins, FORK, subqueries'
q 'LOOKUP JOIN ON ??k' "$F | LOOKUP JOIN any_lookup ON ??k $c" "[{`"k`": {`"identifier`": $A}}]" 'clear error'
q 'LOOKUP JOIN ON os | WHERE family == ?fam' "$F | LOOKUP JOIN any_lookup ON os | WHERE family == ?fam $c" "[{`"fam`": $A}]" '6'
q 'LOOKUP JOIN expr ON os == l_os AND family == ?fam' "$F | RENAME os AS l_os | LOOKUP JOIN any_lookup ON l_os == os AND family == ?fam $c" "[{`"fam`": $A}]" '6 (join kept)'
q 'LOOKUP JOIN expr ON l_os == ?x (no key)' "$F | RENAME os AS l_os | LOOKUP JOIN any_lookup ON l_os == ?x $c" "[{`"x`": $A}]" 'error, not cross join'
q 'FORK (WHERE os == ?os) (WHERE region == "eu")' "$F | FORK (WHERE os == ?os) (WHERE region == `"eu`") | STATS c = COUNT(*) BY _fork | SORT _fork" $os 'fork1 6 | fork2 3'
q 'subquery FROM (... WHERE os == ?os)' "FROM (FROM any_edge | WHERE os == ?os) $c" $os '6'
