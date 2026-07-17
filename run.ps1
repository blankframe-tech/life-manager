# Launch the app with Supabase creds loaded from .env (see .env.example).
# Any extra args are passed through to `flutter run` (e.g. -d <device>).
# Usage:  ./run.ps1        or    ./run.ps1 -d chrome
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$url = ''
$key = ''
if (Test-Path .env) {
  foreach ($line in Get-Content .env) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $parts = $line -split '=', 2
    $name = $parts[0].Trim()
    $value = $parts[1].Trim()
    if ($name -eq 'SUPABASE_URL') { $url = $value }
    elseif ($name -eq 'SUPABASE_ANON_KEY') { $key = $value }
  }
}

flutter run --dart-define=SUPABASE_URL=$url --dart-define=SUPABASE_ANON_KEY=$key @args
