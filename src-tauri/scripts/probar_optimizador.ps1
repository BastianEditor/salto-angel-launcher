<#
  Pruebas automáticas de optimizar.ps1 (corren aquí y en GitHub antes de cada compilación).
  Arman una PC de mentira en una carpeta temporal con espacios, tildes y ñ, y usan una clave de registro de prueba.
  No tocan la PC de verdad: ni Documentos, ni el registro real, ni el plan de energía.
  Uso:  powershell -NoProfile -ExecutionPolicy Bypass -File probar_optimizador.ps1
  Sale con código 0 si todo pasa y 1 si algo falla.
#>
$ErrorActionPreference = 'Stop'
$SCRIPT = Join-Path $PSScriptRoot 'optimizar.ps1'
$BASE = Join-Path ([IO.Path]::GetTempPath()) ('Prueba Salto Ángel Ñandú ' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$REGB = 'HKCU:\Software\SaltoAngelPrueba_' + [guid]::NewGuid().ToString('N').Substring(0, 6)
$SETTINGS = Join-Path $BASE 'Documents\Rockstar Games\GTA V\settings.xml'
$DATA = Join-Path $BASE 'Local\FiveM\FiveM.app\data'
$PROPIA = Join-Path $BASE 'Roaming\SaltoAngelLauncher\optimizador'
$script:pasan = 0; $script:fallan = 0

$XML_ORIGINAL = @'
<?xml version="1.0" encoding="UTF-8"?>
<Settings>
  <version value="27" />
  <configSource>SMC_USER</configSource>
  <graphics>
    <Tessellation value="3" />
    <LodScale value="1.000000" />
    <PedLodBias value="0.200000" />
    <VehicleLodBias value="0.000000" />
    <ShadowQuality value="3" />
    <ReflectionQuality value="3" />
    <ReflectionMSAA value="8" />
    <SSAO value="2" />
    <AnisotropicFiltering value="4" />
    <MSAA value="4" />
    <MSAAFragments value="0" />
    <MSAAQuality value="0" />
    <SamplingMode value="0" />
    <TextureQuality value="2" />
    <ParticleQuality value="3" />
    <WaterQuality value="2" />
    <GrassQuality value="3" />
    <ShaderQuality value="2" />
    <Shadow_SoftShadows value="4" />
    <UltraShadows_Enabled value="false" />
    <Shadow_ParticleShadows value="true" />
    <Shadow_Distance value="1.000000" />
    <Shadow_LongShadows value="false" />
    <FXAA_Enabled value="true" />
    <TXAA_Enabled value="false" />
    <Lighting_FogVolumes value="true" />
    <Shader_SSA value="true" />
    <DX_Version value="2" />
    <CityDensity value="1.000000" />
    <PedVarietyMultiplier value="1.000000" />
    <VehicleVarietyMultiplier value="1.000000" />
    <PostFX value="3" />
    <DoF value="true" />
    <HdStreamingInFlight value="false" />
    <MaxLodScale value="0.500000" />
    <MotionBlurStrength value="0.500000" />
  </graphics>
  <video>
    <ScreenWidth value="1920" />
    <ScreenHeight value="1080" />
    <Windowed value="2" />
    <VSync value="1" />
  </video>
</Settings>
'@

function Correr {
    param([string[]]$a)
    $salida = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $SCRIPT @a -Raiz $BASE -RegBase $REGB -SinEnergia 2>&1 | Out-String
    $lineas = @($salida -split "`r?`n" | Where-Object { $_.Trim() })
    if ($lineas.Count -ne 1) { throw "No respondió UNA línea JSON: $salida" }
    return ($lineas[0] | ConvertFrom-Json)
}
function Probar([string]$nombre, [scriptblock]$prueba) {
    try {
        $r = & $prueba
        if ($r -eq $false) { throw 'la condición dio falso' }
        Write-Host "PASA  $nombre"; $script:pasan++
    } catch {
        Write-Host "FALLA $nombre -> $($_.Exception.Message)"; $script:fallan++
    }
}
function Valor([string]$nodo) { [regex]::Match([IO.File]::ReadAllText($SETTINGS), '<' + $nodo + '\s+value="([^"]*)"').Groups[1].Value }
function Hash([string]$ruta) { (Get-FileHash -LiteralPath $ruta -Algorithm SHA256).Hash }
function RegVal([string]$sub, [string]$n) { try { (Get-ItemProperty -LiteralPath "$REGB\$sub" -Name $n -ErrorAction Stop).$n } catch { $null } }
function PonerSettings([string]$texto) {
    if (Test-Path -LiteralPath $SETTINGS) { (Get-Item -LiteralPath $SETTINGS).IsReadOnly = $false }
    [IO.File]::WriteAllText($SETTINGS, $texto, (New-Object System.Text.UTF8Encoding($false)))
}
function Reiniciar {
    if (Test-Path -LiteralPath $PROPIA) { Remove-Item -LiteralPath $PROPIA -Recurse -Force }
    PonerSettings $XML_ORIGINAL
    (Get-Item -LiteralPath $SETTINGS).IsReadOnly = $true
}

# ===== Armar la PC de mentira =====
New-Item -ItemType Directory -Force -Path (Split-Path $SETTINGS) | Out-Null
foreach ($d in 'cache\game', 'cache\subprocess', 'cache\browser', 'server-cache', 'server-cache-priv') { New-Item -ItemType Directory -Force -Path (Join-Path $DATA $d) | Out-Null }
[IO.File]::WriteAllBytes((Join-Path $BASE 'Local\FiveM\FiveM.exe'), [byte[]](1, 2, 3))
[IO.File]::WriteAllBytes((Join-Path $DATA 'cache\game\gta.rpf'), (New-Object byte[] (3MB)))
[IO.File]::WriteAllBytes((Join-Path $DATA 'cache\browser\c.bin'), (New-Object byte[] (2MB)))
[IO.File]::WriteAllBytes((Join-Path $DATA 'server-cache\a.bin'), (New-Object byte[] (5MB)))
[IO.File]::WriteAllBytes((Join-Path $DATA 'server-cache-priv\b.bin'), (New-Object byte[] (1MB)))
New-Item -ItemType Directory -Force -Path (Join-Path $BASE 'Roaming') | Out-Null
New-Item -Path "$REGB\Software\Microsoft\GameBar" -Force | Out-Null
New-ItemProperty -LiteralPath "$REGB\Software\Microsoft\GameBar" -Name AutoGameModeEnabled -Value 0 -PropertyType DWord -Force | Out-Null
Reiniciar
$HASH_ORIGINAL = Hash $SETTINGS
Write-Host "PC de prueba: $BASE"

try {
    # ----- Revisar -----
    Probar 'revisar responde y ve FiveM y settings.xml' { $r = Correr @('-Accion', 'revisar', '-SinProcesos'); $r.ok -and $r.fivem.instalado -and $r.settings.existe -and -not $r.optimizado -and $r.fivem.cacheMB -ge 7 }

    # ----- Modo extremo y vuelta -----
    $r = $null
    Probar 'aplicar extremo + Windows responde ok' { $script:r = Correr @('-Accion', 'aplicar', '-Perfil', 'extremo', '-Windows', '-SinProcesos'); $script:r.ok -and $script:r.graficos.cambiados -ge 30 }
    Probar 'extremo baja texturas, sombras, distancia y vsync' { (Valor 'TextureQuality') -eq '0' -and (Valor 'ShadowQuality') -eq '1' -and (Valor 'LodScale') -eq '0.000000' -and (Valor 'VSync') -eq '0' -and (Valor 'FXAA_Enabled') -eq 'false' }
    Probar 'extremo NO toca la escala de resolución ni la pantalla' { (Valor 'SamplingMode') -eq '0' -and (Valor 'ScreenWidth') -eq '1920' -and (Valor 'Windowed') -eq '2' -and (Valor 'DX_Version') -eq '2' }
    Probar 'el settings.xml nuevo es XML válido' { [bool]([xml][IO.File]::ReadAllText($SETTINGS)) }
    Probar 'respeta que settings.xml era de solo lectura' { (Get-Item -LiteralPath $SETTINGS).IsReadOnly }
    Probar 'no deja archivos temporales' { -not (Get-ChildItem -LiteralPath (Split-Path $SETTINGS) -Filter '*.tmp_sa') }
    Probar 'el respaldo es idéntico al original' { $e = [IO.File]::ReadAllText((Join-Path $PROPIA 'estado.json')) | ConvertFrom-Json; (Hash $e.settingsRespaldo) -eq $HASH_ORIGINAL }
    Probar 'apaga Game Bar y prende Modo juego' { (RegVal 'System\GameConfigStore' 'GameDVR_Enabled') -eq 0 -and (RegVal 'Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled') -eq 0 -and (RegVal 'Software\Microsoft\GameBar' 'AutoGameModeEnabled') -eq 1 }
    Probar 'aplicar medio después sube texturas a 1' { $x = Correr @('-Accion', 'aplicar', '-Perfil', 'medio', '-SinProcesos'); $x.ok -and (Valor 'TextureQuality') -eq '1' }
    Probar 'aplicar dos veces no duplica lo anotado del registro' {
        $antes = @(([IO.File]::ReadAllText((Join-Path $PROPIA 'estado.json')) | ConvertFrom-Json).registro).Count
        Correr @('-Accion', 'aplicar', '-Perfil', 'extremo', '-Windows', '-SinProcesos') | Out-Null
        $despues = @(([IO.File]::ReadAllText((Join-Path $PROPIA 'estado.json')) | ConvertFrom-Json).registro).Count
        $antes -eq $despues -and $antes -ge 4
    }
    Probar 'revisar ve el modo extremo activo' { $x = Correr @('-Accion', 'revisar', '-SinProcesos'); $x.optimizado -and $x.extremo -and $x.perfil -eq 'extremo' }
    Probar 'restaurar responde ok' { (Correr @('-Accion', 'restaurar', '-SinProcesos')).ok }
    Probar 'settings.xml queda IDÉNTICO al original' { (Hash $SETTINGS) -eq $HASH_ORIGINAL }
    Probar 'sigue de solo lectura después de restaurar' { (Get-Item -LiteralPath $SETTINGS).IsReadOnly }
    Probar 'el registro vuelve: lo que existía con su valor, lo nuevo se borra' { (RegVal 'Software\Microsoft\GameBar' 'AutoGameModeEnabled') -eq 0 -and $null -eq (RegVal 'Software\Microsoft\GameBar' 'AllowAutoGameMode') -and $null -eq (RegVal 'System\GameConfigStore' 'GameDVR_Enabled') }
    Probar 'después de restaurar no queda estado' { -not (Test-Path -LiteralPath (Join-Path $PROPIA 'estado.json')) }
    Probar 'restaurar sin nada que devolver no falla' { $x = Correr @('-Accion', 'restaurar', '-SinProcesos'); $x.ok -and $x.nada }

    # ----- Casos de error -----
    Reiniciar
    Probar 'settings.xml dañado: avisa y NO lo toca' { PonerSettings '<Settings><graphics><TextureQuality value="2" /></graphics'; $h = Hash $SETTINGS; $x = Correr @('-Accion', 'aplicar', '-Perfil', 'extremo', '-SinProcesos'); -not $x.ok -and (Hash $SETTINGS) -eq $h -and $x.error -match 'dañado' }
    Probar 'settings.xml sin la parte de gráficos: avisa y NO lo toca' { PonerSettings '<?xml version="1.0"?><Settings><video><VSync value="1" /></video></Settings>'; $h = Hash $SETTINGS; $x = Correr @('-Accion', 'aplicar', '-Perfil', 'bajo', '-SinProcesos'); -not $x.ok -and (Hash $SETTINGS) -eq $h }
    Probar 'settings.xml vacío: avisa y NO lo toca' { PonerSettings ''; $x = Correr @('-Accion', 'aplicar', '-Perfil', 'bajo', '-SinProcesos'); -not $x.ok -and (Get-Item -LiteralPath $SETTINGS).Length -eq 0 }
    Reiniciar
    Probar 'sin settings.xml: los gráficos avisan y no se crea nada' { (Get-Item -LiteralPath $SETTINGS).IsReadOnly = $false; Remove-Item -LiteralPath $SETTINGS; $x = Correr @('-Accion', 'aplicar', '-Perfil', 'extremo', '-SinProcesos'); -not $x.ok -and -not (Test-Path -LiteralPath $SETTINGS) }
    Probar 'sin settings.xml: el modo extremo igual aplica lo de Windows' { $x = Correr @('-Accion', 'aplicar', '-Perfil', 'extremo', '-Windows', '-SinProcesos'); $x.ok -and -not $x.graficos.aplicado -and @($x.windows).Count -ge 2 }
    Probar '... y se puede devolver' { (Correr @('-Accion', 'restaurar', '-SinProcesos')).ok -and $null -eq (RegVal 'System\GameConfigStore' 'GameDVR_Enabled') }
    Reiniciar
    Probar 'estado.json dañado: lo aparta y sigue funcionando' {
        New-Item -ItemType Directory -Force -Path $PROPIA | Out-Null
        [IO.File]::WriteAllText((Join-Path $PROPIA 'estado.json'), '{ esto no es json')
        $x = Correr @('-Accion', 'revisar', '-SinProcesos')
        $x.ok -and -not $x.optimizado -and @(Get-ChildItem -LiteralPath $PROPIA -Filter 'estado_danado_*.json').Count -eq 1
    }
    Reiniciar
    Probar 'si borraron el respaldo, restaurar devuelve el resto y avisa' {
        Correr @('-Accion', 'aplicar', '-Perfil', 'extremo', '-Windows', '-SinProcesos') | Out-Null
        $e = [IO.File]::ReadAllText((Join-Path $PROPIA 'estado.json')) | ConvertFrom-Json
        Remove-Item -LiteralPath $e.settingsRespaldo -Force
        $x = Correr @('-Accion', 'restaurar', '-SinProcesos')
        $x.ok -and (@($x.avisos) -contains 'respaldo_perdido') -and $null -eq (RegVal 'System\GameConfigStore' 'GameDVR_Enabled')
    }

    # ----- Juego abierto (un ping.exe copiado con el nombre FiveM.exe) -----
    Reiniciar
    $falso = Join-Path $BASE 'FiveM.exe'
    Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\PING.EXE') -Destination $falso
    $proc = Start-Process -FilePath $falso -ArgumentList '-n', '60', '127.0.0.1' -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 800
    try {
        Probar 'con FiveM abierto NO cambia gráficos' { $h = Hash $SETTINGS; $x = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SCRIPT -Accion aplicar -Perfil extremo -Raiz $BASE -RegBase $REGB -SinEnergia | ConvertFrom-Json; -not $x.ok -and (Hash $SETTINGS) -eq $h -and $x.error -match 'Cierra' }
        Probar 'con FiveM abierto NO limpia la caché' { $x = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SCRIPT -Accion limpiar -Raiz $BASE -RegBase $REGB -SinEnergia | ConvertFrom-Json; -not $x.ok -and (Test-Path -LiteralPath (Join-Path $DATA 'server-cache\a.bin')) }
        Probar 'revisar avisa que el juego está abierto' { $x = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SCRIPT -Accion revisar -Raiz $BASE -RegBase $REGB -SinEnergia | ConvertFrom-Json; $x.fivem.abierto }
    } finally { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }

    # ----- Caché y cerrar -----
    Probar 'limpiar borra la caché y respeta cache\game' {
        $x = Correr @('-Accion', 'limpiar', '-SinProcesos')
        $x.ok -and $x.liberadoMB -ge 7 -and (Test-Path -LiteralPath (Join-Path $DATA 'cache\game\gta.rpf')) -and -not (Test-Path -LiteralPath (Join-Path $DATA 'server-cache')) -and -not (Test-Path -LiteralPath (Join-Path $DATA 'cache\browser'))
    }
    Probar 'limpiar dos veces no falla' { $x = Correr @('-Accion', 'limpiar', '-SinProcesos'); $x.ok -and $x.liberadoMB -eq 0 }
    Probar 'cerrar ignora programas que no están en la lista' { $x = Correr @('-Accion', 'cerrar', '-Nombres', 'explorer,FXServer,svchost,steam', '-SinProcesos'); $x.ok -and @($x.cerrados).Count -eq 0 }
    Probar 'deja un registro de lo que hizo' { (Test-Path -LiteralPath (Join-Path $PROPIA 'registro.log')) }
} finally {
    Remove-Item -Path $REGB -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $SETTINGS) { (Get-Item -LiteralPath $SETTINGS).IsReadOnly = $false }
    Remove-Item -LiteralPath $BASE -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "Resultado: $($script:pasan) pasan, $($script:fallan) fallan"
if ($script:fallan -gt 0) { exit 1 } else { exit 0 }
