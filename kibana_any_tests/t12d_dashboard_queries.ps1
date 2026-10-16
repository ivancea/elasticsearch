# Runs the saved queries of the scenarios dashboard's sections 6 and 7 against ES, with the params Kibana would send.
$kb = 'http://localhost:5601'; $es = 'http://localhost:9200'
$d = (Invoke-WebRequest "$kb/api/dashboards/ab0a31b0-e2f1-4140-b942-60bc7c9be5e6" -Headers @{ 'elastic-api-version' = '2023-10-31' } -UseBasicParsing).Content | ConvertFrom-Json
$root = if ($d.data) { $d.data } else { $d }
$cases = @(
  @{ name = 'Any'; params = @(@{ gt_bytes = $null }, @{ gt_latency = $null }, @{ net_cidr = $null }) },
  @{ name = 'bytes>5000, latency>500, [192.168/16, 10/8]'; params = @(@{ gt_bytes = 5000 }, @{ gt_latency = 500 }, @{ net_cidr = @('192.168.0.0/16', '10.0.0.0/8') }) }
)
foreach ($s in $root.panels | Where-Object { $_.title -match '^(6|7)\.' }) {
  "=== $($s.title)"
  foreach ($p in $s.panels | Where-Object { $_.type -eq 'vis' }) {
    $q = $p.config.data_source.query
    foreach ($c in $cases) {
      $used = $c.params | Where-Object { $q -match "\?$(@($_.Keys)[0])\b" }
      $body = @{ query = $q; params = @($used) } | ConvertTo-Json -Depth 10 -Compress
      $out = try {
        $j = (Invoke-WebRequest -Method POST -Uri "$es/_query" -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing).Content | ConvertFrom-Json
        (($j.values | Select-Object -First 6 | ForEach-Object { $_ -join ':' }) -join '; ') + $(if ($j.is_partial) { '  [PARTIAL]' } else { '' })
      } catch { 'ERROR: ' + ($_.ErrorDetails.Message | ConvertFrom-Json).error.reason }
      "  {0,-40} {1,-44} {2}" -f $p.config.title, $c.name, $out
    }
  }
}
