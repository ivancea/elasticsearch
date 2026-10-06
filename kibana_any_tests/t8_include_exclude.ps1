# Validates the compact per-filter include/exclude pattern on the local 9.6 snapshot (any_demo index):
#   ?x IS NULL OR (COALESCE(?x_mode, "include") == "include") == (<match>)
# where <match> = MV_INTERSECTS(?x, f) OR (f IS NULL AND MV_CONTAINS(?x, "__NULL__")) is never null when ?x is set.
$es = 'http://localhost:9200'
$filters = @'
FROM any_demo
| WHERE ?os IS NULL OR (COALESCE(?os_mode, "include") == "include") == (MV_INTERSECTS(?os, os) OR (os IS NULL AND MV_CONTAINS(?os, "__NULL__")))
| WHERE ?tags IS NULL OR (COALESCE(?tags_mode, "include") == "include") == (MV_INTERSECTS(?tags, tags) OR (tags IS NULL AND MV_CONTAINS(?tags, "__NULL__")))
| STATS docs = COUNT(*), no_os = COUNT(*) WHERE os IS NULL, no_tags = COUNT(*) WHERE tags IS NULL
'@
function run([string]$label, [string]$params) {
  $b = '{"query":' + ($filters | ConvertTo-Json -Compress) + ',"params":' + $params + '}'
  try {
    $r = Invoke-WebRequest -Method POST -Uri "$es/_query?format=txt" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -UseBasicParsing
    Write-Output "=== $label`n$($r.Content)"
  } catch { Write-Output "=== $label`n  error: $($_.ErrorDetails.Message)" }
}
run 'Any' '[{"os": null}, {"os_mode": "include"}, {"tags": null}, {"tags_mode": "include"}]'
run 'Any with exclude mode (still Any)' '[{"os": null}, {"os_mode": "exclude"}, {"tags": null}, {"tags_mode": "exclude"}]'
run 'os include linux' '[{"os": "linux"}, {"os_mode": "include"}, {"tags": null}, {"tags_mode": "include"}]'
run 'os exclude linux' '[{"os": "linux"}, {"os_mode": "exclude"}, {"tags": null}, {"tags_mode": "include"}]'
run 'os exclude (No value)' '[{"os": "__NULL__"}, {"os_mode": "exclude"}, {"tags": null}, {"tags_mode": "include"}]'
run 'tags include [prod]' '[{"os": null}, {"os_mode": "include"}, {"tags": ["prod"]}, {"tags_mode": "include"}]'
run 'tags exclude [prod]' '[{"os": null}, {"os_mode": "include"}, {"tags": ["prod"]}, {"tags_mode": "exclude"}]'
run 'tags exclude [prod, (No value)]' '[{"os": null}, {"os_mode": "include"}, {"tags": ["prod", "__NULL__"]}, {"tags_mode": "exclude"}]'
run 'mode cleared (null) acts as include' '[{"os": "linux"}, {"os_mode": null}, {"tags": null}, {"tags_mode": null}]'
run 'os exclude linux AND tags include [prod]' '[{"os": "linux"}, {"os_mode": "exclude"}, {"tags": ["prod"]}, {"tags_mode": "include"}]'
