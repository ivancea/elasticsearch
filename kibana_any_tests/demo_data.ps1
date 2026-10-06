# Creates the `any_demo` index on the local (Windows) Elasticsearch started with ./gradlew run.
$es = 'http://localhost:9200'
function req([string]$method, [string]$path, [string]$body = $null, [string]$ct = 'application/json') {
  [byte[]]$bytes = $null
  if ($body) { $bytes = [Text.Encoding]::UTF8.GetBytes($body) }
  try { (Invoke-WebRequest -Method $method -Uri "$es$path" -ContentType $ct -Body $bytes -UseBasicParsing).Content }
  catch { "HTTP error: " + $(if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }) }
}

req DELETE '/any_demo' | Out-Null
req PUT '/any_demo' '{"mappings":{"dynamic":"strict","properties":{"@timestamp":{"type":"date"},"host":{"type":"keyword"},"os":{"type":"keyword"},"region":{"type":"keyword"},"tags":{"type":"keyword"},"status":{"type":"long"},"bytes":{"type":"long"}}}}'

$hosts = 'web-01', 'web-02', 'web-03', 'api-01', 'api-02'
$oses = 'linux', 'windows', 'macos'
$regions = 'eu-west', 'us-east', 'ap-south'
$tagPool = 'prod', 'canary', 'beta', 'internal'
$statuses = 200, 200, 200, 201, 301, 404, 500, 503
$rand = New-Object System.Random 42
$now = [DateTime]::UtcNow
$sb = New-Object System.Text.StringBuilder
for ($i = 0; $i -lt 2000; $i++) {
  $doc = [ordered]@{
    '@timestamp' = $now.AddMinutes(-$rand.Next(0, 7 * 24 * 60)).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    host = $hosts[$rand.Next($hosts.Count)]
    status = $statuses[$rand.Next($statuses.Count)]
    bytes = $rand.Next(200, 20000)
  }
  # ~15% of documents have no os, ~20% no region, ~25% no tags: these are the "blanks"
  if ($rand.NextDouble() -gt 0.15) { $doc.os = $oses[$rand.Next($oses.Count)] }
  if ($rand.NextDouble() -gt 0.20) { $doc.region = $regions[$rand.Next($regions.Count)] }
  if ($rand.NextDouble() -gt 0.25) {
    $n = $rand.Next(1, 3)
    $doc.tags = @($tagPool | Sort-Object { $rand.Next() } | Select-Object -First $n)
  }
  [void]$sb.AppendLine('{"index":{}}')
  [void]$sb.AppendLine(($doc | ConvertTo-Json -Compress))
}
$r = req POST '/any_demo/_bulk?refresh=true' $sb.ToString() 'application/x-ndjson'
if ($r -like 'HTTP error*') { $r } else { 'bulk errors: ' + ($r | ConvertFrom-Json).errors }
req POST '/_query?format=txt' '{"query":"FROM any_demo | STATS docs = COUNT(*), no_os = COUNT(*) WHERE os IS NULL, no_region = COUNT(*) WHERE region IS NULL, no_tags = COUNT(*) WHERE tags IS NULL, multi_tags = COUNT(*) WHERE MV_COUNT(tags) > 1"}'
