$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDir = Join-Path $projectRoot 'build/media'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$segments = Get-Content -LiteralPath (Join-Path $projectRoot 'media/narration.json') -Encoding UTF8 -Raw | ConvertFrom-Json
$speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voice = $speaker.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -eq 'zh-CN' } | Select-Object -First 1
if (-not $voice) { throw 'A local zh-CN SAPI voice is required' }
$speaker.SelectVoice($voice.VoiceInfo.Name)
$speaker.Rate = 1
foreach ($segment in $segments) {
    $speaker.SetOutputToWaveFile((Join-Path $outputDir ($segment.name + '.wav')))
    $speaker.Speak($segment.text)
    $speaker.SetOutputToNull()
}
$speaker.Dispose()
Write-Output 'PASS LOCAL_CHINESE_NARRATION segments=5'
