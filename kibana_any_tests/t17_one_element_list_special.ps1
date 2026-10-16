# Follow-up to t16 for cases needing extra setup: flattened and dense_vector fields, a time series index, FUSE/LIMIT BY
# and inference commands. Each query template has a {v} constant that runs as a scalar param (baseline), a one-element
# list param and a one-element list literal; forms whose result differs from the baseline are reported.
# Uses ES_CLOUD_HOST / ES_CLOUD_API_KEY from the environment. Pass -Cleanup to delete the probe indices and exit.
param([string]$Only = '', [switch]$Cleanup, [switch]$SkipInference)

$es = $env:ES_CLOUD_HOST.TrimEnd('/')
$headers = @{ Authorization = "ApiKey $env:ES_CLOUD_API_KEY" }
$base = 'one_elem_list_probe'
$extra = 'one_elem_list_probe_x'
$ts = 'one_elem_list_probe_ts'

function req([string]$method, [string]$path, [string]$body = $null) {
  $request = @{ Method = $method; Uri = "$es$path"; Headers = $headers; UseBasicParsing = $true; ContentType = 'application/json' }
  if ($body) { $request.Body = [Text.Encoding]::UTF8.GetBytes($body) }
  Invoke-WebRequest @request
}

if ($Cleanup) {
  foreach ($i in @($base, $extra, $ts)) { try { req DELETE "/$i" | Out-Null; "deleted $i" } catch { "not deleted ${i}: $($_.Exception.Message)" } }
  return
}

function setup() {
  foreach ($i in @($extra, $ts)) { try { req DELETE "/$i" | Out-Null } catch {} }
  req PUT "/$extra" '{"settings":{"number_of_shards":1,"number_of_replicas":0},"mappings":{"properties":{
    "id":{"type":"integer"},"host":{"type":"keyword"},"msg":{"type":"text"},"flat":{"type":"flattened"},
    "vec1":{"type":"dense_vector","dims":1,"similarity":"l2_norm"},"vec3":{"type":"dense_vector","dims":3,"similarity":"l2_norm"}}}}' | Out-Null
  $docs = @(
    '{"id":1,"host":"web-01","msg":"quick brown fox","flat":{"a":"x","b":{"c":"y"}},"vec1":[0.5],"vec3":[1.0,0.0,0.0]}',
    '{"id":2,"host":"db-02","msg":"lazy dog","flat":{"a":"z"},"vec1":[2.0],"vec3":[0.0,1.0,0.0]}',
    '{"id":3,"host":"web-03","msg":"brown cow","flat":{"a":"x"},"vec1":[0.4],"vec3":[0.9,0.1,0.0]}'
  )
  $bulk = ($docs | ForEach-Object { "{`"index`":{}}`n$_" }) -join "`n"
  req POST "/$extra/_bulk?refresh=true" ($bulk + "`n") | Out-Null

  req PUT "/$ts" '{"settings":{"index.mode":"time_series","index.routing_path":["host"],"number_of_shards":1,"number_of_replicas":0},
    "mappings":{"properties":{"@timestamp":{"type":"date"},"host":{"type":"keyword","time_series_dimension":true},
    "bytes":{"type":"long","time_series_metric":"counter"},"cpu":{"type":"double","time_series_metric":"gauge"}}}}' | Out-Null
  $now = [DateTime]::UtcNow
  $lines = @()
  foreach ($h in @('web-01', 'db-02')) {
    $bytes = 0
    foreach ($m in @(90, 60, 30, 5)) {
      $bytes += if ($h -eq 'web-01') { 1000 } else { 300 }
      $t = $now.AddMinutes(-$m).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
      $cpu = if ($h -eq 'web-01') { 0.5 + $m / 1000 } else { 0.2 + $m / 1000 }
      $lines += '{"create":{}}'
      $lines += "{`"@timestamp`":`"$t`",`"host`":`"$h`",`"bytes`":$bytes,`"cpu`":$cpu}"
    }
  }
  $r = req POST "/$ts/_bulk?refresh=true" (($lines -join "`n") + "`n")
  if (($r.Content | ConvertFrom-Json).errors) { throw "time series bulk failed: $($r.Content)" }
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

$fork = "FROM $base METADATA _id, _index, _score | FORK (WHERE MATCH(msg, `"brown`")) (WHERE MATCH(msg, `"fox`")) | LIMIT 10"
$reranker = '.jina-reranker-v3'
$completion = '.google-gemini-2.5-flash-lite-completion'
$embedding = '.jina-embeddings-v5-text-nano'

# name, query template, scalar JSON, inference (calls an inference endpoint)
$cases = @(
  @('LIMIT BY', "FROM $base | LIMIT {v} BY host | STATS c = COUNT(*)", '1', $false),
  @('FUSE rrf rank_constant', "$fork | FUSE WITH {`"rank_constant`": {v}} | SORT _score DESC, _id | KEEP _id, _score", '20', $false),
  @('FUSE linear normalizer', "$fork | FUSE LINEAR WITH {`"normalizer`": {v}} | SORT _score DESC, _id | KEEP _id, _score", '"minmax"', $false),
  @('FUSE weights value', "$fork | FUSE WITH {`"weights`": {`"fork1`": {v}, `"fork2`": 1}} | SORT _score DESC, _id | KEEP _id, _score", '2', $false),
  @('CATEGORIZE option', "FROM $base | STATS c = COUNT(*) BY k = CATEGORIZE(msg, {`"output_format`": {v}}) | SORT k", '"tokens"', $false),
  @('FIELD_EXTRACT path', "FROM $extra | SORT id | EVAL r = FIELD_EXTRACT(flat, {v}) | KEEP r", '"a"', $false),
  @('FIELD_EXTRACT ==', "FROM $extra | WHERE FIELD_EXTRACT(flat, `"a`") == {v} | STATS c = COUNT(*)", '"x"', $false),
  @('FIELD_EXTRACT !=', "FROM $extra | WHERE FIELD_EXTRACT(flat, `"a`") != {v} | STATS c = COUNT(*)", '"x"', $false),
  @('flattened subfield ==', "FROM $extra | WHERE flat.a == {v} | STATS c = COUNT(*)", '"x"', $false),
  @('KNN 1-dim', "FROM $extra | WHERE KNN(vec1, {v}) | SORT id | KEEP id", '0.5', $false),
  @('V_L2_NORM 1-dim', "FROM $extra | SORT id | EVAL r = V_L2_NORM(vec1, {v}) | KEEP r", '0.5', $false),
  @('V_COSINE 1-dim', "FROM $extra | SORT id | EVAL r = V_COSINE(vec1, {v}) | KEEP r", '0.5', $false),
  @('MMR lambda', "FROM $extra | SORT id | LIMIT 10 | MMR ON vec3 LIMIT 2 WITH {`"lambda`": {v}} | KEEP id", '0.5', $false),
  @('MMR query vector 1-dim', "FROM $extra | SORT id | LIMIT 10 | MMR {v} ON vec1 LIMIT 2 | KEEP id", '0.5', $false),
  @('TS TBUCKET string', "TS $ts | STATS r = SUM(RATE(bytes)) BY k = TBUCKET({v}) | SORT k | KEEP r", '"1 hour"', $false),
  @('TS BUCKET string', "TS $ts | STATS r = AVG(cpu) BY k = BUCKET(@timestamp, {v}) | SORT k | KEEP r", '"1 hour"', $false),
  @('TS dimension ==', "TS $ts | WHERE host == {v} | STATS r = SUM(RATE(bytes))", '"web-01"', $false),
  @('TS STARTS_WITH dimension', "TS $ts | WHERE STARTS_WITH(host, {v}) | STATS r = SUM(RATE(bytes))", '"web"', $false),
  @('TS RATE window', "TS $ts | STATS r = SUM(RATE(bytes, {v})) BY k = TBUCKET(1 hour) | SORT k | KEEP r", '"1 hour"', $false),
  @('TS AVG_OVER_TIME window', "TS $ts | STATS r = AVG(AVG_OVER_TIME(cpu, {v})) BY k = TBUCKET(1 hour) | SORT k | KEEP r", '"1 hour"', $false),
  @('TS PERCENTILE_OVER_TIME', "TS $ts | STATS r = MAX(PERCENTILE_OVER_TIME(cpu, {v})) BY host | SORT host | KEEP r", '50', $false),
  @('RERANK query text', "FROM $base | SORT id | LIMIT 3 | RERANK {v} ON msg WITH {`"inference_id`": `"$reranker`"} | KEEP id", '"brown fox"', $true),
  @('RERANK inference_id', "FROM $base | SORT id | LIMIT 3 | RERANK `"brown fox`" ON msg WITH {`"inference_id`": {v}} | KEEP id", "`"$reranker`"", $true),
  @('COMPLETION inference_id', "ROW p = `"Reply with the single word OK`" | COMPLETION r = p WITH {`"inference_id`": {v}} | EVAL ok = r IS NOT NULL | KEEP ok", "`"$completion`"", $true),
  @('COMPLETION prompt', "ROW x = 1 | COMPLETION r = {v} WITH {`"inference_id`": `"$completion`"} | EVAL ok = r IS NOT NULL | KEEP ok", '"Reply with the single word OK"', $true),
  @('TEXT_EMBEDDING inference_id', "ROW r = TEXT_EMBEDDING(`"hello`", {v}) | EVAL ok = r IS NOT NULL | KEEP ok", "`"$embedding`"", $true),
  @('TEXT_EMBEDDING text', "ROW r = TEXT_EMBEDDING({v}, `"$embedding`") | EVAL ok = r IS NOT NULL | KEEP ok", '"hello"', $true)
)

setup
$affected = @()
foreach ($c in $cases) {
  $name, $template, $scalar, $inference = $c
  if ($Only -and $name -notmatch $Only) { continue }
  if ($SkipInference -and $inference) { continue }
  "=== $name   v=$scalar"
  "  $template"
  $baseline = run $template.Replace('{v}', '?p') $scalar
  $listParam = run $template.Replace('{v}', '?p') "[$scalar]"
  $listLiteral = run $template.Replace('{v}', "[$scalar]") $null
  $diffs = @()
  if ($listParam -ne $baseline) { $diffs += "list param -> $listParam" }
  if ($listLiteral -ne $baseline) { $diffs += "list literal -> $listLiteral" }
  if ($diffs) {
    "  DIFF  scalar -> $baseline"
    $diffs | ForEach-Object { "        $_" }
    $affected += $name
  } else {
    "  same  $baseline"
  }
}
''
'=== AFFECTED'
$affected
