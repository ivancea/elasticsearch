# Probes whether the Dashboards API accepts an esql_control panel inside a section.
$body = @'
{
  "title": "probe: control inside section",
  "panels": [
    {
      "title": "Section A",
      "collapsed": false,
      "grid": { "y": 0 },
      "panels": [
        {
          "grid": { "x": 0, "y": 0, "w": 12, "h": 2 },
          "type": "esql_control",
          "config": {
            "title": "Probe OS", "control_type": "VALUES_FROM_QUERY", "esql_query": "FROM any_demo | STATS BY os",
            "variable_name": "probe_os", "variable_type": "values", "single_select": true, "selected_options": []
          }
        }
      ]
    }
  ]
}
'@
$headers = @{ 'kbn-xsrf' = 'true'; 'elastic-api-version' = '2023-10-31' }
try {
  $r = Invoke-WebRequest -Method POST -Uri 'http://localhost:5601/api/dashboards' -Headers $headers -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing
  $j = $r.Content | ConvertFrom-Json
  "Created: $($j.id)"
  ($j | ConvertTo-Json -Depth 12)
} catch { "HTTP error: " + $(if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }) }
