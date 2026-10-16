# Adds two multivalue fields to any_demo, for the "greater than" and CIDR_MATCH demos:
#   latency_ms (integer, 1-3 values, ~8% missing) and client_ip (ip, 1-2 values incl. IPv6, ~9% missing).
# Values are derived deterministically from bytes, so existing counts don't change.
$es = 'http://localhost:9200'
function req([string]$method, [string]$path, [string]$body = $null) {
  [byte[]]$bytes = $null
  if ($body) { $bytes = [Text.Encoding]::UTF8.GetBytes($body) }
  try { (Invoke-WebRequest -Method $method -Uri "$es$path" -ContentType 'application/json' -Body $bytes -UseBasicParsing).Content }
  catch { "HTTP error: " + $(if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }) }
}
req PUT '/any_demo/_mapping' '{"properties":{"latency_ms":{"type":"integer"},"client_ip":{"type":"ip"}}}'
$source = @'
long b = ctx._source.bytes;
if (b % 13 == 0) { ctx._source.remove('latency_ms'); } else {
  List l = new ArrayList();
  for (int i = 0; i <= (int)(b % 3); i++) { l.add((int)(10 + (b * (i + 3) + i * 211) % 990)); }
  ctx._source.latency_ms = l.size() == 1 ? l.get(0) : l;
}
if (b % 11 == 0) { ctx._source.remove('client_ip'); } else {
  List ips = new ArrayList();
  int n = b % 4 == 0 ? 2 : 1;
  for (int i = 0; i < n; i++) {
    long h = b * 31 + i * 17;
    int c = (int)(h % 6);
    long x = (h / 7) % 256;
    long y = (h / 13) % 254 + 1;
    if (c == 0) { ips.add('192.168.' + x + '.' + y); }
    else if (c == 1) { ips.add('10.' + x + '.' + ((h / 3) % 256) + '.' + y); }
    else if (c == 2) { ips.add('172.' + (16 + h % 16) + '.' + x + '.' + y); }
    else if (c == 3) { ips.add('203.0.113.' + y); }
    else if (c == 4) { ips.add('fd00::' + Long.toHexString(h % 65536)); }
    else { ips.add('2001:db8::' + Long.toHexString(h % 65536)); }
  }
  ctx._source.client_ip = ips.size() == 1 ? ips.get(0) : ips;
}
'@
$body = @{ script = @{ lang = 'painless'; source = $source } } | ConvertTo-Json -Depth 5
$r = req POST '/any_demo/_update_by_query?refresh=true&conflicts=proceed' $body
if ($r -like 'HTTP error*') { $r } else { $j = $r | ConvertFrom-Json; "updated: $($j.updated) failures: $($j.failures.Count)" }
req POST '/_query?format=txt' '{"query":"FROM any_demo | STATS docs = COUNT(*), no_latency = COUNT(*) WHERE latency_ms IS NULL, multi_latency = COUNT(*) WHERE MV_COUNT(latency_ms) > 1, no_ip = COUNT(*) WHERE client_ip IS NULL, multi_ip = COUNT(*) WHERE MV_COUNT(client_ip) > 1"}'
