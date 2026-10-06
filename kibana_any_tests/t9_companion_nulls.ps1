# Validates a type-agnostic "(No value)" via a companion boolean param ?<name>__nulls (local 9.6 snapshot).
#   ?x IS NULL AND NOT ?x__nulls   -> "Any" (nothing selected)
#   MV_INTERSECTS(?x, f)          -> selected values (any field type, cast where needed)
#   ?x__nulls AND f IS NULL        -> "(No value)" selected
$es = 'http://localhost:9200'
function req([string]$method, [string]$path, [string]$body = $null, [string]$ct = 'application/json') {
  [byte[]]$bytes = $null
  if ($body) { $bytes = [Text.Encoding]::UTF8.GetBytes($body) }
  try { (Invoke-WebRequest -Method $method -Uri "$es$path" -ContentType $ct -Body $bytes -UseBasicParsing).Content }
  catch { "error: " + $(if ($_.ErrorDetails) { ($_.ErrorDetails.Message | ConvertFrom-Json).error.reason } else { $_.Exception.Message }) }
}
req DELETE '/nulls_demo' | Out-Null
req PUT '/nulls_demo' '{"mappings":{"properties":{"id":{"type":"integer"},"flag":{"type":"boolean"},"code":{"type":"long"}}}}' | Out-Null
$bulk = @'
{"index":{}}
{"id":1,"flag":true,"code":200}
{"index":{}}
{"id":2,"flag":false,"code":404}
{"index":{}}
{"id":3,"flag":true,"code":500}
{"index":{}}
{"id":4}
{"index":{}}
{"id":5,"flag":[true,false],"code":[200,404]}

'@
req POST '/nulls_demo/_bulk?refresh=true' $bulk 'application/x-ndjson' | Out-Null

function run([string]$label, [string]$where, [string]$params) {
  $q = "FROM nulls_demo`n| WHERE $where`n| SORT id`n| KEEP id, flag, code"
  $b = '{"query":' + ($q | ConvertTo-Json -Compress) + ',"params":' + $params + '}'
  Write-Output "=== $label  $params"
  Write-Output (req POST '/_query?format=txt' $b)
}
$boolWhere = '(?f IS NULL AND NOT ?f__nulls) OR MV_INTERSECTS(?f, flag) OR (?f__nulls AND flag IS NULL)'
run 'boolean: Any' $boolWhere '[{"f": null}, {"f__nulls": false}]'
run 'boolean: [true]' $boolWhere '[{"f": [true]}, {"f__nulls": false}]'
run 'boolean: (No value) only' $boolWhere '[{"f": null}, {"f__nulls": true}]'
run 'boolean: [true] + (No value)' $boolWhere '[{"f": [true]}, {"f__nulls": true}]'

$longWhere = '(?c IS NULL AND NOT ?c__nulls) OR MV_INTERSECTS(TO_LONG(?c), code) OR (?c__nulls AND code IS NULL)'
run 'long: Any' $longWhere '[{"c": null}, {"c__nulls": false}]'
run 'long: [404]' $longWhere '[{"c": [404]}, {"c__nulls": false}]'
run 'long: [404] + (No value)' $longWhere '[{"c": [404]}, {"c__nulls": true}]'
run 'long: (No value) only' $longWhere '[{"c": null}, {"c__nulls": true}]'
run 'companion param missing' $longWhere '[{"c": null}]'
