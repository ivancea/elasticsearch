# Query shapes found in Slack control threads, probed with "__ANY__" and null on the local ES
# (branch investigations/kibana-any).
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
  "{0,-62} {1}" -f $label, $out
}
$c = '| STATS docs = COUNT(*)'
$any = '"__ANY__"'

'== OTel RUM integration: IS NOT NULL AND MV_CONTAINS(?p, field)'
$rum = "FROM any_demo | WHERE os IS NOT NULL AND MV_CONTAINS(?os, os) $c"
q 'rum any' $rum "[{`"os`": $any}]"
q 'rum null' $rum '[{"os": null}]'
q 'rum linux' $rum '[{"os": "linux"}]'
q 'rum: filter after computed column, any' "FROM any_demo | EVAL os_u = TO_UPPER(os) | WHERE MV_CONTAINS(?os, os_u) $c" "[{`"os`": $any}]"
q 'rum: ??agg_func(bytes)::double, any' 'FROM any_demo | STATS v = ??f(bytes)::double' "[{`"f`": $any}]"
q 'rum: ??agg_func(bytes)::double, null' 'FROM any_demo | STATS v = ??f(bytes)::double' '[{"f": null}]'

'== Mirko Bez: "all" option'
$all = "FROM any_demo | WHERE `"all`" == ?h OR host == ?h $c"
q 'all-trick any' $all "[{`"h`": $any}]"
q 'all-trick "all"' $all '[{"h": "all"}]'

'== Philipp Kahr / Elliot Laidlaw: one comma-joined value, SPLIT in EVAL'
$split = "FROM any_demo | EVAL ids = SPLIT(?ids, `",`") | WHERE MV_CONTAINS(ids, host) $c"
q 'split any' $split "[{`"ids`": $any}]"
q 'split null' $split '[{"ids": null}]'
q 'split inline (no EVAL), any' "FROM any_demo | WHERE MV_CONTAINS(SPLIT(?ids, `",`"), host) $c" "[{`"ids`": $any}]"

'== Kyle Zeinemann: free-text IP vs CIDR column'
$cidr = 'ROW ip_range = ["10.0.0.0/8", "192.168.0.0/16"] | MV_EXPAND ip_range | WHERE CIDR_MATCH(TO_IP(?ip), ip_range)'
q 'cidr 10.1.2.3' $cidr '[{"ip": "10.1.2.3"}]'
q 'cidr any' $cidr "[{`"ip`": $any}]"

'== Cesar Munoz: version "1.0" arrives as a number from Kibana'
$ver = 'ROW version = "1.0" | WHERE version == ?v'
q 'version "1.0" (string)' $ver '[{"v": "1.0"}]'
q 'version 1.0 (number, what Kibana sends)' $ver '[{"v": 1.0}]'
q 'version TO_STRING(?v), number' 'ROW version = "1.0" | WHERE version == TO_STRING(?v)' '[{"v": 1.0}]'
q 'version TO_STRING(?v), any' 'ROW version = "1.0" | WHERE version == TO_STRING(?v)' "[{`"v`": $any}]"

'== Mirko Bez: label shown, id sent (EVAL then join)'
q 'EVAL key = ?c then filter, any' "FROM any_demo | EVAL key = ?c | WHERE host == key $c" "[{`"c`": $any}]"

'== Other shapes seen in threads'
q 'MATCH(os, ?q) any' "FROM any_demo | WHERE MATCH(os, ?q) $c" "[{`"q`": $any}]"
q 'os LIKE ?p any (pattern param)' "FROM any_demo | WHERE os LIKE ?p $c" "[{`"p`": $any}]"
q 'os LIKE ?p "lin*"' "FROM any_demo | WHERE os LIKE ?p $c" '[{"p": "lin*"}]'
q 'os IN (?a, ?b) a=any' "FROM any_demo | WHERE os IN (?a, ?b) $c" "[{`"a`": $any}, {`"b`": `"linux`"}]"
q 'bytes > ?v::long any' "FROM any_demo | WHERE bytes > ?v::long $c" "[{`"v`": $any}]"
q 'BUCKET(@timestamp, ?interval) any' 'FROM any_demo | STATS docs = COUNT(*) BY b = BUCKET(@timestamp, ?i) | LIMIT 3' "[{`"i`": $any}]"
q 'SORT ??f any' 'FROM any_demo | SORT ??f | LIMIT 1 | KEEP os' "[{`"f`": $any}]"
q 'CASE(?os == "linux", bytes > 5000, true) any' "FROM any_demo | WHERE CASE(?os == `"linux`", bytes > 5000, true) $c" "[{`"os`": $any}]"
q 'CASE(?os == "linux", ...) linux (reference)' "FROM any_demo | WHERE CASE(?os == `"linux`", bytes > 5000, true) $c" '[{"os": "linux"}]'
q 'bytes > 5000 (reference)' "FROM any_demo | WHERE bytes > 5000 $c" '[]'
