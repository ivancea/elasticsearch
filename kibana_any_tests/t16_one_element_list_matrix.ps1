# Which functions/commands treat a one-element list constant differently from the scalar?
# For each case, the constant is passed as a scalar param (baseline), a one-element list param and a one-element list
# literal. Each case runs folded (ROW source), evaluated (FROM ... | EVAL) and, for predicates, pushed down
# (FROM ... | WHERE). A form is reported when its result differs from the baseline.
# Uses ES_CLOUD_HOST / ES_CLOUD_API_KEY from the environment.
param([string]$Only = '', [switch]$Local)

if ($Local) {
  $es = 'http://localhost:9200'
  $headers = @{}
} else {
  $es = $env:ES_CLOUD_HOST.TrimEnd('/')
  $headers = @{ Authorization = "ApiKey $env:ES_CLOUD_API_KEY" }
}
$index = 'one_elem_list_probe'

function req([string]$method, [string]$path, [string]$body = $null) {
  $request = @{ Method = $method; Uri = "$es$path"; Headers = $headers; UseBasicParsing = $true; ContentType = 'application/json' }
  if ($body) { $request.Body = [Text.Encoding]::UTF8.GetBytes($body) }
  Invoke-WebRequest @request
}

function setup() {
  try { req DELETE "/$index" | Out-Null } catch {}
  req PUT "/$index" '{"settings":{"number_of_shards":1,"number_of_replicas":0},"mappings":{"properties":{
    "id":{"type":"integer"},"host":{"type":"keyword"},"msg":{"type":"text"},"ip":{"type":"ip"},"ts":{"type":"date"},
    "ds":{"type":"keyword"},"n":{"type":"long"},"n_mv":{"type":"long"},"d":{"type":"double"},"b":{"type":"boolean"},
    "v":{"type":"version"},"geo":{"type":"geo_point"},"a":{"type":"keyword"},"a2":{"type":"keyword"}}}}' | Out-Null
  $docs = @(
    '{"id":1,"host":"web-01","msg":"quick brown fox","ip":"192.168.1.1","ts":"2024-01-15T10:00:00Z","ds":"2024-01-15","n":150,"n_mv":[3,1,2],"d":3.14159,"b":true,"v":"1.2.3","geo":"POINT(-71.34 41.12)","a":["x","y"],"a2":["1","2"]}',
    '{"id":2,"host":"db-02","msg":"lazy dog","ip":"10.0.0.5","ts":"2023-06-01T00:00:00Z","ds":"2023-06-01","n":42,"n_mv":[10,20],"d":2.5,"b":false,"v":"2.0.0","geo":"POINT(2.35 48.85)","a":["z"],"a2":["3"]}',
    '{"id":3,"host":"web-03","msg":"brown cow","ip":"192.168.2.7","ts":"2024-03-02T12:30:00Z","ds":"2024-03-02","n":999,"n_mv":[7],"d":0.5,"b":true,"v":"1.10.0","geo":"POINT(-70.9 42.3)","a":["x"],"a2":["4"]}'
  )
  $bulk = ($docs | ForEach-Object { "{`"index`":{}}`n$_" }) -join "`n"
  req POST "/$index/_bulk?refresh=true" ($bulk + "`n") | Out-Null
}

function run([string]$query, [string]$paramJson) {
  $q = ConvertTo-Json $query -Compress
  $body = if ($paramJson) { "{`"query`":$q,`"params`":[{`"p`":$paramJson}]}" } else { "{`"query`":$q}" }
  try {
    $resp = req POST '/_query' $body
    $j = $resp.Content | ConvertFrom-Json
    $out = ConvertTo-Json -InputObject $j.values -Compress -Depth 10
    if ($j.is_partial) { $out += ' PARTIAL' }
    $w = @($resp.Headers['Warning']) | Where-Object { $_ -and $_ -notmatch 'No limit defined' }
    if ($w) { $out += ' WARN:' + ((@($w) | ForEach-Object { ($_ -replace '^299 Elasticsearch-\S+ "', '') -replace '"$', '' }) -join ' / ') }
    $out
  } catch {
    $msg = $_.ErrorDetails.Message
    try { $msg = ($msg | ConvertFrom-Json).error.reason } catch {}
    'ERROR: ' + ((($msg -split "`n") | Where-Object { $_ -and $_ -notmatch '^Found \d+ problem' }) -join ' / ')
  }
}

$row = 'ROW id = 1, host = "web-01", msg = "quick brown fox", ip = TO_IP("192.168.1.1"), ts = TO_DATETIME("2024-01-15T10:00:00Z"), ' +
  'ds = "2024-01-15", n = 150, n_mv = [3, 1, 2], d = 3.14159, b = true, v = TO_VERSION("1.2.3"), ' +
  'geo = TO_GEOPOINT("POINT(-71.34 41.12)"), a = ["x", "y"], a2 = ["1", "2"]'
$from = "FROM $index"

# kind: bool = predicate (ROW/EVAL/WHERE), val = value (ROW/EVAL), agg = aggregation (STATS), cmd = full query with {src}
$cases = @(
  @('bool', 'STARTS_WITH', 'STARTS_WITH(host, {v})', '"web"'),
  @('bool', 'ENDS_WITH', 'ENDS_WITH(host, {v})', '"01"'),
  @('bool', 'CONTAINS', 'CONTAINS(host, {v})', '"eb"'),
  @('bool', 'CIDR_MATCH', 'CIDR_MATCH(ip, {v})', '"192.168.0.0/16"'),
  @('bool', 'CIDR_MATCH 2nd block', 'CIDR_MATCH(ip, "10.0.0.0/8", {v})', '"192.168.0.0/16"'),
  @('bool', 'keyword ==', 'host == {v}', '"web-01"'),
  @('bool', 'keyword !=', 'host != {v}', '"web-01"'),
  @('bool', 'text ==', 'msg == {v}', '"lazy dog"'),
  @('bool', 'keyword IN', 'host IN ({v}, "zzz")', '"web-01"'),
  @('bool', 'keyword IN single', 'host IN ({v})', '"web-01"'),
  @('bool', 'long IN', 'n IN ({v}, 1)', '42'),
  @('bool', 'long >', 'n > {v}', '100'),
  @('bool', 'double <=', 'd <= {v}', '3'),
  @('bool', 'ip == string', 'ip == {v}', '"192.168.1.1"'),
  @('bool', 'date > string', 'ts > {v}', '"2024-01-01"'),
  @('bool', 'version == string', 'v == {v}', '"1.2.3"'),
  @('bool', 'boolean ==', 'b == {v}', 'true'),
  @('bool', 'TO_LOWER(x) ==', 'TO_LOWER(host) == {v}', '"web-01"'),
  @('bool', 'TO_UPPER(x) ==', 'TO_UPPER(host) == {v}', '"WEB-01"'),
  @('bool', 'LIKE', 'host LIKE {v}', '"web*"'),
  @('bool', 'RLIKE', 'host RLIKE {v}', '"web.*"'),
  @('bool', 'MATCH', 'MATCH(msg, {v})', '"brown"'),
  @('bool', 'match operator', 'msg : {v}', '"brown"'),
  @('bool', 'MATCH_PHRASE', 'MATCH_PHRASE(msg, {v})', '"brown fox"'),
  @('bool', 'QSTR', 'QSTR({v})', '"msg:brown"'),
  @('bool', 'KQL', 'KQL({v})', '"msg:brown"'),
  @('bool', 'TERM', 'TERM(host, {v})', '"web-01"'),
  @('bool', 'MV_CONTAINS', 'MV_CONTAINS(a, {v})', '"x"'),
  @('bool', 'WHERE constant', '{v}', 'true'),
  @('bool', 'ST_INTERSECTS string', 'ST_INTERSECTS(geo, {v})', '"POLYGON((-80 30, -60 30, -60 50, -80 50, -80 30))"'),
  @('bool', 'ST_INTERSECTS TO_GEOSHAPE', 'ST_INTERSECTS(geo, TO_GEOSHAPE({v}))', '"POLYGON((-80 30, -60 30, -60 50, -80 50, -80 30))"'),
  @('bool', 'ST_DISTANCE <', 'ST_DISTANCE(geo, TO_GEOPOINT({v})) < 1000000', '"POINT(-71 41)"'),
  @('bool', 'ip == TO_IP', 'ip == TO_IP({v})', '"192.168.1.1"'),
  @('bool', 'keyword NOT IN', 'host NOT IN ({v}, "zzz")', '"web-01"'),
  @('bool', 'TO_LOWER(x) IN', 'TO_LOWER(host) IN ({v}, "zzz")', '"web-01"'),
  @('bool', 'LIKE list', 'host LIKE ({v}, "zzz*")', '"web*"'),
  @('bool', 'STARTS_WITH constant first', 'STARTS_WITH({v}, host)', '"web-01-extra"'),
  @('bool', 'version >', 'v > {v}', '"1.5.0"'),
  @('bool', 'ip IN string', 'ip IN ({v}, "1.1.1.1")', '"192.168.1.1"'),
  @('bool', 'insensitive ~', 'host ~ {v}', '"WEB-01"'),
  @('bool', 'MATCH option value', 'MATCH(msg, "brown fox", {"operator": {v}})', '"AND"'),
  @('val', 'ST_SIMPLIFY', 'ST_SIMPLIFY(TO_GEOSHAPE("LINESTRING(0 0, 1 1, 2 2)"), {v})', '0.5'),
  @('val', 'ST_BUFFER', 'ST_BUFFER(geo, {v})', '0.1'),
  @('val', 'DECAY', 'DECAY(n, 100, 50, {"type": {v}})', '"linear"'),
  @('val', 'DATE_FORMAT', 'DATE_FORMAT({v}, ts)', '"yyyy"'),
  @('val', 'DATE_PARSE', 'DATE_PARSE({v}, ds)', '"yyyy-MM-dd"'),
  @('val', 'DATE_EXTRACT', 'DATE_EXTRACT({v}, ts)', '"year"'),
  @('val', 'DATE_DIFF', 'DATE_DIFF({v}, ts, TO_DATETIME("2025-01-01"))', '"day"'),
  @('val', 'DATE_TRUNC string', 'DATE_TRUNC({v}, ts)', '"1 day"'),
  @('val', 'TO_DATETIME', 'TO_DATETIME({v})', '"2024-01-01T00:00:00Z"'),
  @('val', 'ROUND', 'ROUND(d, {v})', '2'),
  @('val', 'ROUND_TO', 'ROUND_TO(n, {v}, 1000)', '100'),
  @('val', 'LOG base', 'LOG({v}, d)', '10'),
  @('val', 'POW', 'POW(d, {v})', '2'),
  @('val', 'arithmetic +', 'n + {v}', '1'),
  @('val', 'GREATEST', 'GREATEST(n, {v})', '500'),
  @('val', 'COALESCE', 'COALESCE(host, {v})', '"x"'),
  @('val', 'CASE value', 'CASE(b, {v}, "no")', '"yes"'),
  @('val', 'CASE condition', 'CASE({v}, host, "no")', 'true'),
  @('val', 'LOCATE', 'LOCATE(host, {v})', '"b"'),
  @('val', 'REPLACE regex', 'REPLACE(host, {v}, "X")', '"w"'),
  @('val', 'REPLACE replacement', 'REPLACE(host, "w", {v})', '"X"'),
  @('val', 'SPLIT', 'SPLIT(host, {v})', '"-"'),
  @('val', 'SUBSTRING', 'SUBSTRING(host, {v}, 2)', '2'),
  @('val', 'LEFT', 'LEFT(host, {v})', '2'),
  @('val', 'REPEAT', 'REPEAT(host, {v})', '2'),
  @('val', 'CONCAT', 'CONCAT(host, {v})', '"!"'),
  @('val', 'HASH', 'HASH({v}, host)', '"md5"'),
  @('val', 'SPACE', 'SPACE({v})', '2'),
  @('val', 'IP_PREFIX', 'IP_PREFIX(ip, {v}, 0)', '24'),
  @('val', 'MV_SORT', 'MV_SORT(n_mv, {v})', '"DESC"'),
  @('val', 'MV_SLICE', 'MV_SLICE(n_mv, {v}, 1)', '0'),
  @('val', 'MV_ZIP', 'MV_ZIP(a, a2, {v})', '"|"'),
  @('val', 'MV_CONCAT', 'MV_CONCAT(a, {v})', '"|"'),
  @('val', 'MV_PERCENTILE', 'MV_PERCENTILE(n_mv, {v})', '50'),
  @('val', 'MV_PSERIES_WEIGHTED_SUM', 'MV_PSERIES_WEIGHTED_SUM(TO_DOUBLE(n_mv), {v})', '1.5'),
  @('val', 'ST_GEOHASH', 'ST_GEOHASH(geo, {v})', '3'),
  @('val', 'ST_GEOTILE', 'ST_GEOTILE(geo, {v})', '3'),
  @('val', 'ST_GEOHEX', 'ST_GEOHEX(geo, {v})', '3'),
  @('agg', 'PERCENTILE', 'PERCENTILE(n, {v})', '50'),
  @('agg', 'TOP limit', 'TOP(n, {v}, "desc")', '2'),
  @('agg', 'TOP order', 'TOP(n, 2, {v})', '"desc"'),
  @('agg', 'COUNT_DISTINCT precision', 'COUNT_DISTINCT(host, {v})', '1000'),
  @('agg', 'SAMPLE', 'MV_COUNT(SAMPLE(n, {v}))', '2'),
  @('agg', 'COUNT constant', 'COUNT({v})', '"a"'),
  @('agg', 'SUM constant', 'SUM({v})', '2'),
  @('agg', 'WEIGHTED_AVG weight', 'WEIGHTED_AVG(n, {v})', '2'),
  @('agg', 'STATS ... WHERE', 'COUNT(*) WHERE {v}', 'true'),
  @('cmd', 'BUCKET numeric span', '{src} | STATS c = COUNT(*) BY k = BUCKET(n, {v}) | SORT k', '100'),
  @('cmd', 'BUCKET target buckets', '{src} | STATS c = COUNT(*) BY k = BUCKET(n, {v}, 0, 1000) | SORT k', '10'),
  @('cmd', 'BUCKET date span string', '{src} | STATS c = COUNT(*) BY k = BUCKET(ts, {v}) | SORT k', '"1 year"'),
  @('cmd', 'STATS BY constant', '{src} | STATS c = COUNT(*) BY k = {v}', '"g"'),
  @('cmd', 'LIMIT', '{src} | LIMIT {v} | STATS c = COUNT(*)', '2'),
  @('cmd', 'EVAL x then ==', '{src} | EVAL x = {v} | WHERE host == x | STATS c = COUNT(*)', '"web-01"'),
  @('cmd', 'EVAL x then STARTS_WITH', '{src} | EVAL x = {v} | WHERE STARTS_WITH(host, x) | STATS c = COUNT(*)', '"web"'),
  @('cmd', 'EVAL x then CIDR_MATCH', '{src} | EVAL x = {v} | WHERE CIDR_MATCH(ip, x) | STATS c = COUNT(*)', '"192.168.0.0/16"'),
  @('cmd', 'GROK pattern', '{src} | GROK host {v} | KEEP h', '"%{WORD:h}-%{NUMBER}"'),
  @('cmd', 'DISSECT pattern', '{src} | DISSECT host {v} | KEEP h', '"%{h}-%{num}"'),
  @('cmd', 'SORT + LIMIT', '{src} | SORT n DESC | LIMIT {v} | KEEP n', '1'),
  @('cmd', 'SAMPLE command', '{src} | SAMPLE {v} | STATS c = COUNT(*) | EVAL ok = c >= 0 | KEEP ok', '0.5'),
  @('cmd', 'BUCKET date start bound', '{src} | STATS c = COUNT(*) BY k = BUCKET(ts, 5, {v}, "2025-01-01") | SORT k', '"2023-01-01"'),
  @('cmd', 'EVAL x then TO_LOWER ==', '{src} | EVAL x = {v} | WHERE TO_LOWER(host) == x | STATS c = COUNT(*)', '"web-01"'),
  @('cmd', 'STATS WHERE STARTS_WITH', '{src} | STATS c = COUNT(*) WHERE STARTS_WITH(host, {v})', '"web"')
)

function queries($kind, $expr) {
  switch ($kind) {
    'bool' { [ordered]@{
      'ROW|WHERE' = "$row | WHERE $expr | STATS c = COUNT(*)"
      'FROM|EVAL' = "$from | SORT id | EVAL r = $expr | KEEP r"
      'FROM|WHERE' = "$from | WHERE $expr | STATS c = COUNT(*)"
    } }
    'val' { [ordered]@{
      'ROW|EVAL' = "$row | EVAL r = $expr | KEEP r"
      'FROM|EVAL' = "$from | SORT id | EVAL r = $expr | KEEP r"
    } }
    'agg' { [ordered]@{
      'ROW|STATS' = "$row | STATS r = $expr"
      'FROM|STATS' = "$from | STATS r = $expr"
    } }
    'cmd' { [ordered]@{
      'ROW' = $expr.Replace('{src}', $row)
      'FROM' = $expr.Replace('{src}', $from)
    } }
    default { throw "unknown kind [$kind]" }
  }
}

setup
$affected = @()
foreach ($c in $cases) {
  $kind, $name, $template, $scalar = $c
  if ($Only -and $name -notmatch $Only) { continue }
  "=== $name   [$template]  v=$scalar"
  $qs = queries $kind $template
  foreach ($ctx in $qs.Keys) {
    $q = $qs[$ctx]
    $base = run $q.Replace('{v}', '?p') $scalar
    $listParam = run $q.Replace('{v}', '?p') "[$scalar]"
    $listLiteral = run $q.Replace('{v}', "[$scalar]") $null
    $diffs = @()
    if ($listParam -ne $base) { $diffs += "list param -> $listParam" }
    if ($listLiteral -ne $base) { $diffs += "list literal -> $listLiteral" }
    if ($diffs) {
      "  {0,-11} DIFF  scalar -> {1}" -f $ctx, $base
      $diffs | ForEach-Object { "                    $_" }
      $affected += "$name @ $ctx"
    } else {
      "  {0,-11} same  {1}" -f $ctx, $base
    }
  }
}
''
'=== AFFECTED'
$affected
