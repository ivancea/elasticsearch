# Compares `field == ?x` with `MV_INTERSECTS(?x, field)` for a single-select value, on the local 9.6 snapshot.
$es = 'http://localhost:9200'
function run([string]$label, [string]$query, [string]$params, [switch]$profile) {
  $b = '{"query":' + ($query | ConvertTo-Json -Compress) + ',"params":' + $params + $(if ($profile) { ',"profile":true' } else { '' }) + '}'
  $r = Invoke-WebRequest -Method POST -Uri "$es/_query" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -UseBasicParsing
  $json = $r.Content | ConvertFrom-Json
  Write-Output "=== $label"
  Write-Output ("  rows: " + ($json.values | ForEach-Object { $_ -join ' | ' }))
  if ($r.Headers['Warning']) { Write-Output ("  warning: " + ($r.Headers['Warning'] -split ',')[0]) }
  if ($profile) {
    $plan = ($json.profile.plans | Where-Object { $_.description -like '*data*' } | Select-Object -First 1).plan
    $pushed = if ($plan -match '"terms"|"term"') { 'pushed to Lucene' } elseif ($plan -match 'FilterExec') { 'NOT pushed (FilterExec)' } else { 'no filter' }
    Write-Output "  pushdown: $pushed"
  }
}

$p = '[{"tag": "prod"}]'
run 'tags == ?tag' 'FROM any_demo | WHERE ?tag IS NULL OR tags == ?tag | STATS docs = COUNT(*), multi = COUNT(*) WHERE MV_COUNT(tags) > 1' $p
run 'MV_INTERSECTS(?tag, tags)' 'FROM any_demo | WHERE ?tag IS NULL OR MV_INTERSECTS(?tag, tags) | STATS docs = COUNT(*), multi = COUNT(*) WHERE MV_COUNT(tags) > 1' $p
run 'tags == ?tag (profile)' 'FROM any_demo | WHERE ?tag IS NULL OR tags == ?tag | KEEP host' $p -profile
run 'MV_INTERSECTS single value (profile)' 'FROM any_demo | WHERE ?tag IS NULL OR MV_INTERSECTS(?tag, tags) | KEEP host' $p -profile
run 'MV_INTERSECTS list (profile)' 'FROM any_demo | WHERE ?tag IS NULL OR MV_INTERSECTS(?tag, tags) | KEEP host' '[{"tag": ["prod", "beta"]}]' -profile
run 'MV_INTERSECTS Any (profile)' 'FROM any_demo | WHERE ?tag IS NULL OR MV_INTERSECTS(?tag, tags) | KEEP host' '[{"tag": null}]' -profile
run 'long field, int param, ==' 'FROM any_demo | WHERE ?s IS NULL OR status == ?s | STATS docs = COUNT(*)' '[{"s": 404}]'
try { run 'long field, int param, MV_INTERSECTS' 'FROM any_demo | WHERE ?s IS NULL OR MV_INTERSECTS(?s, status) | STATS docs = COUNT(*)' '[{"s": 404}]' } catch { "=== long field, int param, MV_INTERSECTS`n  error: " + ($_.ErrorDetails.Message | ConvertFrom-Json).error.reason }
run 'long field, TO_LONG(param), MV_INTERSECTS' 'FROM any_demo | WHERE ?s IS NULL OR MV_INTERSECTS(TO_LONG(?s), status) | STATS docs = COUNT(*)' '[{"s": 404}]'
