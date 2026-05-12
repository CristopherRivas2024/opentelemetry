$now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 1000000
$start = $now - 1000000000

$body = @{
  resourceSpans = @(@{
    resource = @{
      attributes = @(@{ key = 'service.name'; value = @{ stringValue = 'test-from-laptop' } })
    }
    scopeSpans = @(@{
      scope = @{ name = 'manual-test' }
      spans = @(@{
        traceId = 'aabbccddeeff00112233445566778899'
        spanId  = 'aabbccddeeff0011'
        name    = 'smoke-test-span'
        kind    = 1
        startTimeUnixNano = "$start"
        endTimeUnixNano   = "$now"
        status  = @{ code = 1 }
      })
    })
  })
} | ConvertTo-Json -Depth 10

try {
  $resp = Invoke-WebRequest -Uri 'http://192.168.39.218:4318/v1/traces' `
    -Method Post -ContentType 'application/json' -Body $body -UseBasicParsing
  Write-Host "HTTP $($resp.StatusCode) - $($resp.StatusDescription)"
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  if ($_.Exception.Response) {
    Write-Host "Status: $($_.Exception.Response.StatusCode)"
  }
}
