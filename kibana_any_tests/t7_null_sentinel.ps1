# Validates the "__NULL__" sentinel filters on the local 9.6 snapshot (any_demo index).
$es = 'http://localhost:9200'
$filters = @'
FROM any_demo
| WHERE ?os IS NULL OR MV_INTERSECTS(?os, os) OR (os IS NULL AND MV_CONTAINS(?os, "__NULL__"))
| WHERE ?tags IS NULL
     OR (COALESCE(?tags_mode, "include") == "include" AND (MV_INTERSECTS(?tags, tags) OR (tags IS NULL AND MV_CONTAINS(?tags, "__NULL__"))))
     OR (COALESCE(?tags_mode, "include") == "exclude" AND NOT (MV_INTERSECTS(?tags, tags) OR (tags IS NULL AND MV_CONTAINS(?tags, "__NULL__"))))
| STATS docs = COUNT(*), no_os = COUNT(*) WHERE os IS NULL, no_tags = COUNT(*) WHERE tags IS NULL
'@
function run([string]$label, [string]$query, [string]$params) {
  $b = '{"query":' + ($query | ConvertTo-Json -Compress) + ',"params":' + $params + '}'
  try {
    $r = Invoke-WebRequest -Method POST -Uri "$es/_query?format=txt" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -UseBasicParsing
    Write-Output "=== $label`n$($r.Content)"
  } catch { Write-Output "=== $label`n  error: $($_.ErrorDetails.Message)" }
}
run 'values query: os options' 'FROM any_demo | STATS BY os | EVAL os = COALESCE(os, "__NULL__") | SORT os' '[]'
run 'values query: tags options' 'FROM any_demo | MV_EXPAND tags | STATS BY tags | EVAL tags = COALESCE(tags, "__NULL__") | SORT tags' '[]'
run 'Any everywhere' $filters '[{"os": null}, {"tags": null}, {"tags_mode": "include"}]'
run 'os = (No value)' $filters '[{"os": "__NULL__"}, {"tags": null}, {"tags_mode": "include"}]'
run 'os = linux' $filters '[{"os": "linux"}, {"tags": null}, {"tags_mode": "include"}]'
run 'tags = [prod]' $filters '[{"os": null}, {"tags": ["prod"]}, {"tags_mode": "include"}]'
run 'tags = [prod, (No value)]' $filters '[{"os": null}, {"tags": ["prod", "__NULL__"]}, {"tags_mode": "include"}]'
run 'tags = [(No value)]' $filters '[{"os": null}, {"tags": ["__NULL__"]}, {"tags_mode": "include"}]'
run 'exclude [prod]' $filters '[{"os": null}, {"tags": ["prod"]}, {"tags_mode": "exclude"}]'
run 'exclude [prod, (No value)]' $filters '[{"os": null}, {"tags": ["prod", "__NULL__"]}, {"tags_mode": "exclude"}]'
