# Loads the local any_demo shape onto the cloud cluster (ES_CLOUD_HOST / ES_CLOUD_API_KEY).
# Same seed and field rules as demo_data.ps1, demo_data_nulls.ps1 and demo_data_compare.ps1.
. "$PSScriptRoot\es.ps1"

$mapping = '{"mappings":{"dynamic":"strict","properties":{"@timestamp":{"type":"date"},"host":{"type":"keyword"},"os":{"type":"keyword"},"region":{"type":"keyword"},"tags":{"type":"keyword"},"status":{"type":"long"},"bytes":{"type":"long"},"priority":{"type":"integer"},"secure":{"type":"boolean"},"latency_ms":{"type":"integer"},"client_ip":{"type":"ip"}}}}'
$created = es PUT '/any_demo' $mapping
if ($created -like 'HTTP *') { $created; exit 1 }
"created index any_demo"

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
  if ($rand.NextDouble() -gt 0.15) { $doc.os = $oses[$rand.Next($oses.Count)] }
  if ($rand.NextDouble() -gt 0.20) { $doc.region = $regions[$rand.Next($regions.Count)] }
  if ($rand.NextDouble() -gt 0.25) {
    $n = $rand.Next(1, 3)
    $doc.tags = @($tagPool | Sort-Object { $rand.Next() } | Select-Object -First $n)
  }
  [void]$sb.AppendLine('{"index":{}}')
  [void]$sb.AppendLine(($doc | ConvertTo-Json -Compress))
}
$bulk = es POST '/any_demo/_bulk?refresh=true' $sb.ToString() 'application/x-ndjson'
if ($bulk -like 'HTTP *') { $bulk; exit 1 }
"bulk errors: $(($bulk | ConvertFrom-Json).errors)"

$nulls = '{"script":{"lang":"painless","source":"long b = ctx._source.bytes; if (b % 5 != 0) { ctx._source.priority = (int)(b % 4) + 1; } else { ctx._source.remove(''priority''); } if (b % 7 != 0) { ctx._source.secure = (b % 3 != 0); } else { ctx._source.remove(''secure''); }"}}'
$r1 = es POST '/any_demo/_update_by_query?refresh=true&conflicts=proceed' $nulls
if ($r1 -like 'HTTP *') { $r1; exit 1 }
$j1 = $r1 | ConvertFrom-Json
"priority/secure updated: $($j1.updated) failures: $($j1.failures.Count)"

$compare = @'
long b = ctx._source.bytes;
if (b % 13 == 0) { ctx._source.remove("latency_ms"); } else {
  List l = new ArrayList();
  for (int i = 0; i <= (int)(b % 3); i++) { l.add((int)(10 + (b * (i + 3) + i * 211) % 990)); }
  ctx._source.latency_ms = l.size() == 1 ? l.get(0) : l;
}
if (b % 11 == 0) { ctx._source.remove("client_ip"); } else {
  List ips = new ArrayList();
  int n = b % 4 == 0 ? 2 : 1;
  for (int i = 0; i < n; i++) {
    long h = b * 31 + i * 17;
    int c = (int)(h % 6);
    long x = (h / 7) % 256;
    long y = (h / 13) % 254 + 1;
    if (c == 0) { ips.add("192.168." + x + "." + y); }
    else if (c == 1) { ips.add("10." + x + "." + ((h / 3) % 256) + "." + y); }
    else if (c == 2) { ips.add("172." + (16 + h % 16) + "." + x + "." + y); }
    else if (c == 3) { ips.add("203.0.113." + y); }
    else if (c == 4) { ips.add("fd00::" + Long.toHexString(h % 65536)); }
    else { ips.add("2001:db8::" + Long.toHexString(h % 65536)); }
  }
  ctx._source.client_ip = ips.size() == 1 ? ips.get(0) : ips;
}
'@
$compareBody = @{ script = @{ lang = 'painless'; source = $compare } } | ConvertTo-Json -Depth 5 -Compress
$r2 = es POST '/any_demo/_update_by_query?refresh=true&conflicts=proceed' $compareBody
if ($r2 -like 'HTTP *') { $r2; exit 1 }
$j2 = $r2 | ConvertFrom-Json
"latency/ip updated: $($j2.updated) failures: $($j2.failures.Count)"

esql 'FROM any_demo | STATS docs = COUNT(*), no_os = COUNT(*) WHERE os IS NULL, no_region = COUNT(*) WHERE region IS NULL, no_tags = COUNT(*) WHERE tags IS NULL, no_priority = COUNT(*) WHERE priority IS NULL, no_secure = COUNT(*) WHERE secure IS NULL, no_latency = COUNT(*) WHERE latency_ms IS NULL, no_ip = COUNT(*) WHERE client_ip IS NULL'
