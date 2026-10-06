# Adds two fields with missing values to any_demo, for the "?x__nulls" companion demo:
#   priority (integer, ~20% missing) and secure (boolean, ~15% missing).
# Values are derived deterministically from existing fields, so existing counts don't change.
$es = 'http://localhost:9200'
function req([string]$method, [string]$path, [string]$body = $null) {
  [byte[]]$bytes = $null
  if ($body) { $bytes = [Text.Encoding]::UTF8.GetBytes($body) }
  try { (Invoke-WebRequest -Method $method -Uri "$es$path" -ContentType 'application/json' -Body $bytes -UseBasicParsing).Content }
  catch { "HTTP error: " + $(if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }) }
}
req PUT '/any_demo/_mapping' '{"properties":{"priority":{"type":"integer"},"secure":{"type":"boolean"}}}'
$script = @'
{
  "script": {
    "lang": "painless",
    "source": "long b = ctx._source.bytes; if (b % 5 != 0) { ctx._source.priority = (int)(b % 4) + 1; } else { ctx._source.remove('priority'); } if (b % 7 != 0) { ctx._source.secure = (b % 3 != 0); } else { ctx._source.remove('secure'); }"
  }
}
'@
$r = req POST '/any_demo/_update_by_query?refresh=true&conflicts=proceed' $script
if ($r -like 'HTTP error*') { $r } else { $j = $r | ConvertFrom-Json; "updated: $($j.updated) failures: $($j.failures.Count)" }
req POST '/_query?format=txt' '{"query":"FROM any_demo | STATS docs = COUNT(*), no_priority = COUNT(*) WHERE priority IS NULL, no_secure = COUNT(*) WHERE secure IS NULL"}'
