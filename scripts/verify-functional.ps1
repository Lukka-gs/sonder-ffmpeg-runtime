<#
Verificacao funcional COMPARTILHADA do candidato ffmpeg.exe/ffprobe.exe.
Chamada de forma IDENTICA por verify.yml e release.yml -- nao duplicar esta
logica em nenhum workflow; qualquer mudanca de comportamento entra aqui, uma
vez so.

Gate OBRIGATORIO (qualquer falha aqui termina o processo com exit 1, nunca
um aviso seguido de exit 0):
  1. SHA-256 dos binarios e dos link maps (via scripts/verify-artifacts.mjs)
  2. `-buildconf` E os dois link maps sem nenhum componente proibido -- a
     lista de flags/componentes proibidos vem EXCLUSIVAMENTE de
     docs/BUILD_MANIFEST.json (forbiddenCheck.forbiddenConfigureFlags /
     forbiddenComponents), via scripts/verify-forbidden-components.mjs.
     Nenhuma segunda lista manual existe neste script.
  3. `-encoders` contem h264_mf e aac
  4. `ffprobe -version` funciona
  5. baseline obrigatorio: entrada Y4M+WAV gerada programaticamente por
     scripts/generate-baseline-fixture.mjs (sem depender de nenhum ffmpeg de
     sistema no runner), convertida pelo ffmpeg.exe CANDIDATO para MP4
     H.264 (h264_mf, software, --hw_encoding 0) + AAC, e validada pelo
     ffprobe.exe CANDIDATO.

Cobertura OPCIONAL (nunca falha o job -- so informa; NAO e um gate e nunca
deve ser tratada como equivalente ao baseline obrigatorio acima):
  6. matriz estendida de codecs/containers, gerada com um ffmpeg de sistema
     do runner SE presente, e decodificada pelo ffprobe.exe candidato.

Uso:
  pwsh -File scripts/verify-functional.ps1 -ArtifactsDir <dir> [-SkipOptionalMatrix]

<dir> deve conter: ffmpeg.exe, ffprobe.exe, SHA256SUMS.txt, ffmpeg-link.map,
ffprobe-link.map.
#>
param(
  [Parameter(Mandatory = $true)][string]$ArtifactsDir,
  [switch]$SkipOptionalMatrix
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Fail([string]$Message) {
  Write-Error "FAIL: $Message"
  exit 1
}

$FfmpegExe = Join-Path $ArtifactsDir 'ffmpeg.exe'
$FfprobeExe = Join-Path $ArtifactsDir 'ffprobe.exe'
$Sha256Sums = Join-Path $ArtifactsDir 'SHA256SUMS.txt'
$FfmpegLinkMap = Join-Path $ArtifactsDir 'ffmpeg-link.map'
$FfprobeLinkMap = Join-Path $ArtifactsDir 'ffprobe-link.map'

foreach ($required in @($FfmpegExe, $FfprobeExe, $Sha256Sums, $FfmpegLinkMap, $FfprobeLinkMap)) {
  if (-not (Test-Path $required)) { Fail "arquivo obrigatorio ausente: $required" }
}

Write-Output "== 1/5: SHA-256 dos binarios e dos link maps =="
node (Join-Path $ScriptDir 'verify-artifacts.mjs') `
  --ffmpeg $FfmpegExe --ffprobe $FfprobeExe --sha256sums $Sha256Sums `
  --ffmpeg-link-map $FfmpegLinkMap --ffprobe-link-map $FfprobeLinkMap
if ($LASTEXITCODE -ne 0) { Fail "verify-artifacts.mjs reportou falha (exit $LASTEXITCODE)" }

Write-Output "== 2/5: -buildconf + link maps sem componentes proibidos (fonte: docs/BUILD_MANIFEST.json) =="
$ManifestPath = Join-Path (Join-Path $ScriptDir '..') 'docs/BUILD_MANIFEST.json'
$BuildconfFile = Join-Path ([System.IO.Path]::GetTempPath()) ("sonder-ffmpeg-buildconf-" + [System.Guid]::NewGuid().ToString("N") + ".txt")
try {
  & $FfmpegExe -hide_banner -buildconf 2>&1 | Out-File -FilePath $BuildconfFile -Encoding utf8
  node (Join-Path $ScriptDir 'verify-forbidden-components.mjs') `
    --manifest $ManifestPath `
    --buildconf-file $BuildconfFile `
    --ffmpeg-link-map $FfmpegLinkMap `
    --ffprobe-link-map $FfprobeLinkMap
  if ($LASTEXITCODE -ne 0) { Fail "verify-forbidden-components.mjs reportou falha (exit $LASTEXITCODE)" }
} finally {
  Remove-Item -Force $BuildconfFile -ErrorAction SilentlyContinue
}

Write-Output "== 3/5: -encoders contem h264_mf e aac =="
$encoders = & $FfmpegExe -hide_banner -encoders 2>&1 | Out-String
if ($encoders -notmatch "h264_mf") { Fail "h264_mf ausente de -encoders" }
if ($encoders -notmatch "(?m)^\s*A[\.\w]*\s+aac\s") { Fail "aac ausente de -encoders" }
Write-Output "h264_mf e aac confirmados em -encoders"

Write-Output "== 4/5: ffprobe -version =="
& $FfprobeExe -version | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "ffprobe -version falhou (exit $LASTEXITCODE)" }

Write-Output "== 5/5: baseline OBRIGATORIO (Y4M+WAV gerado programaticamente -> MP4 h264_mf/aac) =="
$Workdir = Join-Path ([System.IO.Path]::GetTempPath()) ("sonder-ffmpeg-baseline-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $Workdir | Out-Null
try {
  node (Join-Path $ScriptDir 'generate-baseline-fixture.mjs') --out-dir $Workdir
  if ($LASTEXITCODE -ne 0) {
    Fail "geracao do baseline (Y4M+WAV) falhou (exit $LASTEXITCODE) -- gate obrigatorio, sem fallback nem skip"
  }

  $y4m = Join-Path $Workdir 'baseline.y4m'
  $wav = Join-Path $Workdir 'baseline.wav'
  foreach ($f in @($y4m, $wav)) {
    if (-not (Test-Path $f)) { Fail "baseline nao gerado: $f ausente" }
    if ((Get-Item $f).Length -eq 0) { Fail "baseline gerado vazio: $f" }
  }

  $outMp4 = Join-Path $Workdir 'baseline_out.mp4'
  & $FfmpegExe -y -hide_banner -loglevel error `
    -i $y4m -i $wav `
    -map 0:v:0 -map 1:a:0 `
    -c:v h264_mf -pix_fmt nv12 -hw_encoding 0 `
    -movflags +faststart -f mp4 `
    -c:a aac -ac 2 -b:a 128k `
    $outMp4
  if ($LASTEXITCODE -ne 0) {
    Fail "conversao obrigatoria do baseline para MP4 h264_mf/aac falhou (exit $LASTEXITCODE)"
  }
  if (-not (Test-Path $outMp4) -or (Get-Item $outMp4).Length -eq 0) {
    Fail "conversao obrigatoria do baseline nao produziu um arquivo de saida valido"
  }

  $probe = & $FfprobeExe -v error -show_entries stream=codec_name -of default=noprint_wrappers=1 $outMp4 | Out-String
  if ($LASTEXITCODE -ne 0) { Fail "ffprobe falhou ao ler a saida do baseline (exit $LASTEXITCODE)" }
  if ($probe -notmatch "codec_name=h264") { Fail "saida do baseline nao contem stream h264: $probe" }
  if ($probe -notmatch "codec_name=aac") { Fail "saida do baseline nao contem stream aac: $probe" }

  Write-Output "baseline obrigatorio APROVADO: Y4M+WAV programatico -> MP4 h264_mf(software)/aac, validado por ffprobe"
} finally {
  Remove-Item -Recurse -Force $Workdir -ErrorAction SilentlyContinue
}

if ($SkipOptionalMatrix) {
  Write-Output "== cobertura opcional pulada (-SkipOptionalMatrix) =="
} else {
  Write-Output "== cobertura OPCIONAL (NAO e um gate -- falhas aqui nunca terminam o job com erro) =="
  Write-Output "Tenta autorar fixtures adicionais com o ffmpeg DE SISTEMA do runner (se presente) para"
  Write-Output "exercitar mais codecs/containers alem do baseline obrigatorio acima. Isto NAO substitui"
  Write-Output "nem amplia o gate obrigatorio -- e so cobertura extra, best-effort, dependente do runner."
  $sysFfmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
  if (-not $sysFfmpeg) {
    Write-Output "OPCIONAL: ffmpeg de sistema nao encontrado no runner -- cobertura opcional pulada (isto NAO falha o gate obrigatorio, que ja foi aprovado acima)"
  } else {
    $OptWorkdir = Join-Path ([System.IO.Path]::GetTempPath()) ("sonder-ffmpeg-optional-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $OptWorkdir | Out-Null
    try {
      $cases = @(
        @{ Name = "hevc_mov";  Args = "-f lavfi -i testsrc2=size=320x240:duration=1:rate=30 -c:v libx265 -pix_fmt yuv420p -f mov hevc.mov" }
        @{ Name = "mpeg4_m4v"; Args = "-f lavfi -i testsrc2=size=320x240:duration=1:rate=30 -c:v mpeg4 -pix_fmt yuv420p -f mp4 mpeg4.m4v" }
        @{ Name = "vp8_webm";  Args = "-f lavfi -i testsrc2=size=320x240:duration=1:rate=30 -c:v libvpx -pix_fmt yuv420p -f webm vp8.webm" }
        @{ Name = "vp9_webm";  Args = "-f lavfi -i testsrc2=size=320x240:duration=1:rate=30 -c:v libvpx-vp9 -pix_fmt yuv420p -f webm vp9.webm" }
        @{ Name = "av1_mkv";   Args = "-f lavfi -i testsrc2=size=320x240:duration=1:rate=30 -c:v libaom-av1 -cpu-used 8 -pix_fmt yuv420p -f matroska av1.mkv" }
        @{ Name = "prores_mov"; Args = "-f lavfi -i testsrc2=size=320x240:duration=1:rate=30 -c:v prores_ks -profile:v 0 -pix_fmt yuv422p10le -f mov prores.mov" }
        @{ Name = "dnxhd_mov"; Args = "-f lavfi -i testsrc2=size=1920x1080:duration=1:rate=25 -c:v dnxhd -b:v 36M -pix_fmt yuv422p -f mov dnxhd.mov" }
      )
      Push-Location $OptWorkdir
      $generated = @()
      foreach ($c in $cases) {
        & ffmpeg -y -hide_banner -loglevel error $($c.Args -split ' ')
        if ($LASTEXITCODE -eq 0) { $generated += $c.Name }
        else { Write-Output "OPCIONAL: fixture '$($c.Name)' nao gerada (encoder provavelmente ausente no ffmpeg de sistema deste runner) -- ignorado, nao e um gate" }
      }
      $failed = @()
      foreach ($f in (Get-ChildItem -File -ErrorAction SilentlyContinue)) {
        & $FfprobeExe -v error -show_entries stream=codec_name -of default=noprint_wrappers=1 $f.FullName | Out-Null
        if ($LASTEXITCODE -ne 0) { $failed += $f.Name }
      }
      Pop-Location
      Write-Output "OPCIONAL: $($generated.Count) de $($cases.Count) fixtures extras geradas e decodificadas pelo ffprobe candidato ($($failed.Count) falharam ao decodificar) -- cobertura informativa, nao gate"
    } finally {
      Remove-Item -Recurse -Force $OptWorkdir -ErrorAction SilentlyContinue
    }
  }
}

Write-Output ""
Write-Output "verify-functional: OK (gate obrigatorio aprovado)"
exit 0
