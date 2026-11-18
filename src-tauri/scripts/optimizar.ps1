<#
  Salto Ángel Launcher - optimizador (docs/disenos/LAUNCHER.md §3 y §3.1).
  Lo llama src-tauri/src/lib.rs y SIEMPRE responde una sola línea JSON: {"ok":true,...} o {"ok":false,"error":"..."}.
  Pruebas automáticas: src-tauri/scripts/probar_optimizador.ps1 (corren aquí y en GitHub).

  Acciones:
    revisar                          Revisa la PC (solo lee).
    aplicar  -Perfil <p> [-Windows]  Gráficos del GTA (extremo|bajo|medio|alto). Con -Windows además:
                                     tarjeta de video potente para FiveM, plan de energía, sin grabación de Game Bar y Modo juego.
    restaurar                        Deja todo como estaba antes del primer cambio.
    cache                            Cuánto ocupa la caché de FiveM.
    limpiar                          Borra la caché de FiveM (no toca cache\game). Solo con el juego cerrado.
    cerrar   -Nombres a,b            Cierra programas pesados de una lista fija (navegadores, Spotify, OBS).

  Blindaje:
    - Respalda settings.xml y anota cada valor del registro ANTES de cambiarlo; lo anotado se guarda aunque algo falle a mitad.
    - Escribe settings.xml y estado.json de forma atómica (archivo temporal + reemplazo): nunca quedan a medias.
    - Solo modifica nodos que ya existen; si el XML no se puede leer o el resultado no es XML válido, no escribe nada.
    - Si estado.json está dañado, lo aparta (estado_danado_*.json) y sigue.
    - Restaurar sigue aunque falle una parte; lo que no pudo deshacer queda anotado para intentarlo otra vez.
    - Consultas a Windows con tiempo límite; cualquier error se responde en español y se anota en registro.log.
    - No toca nada si el juego (FiveM o GTA V) está abierto.

  Para pruebas: -Raiz <carpeta> cambia Documentos/LocalAppData/AppData por <carpeta>\Documents|Local|Roaming,
  -RegBase cambia HKCU: por otra clave, -SinEnergia no toca powercfg y -SinProcesos ignora los programas abiertos.
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('revisar', 'aplicar', 'restaurar', 'cache', 'limpiar', 'cerrar')][string]$Accion,
    [ValidateSet('extremo', 'bajo', 'medio', 'alto')][string]$Perfil = 'extremo',
    [switch]$Windows,
    [string[]]$Nombres = @(),
    [string]$Raiz = '',
    [string]$RegBase = 'HKCU:',
    [switch]$SinEnergia,
    [switch]$SinProcesos
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
$INV = [Globalization.CultureInfo]::InvariantCulture
$UTF8 = New-Object System.Text.UTF8Encoding($false)

# ===== Rutas (en MAYÚSCULAS y con nombres que no choquen: PowerShell no distingue mayúsculas) =====
if ($Raiz) {
    $DIR_DOCS = Join-Path $Raiz 'Documents'; $DIR_LOCAL = Join-Path $Raiz 'Local'; $DIR_ROAM = Join-Path $Raiz 'Roaming'
} else {
    $DIR_DOCS = [Environment]::GetFolderPath('MyDocuments'); $DIR_LOCAL = $env:LOCALAPPDATA; $DIR_ROAM = $env:APPDATA
}
$RUTA_SETTINGS = Join-Path $DIR_DOCS 'Rockstar Games\GTA V\settings.xml'
$DIR_FIVEM = Join-Path $DIR_LOCAL 'FiveM'
$RUTA_FIVEM_EXE = Join-Path $DIR_FIVEM 'FiveM.exe'
$DIR_FIVEM_DATA = Join-Path $DIR_FIVEM 'FiveM.app\data'
$DIR_PROPIA = Join-Path $DIR_ROAM 'SaltoAngelLauncher\optimizador'
$RUTA_ESTADO = Join-Path $DIR_PROPIA 'estado.json'
$RUTA_LOG = Join-Path $DIR_PROPIA 'registro.log'

$REG_GPU = "$RegBase\Software\Microsoft\DirectX\UserGpuPreferences"
$REG_DVR1 = "$RegBase\System\GameConfigStore"
$REG_DVR2 = "$RegBase\Software\Microsoft\Windows\CurrentVersion\GameDVR"
$REG_MODO = "$RegBase\Software\Microsoft\GameBar"

$PLAN_ALTO = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'      # Alto rendimiento
$PLAN_MAXIMO = 'e9a42b02-d5df-448d-aa00-03f14749eb61'    # Máximo rendimiento (plantilla oculta)
$PATRON_GUID = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

# Programas que se pueden cerrar (nunca Steam, Epic ni Rockstar: el GTA los necesita)
$CERRABLES = @('chrome', 'msedge', 'firefox', 'opera', 'brave', 'Spotify', 'obs64', 'obs32')
# Procesos del juego: con cualquiera abierto no se toca nada
$PROCESOS_JUEGO = @('FiveM', 'GTA5', 'GTA5_Enhanced', 'PlayGTAV', 'GTAVLauncher')

# ===== Utilidades =====
function Anotar([string]$texto) {
    try {
        [IO.Directory]::CreateDirectory($DIR_PROPIA) | Out-Null
        if ((Test-Path -LiteralPath $RUTA_LOG) -and (Get-Item -LiteralPath $RUTA_LOG).Length -gt 256KB) { Remove-Item -LiteralPath $RUTA_LOG -Force }
        [IO.File]::AppendAllText($RUTA_LOG, ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + " [$Accion] " + $texto + "`r`n"), $UTF8)
    } catch {}
}
function Salir($obj) { $obj | ConvertTo-Json -Depth 6 -Compress; exit 0 }
function Fallar([string]$texto) { Anotar ('ERROR: ' + $texto); Salir @{ ok = $false; error = $texto } }

# Escritura atómica: se escribe un temporal y se reemplaza de una vez.
# Ojo: en PowerShell un $null pasado a .NET llega como "" y File.Replace lo rechaza; por eso [NullString]::Value.
function ReemplazarArchivo([string]$tmp, [string]$ruta) {
    try {
        if (Test-Path -LiteralPath $ruta) { [IO.File]::Replace($tmp, $ruta, [NullString]::Value) } else { [IO.File]::Move($tmp, $ruta) }
    } catch {
        # Discos donde Replace no existe (USB FAT32, unidades de red): copia y borra el temporal
        [IO.File]::Copy($tmp, $ruta, $true)
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}
function EscribirAtomico([string]$ruta, [string]$texto, $codificacion) {
    $tmp = $ruta + '.tmp_sa'
    try {
        [IO.File]::WriteAllText($tmp, $texto, $codificacion)
        ReemplazarArchivo $tmp $ruta
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function JuegoAbierto {
    if ($SinProcesos) { return $false }
    $p = Get-Process -ErrorAction SilentlyContinue | Where-Object { $PROCESOS_JUEGO -contains $_.ProcessName -or $_.ProcessName -like 'FiveM_*' }
    return [bool]$p
}

function Cim([string]$clase, [string]$filtro = '', [string]$espacio = 'root/cimv2') {
    $a = @{ ClassName = $clase; Namespace = $espacio; OperationTimeoutSec = 10; ErrorAction = 'Stop' }
    if ($filtro) { $a.Filter = $filtro }
    return Get-CimInstance @a
}

# ===== Estado previo (para "Volver como estaba") =====
function LeerEstado {
    if (-not (Test-Path -LiteralPath $RUTA_ESTADO)) { return $null }
    try {
        $e = [IO.File]::ReadAllText($RUTA_ESTADO) | ConvertFrom-Json
        if (-not $e -or -not ($e.PSObject.Properties.Name -contains 'registro')) { throw 'sin formato' }
        $e.registro = @($e.registro | Where-Object { $_ })
        return $e
    } catch {
        $apartado = Join-Path $DIR_PROPIA ('estado_danado_' + (Get-Date).ToString('yyyyMMdd_HHmmss') + '.json')
        try { Move-Item -LiteralPath $RUTA_ESTADO -Destination $apartado -Force } catch {}
        Anotar ('estado.json dañado, apartado en ' + $apartado)
        return $null
    }
}
function GuardarEstado($e) {
    [IO.Directory]::CreateDirectory($DIR_PROPIA) | Out-Null
    EscribirAtomico $RUTA_ESTADO ($e | ConvertTo-Json -Depth 6) $UTF8
}
function EstadoNuevo {
    return [pscustomobject]@{ creado = (Get-Date).ToString('s'); perfil = ''; windows = $false; settingsRespaldo = $null; settingsSoloLectura = $false; registro = @(); energiaAnterior = $null; energiaCreada = $null }
}

# ===== Registro (anota el valor viejo una sola vez, antes de cambiarlo) =====
function PonerRegistro($estado, [string]$clave, [string]$nombre, $valor, [string]$tipo) {
    $ya = @($estado.registro | Where-Object { $_.clave -eq $clave -and $_.nombre -eq $nombre })
    if ($ya.Count -eq 0) {
        $viejo = $null; $existia = $false; $tipoViejo = $tipo
        if (Test-Path -LiteralPath $clave) {
            $item = Get-Item -LiteralPath $clave
            if ($item.GetValueNames() -contains $nombre) {
                $existia = $true; $viejo = $item.GetValue($nombre); $tipoViejo = $item.GetValueKind($nombre).ToString()
            }
        }
        $estado.registro = @($estado.registro) + [pscustomobject]@{ clave = $clave; nombre = $nombre; existia = $existia; valor = $viejo; tipo = $tipoViejo }
    }
    if (-not (Test-Path -LiteralPath $clave)) { New-Item -Path $clave -Force | Out-Null }
    New-ItemProperty -LiteralPath $clave -Name $nombre -Value $valor -PropertyType $tipo -Force | Out-Null
}

function DevolverRegistro($r) {
    if ($r.existia) {
        if (-not (Test-Path -LiteralPath $r.clave)) { New-Item -Path $r.clave -Force | Out-Null }
        $v = $r.valor
        switch ($r.tipo) {
            'DWord' { $v = [int]$v }
            'QWord' { $v = [long]$v }
            'Binary' { $v = [byte[]]@($v) }
            'MultiString' { $v = [string[]]@($v) }
            default { $v = [string]$v }
        }
        New-ItemProperty -LiteralPath $r.clave -Name $r.nombre -Value $v -PropertyType $r.tipo -Force | Out-Null
    } elseif (Test-Path -LiteralPath $r.clave) {
        $item = Get-Item -LiteralPath $r.clave
        if ($item.GetValueNames() -contains $r.nombre) { Remove-ItemProperty -LiteralPath $r.clave -Name $r.nombre }
    }
}

# ===== Perfiles de gráficos (valores del menú del juego; solo se cambian nodos que existen) =====
# Texturas 0-2, sombras 1-3, reflejos/hierba/partículas/postFX 0-3, agua/shaders/SSAO 0-2. LodScale = distancia (0 a 1).
# SamplingMode (escalado de resolución) NO se toca: no se sabe con certeza qué número es cada escala.
$PERFILES = @{
    extremo = [ordered]@{ TextureQuality = 0; ShadowQuality = 1; ReflectionQuality = 0; ReflectionMSAA = 0; WaterQuality = 0; ParticleQuality = 0; GrassQuality = 0; ShaderQuality = 0
        PostFX = 0; SSAO = 0; MSAA = 0; AnisotropicFiltering = 0; Tessellation = 0; FXAA_Enabled = 'false'; TXAA_Enabled = 'false'; DoF = 'false'
        LodScale = 0.0; MaxLodScale = 0.0; PedLodBias = 0.0; VehicleLodBias = 0.0; CityDensity = 0.0; PedVarietyMultiplier = 0.0; VehicleVarietyMultiplier = 0.0
        MotionBlurStrength = 0.0; Shadow_SoftShadows = 0; UltraShadows_Enabled = 'false'; Shadow_ParticleShadows = 'false'; Shadow_LongShadows = 'false'
        Shadow_Distance = 1.0; HdStreamingInFlight = 'false'; Lighting_FogVolumes = 'false'; Reflection_MipBlur = 'false'; VSync = 0 }
    bajo = [ordered]@{ TextureQuality = 0; ShadowQuality = 1; ReflectionQuality = 0; ReflectionMSAA = 0; WaterQuality = 0; ParticleQuality = 0; GrassQuality = 0; ShaderQuality = 0
        PostFX = 0; SSAO = 0; MSAA = 0; AnisotropicFiltering = 1; Tessellation = 0; FXAA_Enabled = 'true'; TXAA_Enabled = 'false'; DoF = 'false'
        LodScale = 0.3; MaxLodScale = 0.0; PedLodBias = 0.2; VehicleLodBias = 0.2; CityDensity = 0.5; PedVarietyMultiplier = 0.5; VehicleVarietyMultiplier = 0.5
        MotionBlurStrength = 0.0; Shadow_SoftShadows = 0; UltraShadows_Enabled = 'false'; Shadow_ParticleShadows = 'false'; Shadow_LongShadows = 'false'
        Shadow_Distance = 1.0; HdStreamingInFlight = 'false'; Lighting_FogVolumes = 'false'; VSync = 0 }
    medio = [ordered]@{ TextureQuality = 1; ShadowQuality = 2; ReflectionQuality = 1; ReflectionMSAA = 0; WaterQuality = 1; ParticleQuality = 1; GrassQuality = 1; ShaderQuality = 1
        PostFX = 1; SSAO = 1; MSAA = 0; AnisotropicFiltering = 2; Tessellation = 1; FXAA_Enabled = 'true'; TXAA_Enabled = 'false'; DoF = 'false'
        LodScale = 0.6; MaxLodScale = 0.0; PedLodBias = 0.5; VehicleLodBias = 0.5; CityDensity = 0.8; PedVarietyMultiplier = 0.8; VehicleVarietyMultiplier = 0.8
        MotionBlurStrength = 0.0; Shadow_SoftShadows = 1; UltraShadows_Enabled = 'false'; Shadow_ParticleShadows = 'false'; Shadow_LongShadows = 'false'
        Shadow_Distance = 1.0; HdStreamingInFlight = 'false'; Lighting_FogVolumes = 'true' }
    alto = [ordered]@{ TextureQuality = 2; ShadowQuality = 3; ReflectionQuality = 2; ReflectionMSAA = 0; WaterQuality = 2; ParticleQuality = 2; GrassQuality = 2; ShaderQuality = 2
        PostFX = 2; SSAO = 2; MSAA = 0; AnisotropicFiltering = 3; Tessellation = 2; FXAA_Enabled = 'true'; TXAA_Enabled = 'false'; DoF = 'false'
        LodScale = 1.0; MaxLodScale = 0.0; PedLodBias = 1.0; VehicleLodBias = 1.0; CityDensity = 1.0; PedVarietyMultiplier = 1.0; VehicleVarietyMultiplier = 1.0
        MotionBlurStrength = 0.0; Shadow_SoftShadows = 2; UltraShadows_Enabled = 'false'; Shadow_ParticleShadows = 'true'; Shadow_LongShadows = 'false'
        Shadow_Distance = 1.0; HdStreamingInFlight = 'false'; Lighting_FogVolumes = 'true' }
}

function TextoValor($v) {
    if ($v -is [double]) { return $v.ToString('F6', $INV) }
    return [string]$v
}

function AplicarGraficos($estado, [string]$perfil) {
    if (-not (Test-Path -LiteralPath $RUTA_SETTINGS)) { return @{ aplicado = $false; motivo = 'No hay settings.xml: abre el GTA o FiveM una vez y vuelve a intentarlo.' } }
    try {
        $bytes = [IO.File]::ReadAllBytes($RUTA_SETTINGS)
        $texto = [IO.File]::ReadAllText($RUTA_SETTINGS)
    } catch { return @{ aplicado = $false; motivo = 'No se pudo leer settings.xml (¿está abierto el juego o lo bloquea el antivirus?). No se tocó.' } }
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if ($texto -notmatch '<Settings>' -or $texto -notmatch '<graphics>') { return @{ aplicado = $false; motivo = 'El settings.xml no tiene el formato esperado. No se tocó.' } }
    try { [xml]$texto | Out-Null } catch { return @{ aplicado = $false; motivo = 'El settings.xml está dañado. No se tocó. Bórralo y abre el GTA para que cree uno nuevo.' } }

    $nuevo = $texto
    $cambiados = 0
    foreach ($par in $PERFILES[$perfil].GetEnumerator()) {
        $patron = '(<' + [regex]::Escape($par.Key) + '\s+value=")[^"]*(")'
        if ([regex]::IsMatch($nuevo, $patron)) {
            $valor = TextoValor $par.Value
            $nuevo = [regex]::Replace($nuevo, $patron, { param($m) $m.Groups[1].Value + $valor + $m.Groups[2].Value })
            $cambiados++
        }
    }
    if ($cambiados -eq 0) { return @{ aplicado = $false; motivo = 'El settings.xml no tiene las opciones de gráficos esperadas. No se tocó.' } }
    try { [xml]$nuevo | Out-Null } catch { return @{ aplicado = $false; motivo = 'No se pudo armar el archivo nuevo. No se tocó.' } }

    # Respaldo del original, solo la primera vez y ANTES de escribir nada
    if (-not $estado.settingsRespaldo) {
        $carpeta = Join-Path $DIR_PROPIA 'respaldos'
        [IO.Directory]::CreateDirectory($carpeta) | Out-Null
        $copia = Join-Path $carpeta ('settings_' + (Get-Date).ToString('yyyy-MM-dd_HHmmss') + '.xml')
        [IO.File]::WriteAllBytes($copia, $bytes)
        $estado.settingsRespaldo = $copia
        $estado.settingsSoloLectura = (Get-Item -LiteralPath $RUTA_SETTINGS).IsReadOnly
        GuardarEstado $estado
    }

    $info = Get-Item -LiteralPath $RUTA_SETTINGS
    $soloLectura = $info.IsReadOnly
    if ($soloLectura) { $info.IsReadOnly = $false }
    try {
        EscribirAtomico $RUTA_SETTINGS $nuevo (New-Object System.Text.UTF8Encoding($bom))
    } finally {
        if ($soloLectura -and (Test-Path -LiteralPath $RUTA_SETTINGS)) { (Get-Item -LiteralPath $RUTA_SETTINGS).IsReadOnly = $true }
    }
    return @{ aplicado = $true; cambiados = $cambiados }
}

# ===== Ajustes de Windows del modo extremo =====
function TarjetasVideo {
    try { return @(Cim 'Win32_VideoController' | Where-Object { $_.Name -notmatch 'Basic Display|Remote|Virtual|Parsec|Meta|Mirage|DisplayLink' }) } catch { return @() }
}
function EsLaptop {
    try { return [bool](Cim 'Win32_Battery') } catch { return $false }
}

function ExesFivem {
    $lista = @($RUTA_FIVEM_EXE, (Join-Path $DIR_FIVEM_DATA 'cache\subprocess\FiveM_b3258_GTAProcess.exe'))
    $sub = Join-Path $DIR_FIVEM_DATA 'cache\subprocess'
    if (Test-Path -LiteralPath $sub) { Get-ChildItem -LiteralPath $sub -Filter 'FiveM_*GTAProcess.exe' -ErrorAction SilentlyContinue | ForEach-Object { $lista += $_.FullName } }
    return @($lista | Select-Object -Unique)
}

# powercfg con sus avisos atrapados (en PowerShell 5.1 un aviso de un programa externo puede cortar el script)
function Powercfg {
    $ErrorActionPreference = 'Continue'
    try {
        $salida = (& powercfg.exe @args 2>&1 | Out-String)
        return @{ texto = $salida; codigo = $LASTEXITCODE }
    } catch { return @{ texto = ''; codigo = 1 } }
}

function PlanActivo {
    $s = (Powercfg /getactivescheme).texto
    $m = [regex]::Match($s, $PATRON_GUID)
    $nombre = [regex]::Match($s, '\(([^)]*)\)').Groups[1].Value
    if ($m.Success) { return @{ guid = $m.Value.ToLower(); nombre = $nombre } }
    return $null
}

function AplicarWindows($estado) {
    $hecho = @(); $fallos = @()
    # Cada ajuste por separado: si uno falla (PC de empresa, permisos), los demás igual se aplican
    # 1) Tarjeta de video potente para FiveM (sirve en PCs con dos tarjetas, típico de laptops)
    try {
        if ((TarjetasVideo).Count -gt 1 -or (EsLaptop)) {
            foreach ($exe in ExesFivem) { PonerRegistro $estado $REG_GPU $exe 'GpuPreference=2;' 'String' }
            $hecho += 'gpu'
        }
    } catch { $fallos += 'gpu'; Anotar ('gpu: ' + $_.Exception.Message) }
    # 2) Sin grabación en segundo plano de Xbox Game Bar
    try {
        PonerRegistro $estado $REG_DVR1 'GameDVR_Enabled' 0 'DWord'
        PonerRegistro $estado $REG_DVR2 'AppCaptureEnabled' 0 'DWord'
        $hecho += 'gamebar'
    } catch { $fallos += 'gamebar'; Anotar ('gamebar: ' + $_.Exception.Message) }
    # 3) Modo juego de Windows
    try {
        PonerRegistro $estado $REG_MODO 'AutoGameModeEnabled' 1 'DWord'
        PonerRegistro $estado $REG_MODO 'AllowAutoGameMode' 1 'DWord'
        $hecho += 'modojuego'
    } catch { $fallos += 'modojuego'; Anotar ('modojuego: ' + $_.Exception.Message) }
    # 4) Plan de energía: Alto rendimiento; si la PC no lo tiene, una copia de Máximo rendimiento
    if (-not $SinEnergia) {
        try {
            $actual = PlanActivo
            if ($actual -and -not $estado.energiaAnterior) { $estado.energiaAnterior = $actual.guid; GuardarEstado $estado }
            $r = Powercfg /setactive $PLAN_ALTO
            if ($r.codigo -ne 0) {
                if (-not $estado.energiaCreada) {
                    $m = [regex]::Match((Powercfg -duplicatescheme $PLAN_MAXIMO).texto, $PATRON_GUID)
                    if ($m.Success) { $estado.energiaCreada = $m.Value.ToLower(); GuardarEstado $estado }
                }
                if ($estado.energiaCreada) { $r = Powercfg /setactive $estado.energiaCreada }
            }
            if ($r.codigo -eq 0) { $hecho += 'energia' } else { $fallos += 'energia' }
        } catch { $fallos += 'energia'; Anotar ('energia: ' + $_.Exception.Message) }
    }
    return @{ hecho = $hecho; fallos = $fallos }
}

# ===== Caché de FiveM =====
function CarpetasCache {
    $lista = @()
    foreach ($n in @('server-cache', 'server-cache-priv')) { $p = Join-Path $DIR_FIVEM_DATA $n; if (Test-Path -LiteralPath $p) { $lista += $p } }
    $cache = Join-Path $DIR_FIVEM_DATA 'cache'
    if (Test-Path -LiteralPath $cache) {
        # Todo menos cache\game: ahí está la copia de datos del GTA y bajarla otra vez tarda mucho
        Get-ChildItem -LiteralPath $cache -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'game' } | ForEach-Object { $lista += $_.FullName }
    }
    return $lista
}
function TamanoMB($rutas) {
    $total = 0
    foreach ($r in $rutas) {
        try {
            $i = Get-Item -LiteralPath $r -Force
            if ($i.PSIsContainer) { $s = (Get-ChildItem -LiteralPath $r -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if ($s) { $total += $s } }
            else { $total += $i.Length }
        } catch {}
    }
    return [math]::Round($total / 1MB)
}

# ===== Revisión de la PC (cada parte por separado: si una falla, las demás igual salen) =====
function Revisar {
    $tarjetas = @()
    try {
        $tarjetas = @(TarjetasVideo | ForEach-Object {
                $meses = $null
                try { if ($_.DriverDate) { $meses = [int][math]::Floor(((Get-Date) - [datetime]$_.DriverDate).TotalDays / 30.4) } } catch {}
                if ($meses -lt 0) { $meses = $null }
                $vram = $null
                if ($_.AdapterRAM -and $_.AdapterRAM -gt 0) { $vram = [math]::Round($_.AdapterRAM / 1MB) } # Windows topa este dato en 4 GB
                [pscustomobject]@{ nombre = [string]$_.Name; driver = [string]$_.DriverVersion; driverMeses = $meses; vramMB = $vram }
            })
    } catch {}
    $ram = $null
    try { $ram = [math]::Round((Cim 'Win32_ComputerSystem').TotalPhysicalMemory / 1GB, 1) } catch {}
    $disco = $null
    try {
        $letra = (Split-Path -Qualifier $DIR_LOCAL)
        $d = Cim 'Win32_LogicalDisk' ("DeviceID='" + $letra + "'")
        $ssd = $null
        try {
            $part = Cim 'MSFT_Partition' ("DriveLetter='" + $letra.TrimEnd(':') + "'") 'root/Microsoft/Windows/Storage'
            $fis = @(Cim 'MSFT_PhysicalDisk' '' 'root/Microsoft/Windows/Storage' | Where-Object { [string]$_.DeviceId -eq [string]$part.DiskNumber })
            if ($fis.Count) { if ($fis[0].MediaType -eq 4) { $ssd = $true } elseif ($fis[0].MediaType -eq 3) { $ssd = $false } }
        } catch {}
        $disco = [pscustomobject]@{ unidad = $letra; libreGB = [math]::Round($d.FreeSpace / 1GB); totalGB = [math]::Round($d.Size / 1GB); ssd = $ssd }
    } catch {}
    $plan = $null
    if (-not $SinEnergia) { try { $plan = PlanActivo } catch {} }
    $dvr = $false
    try { $v = (Get-ItemProperty -LiteralPath $REG_DVR2 -Name AppCaptureEnabled -ErrorAction Stop).AppCaptureEnabled; $dvr = ($v -ne 0) } catch {}
    try { $v = (Get-ItemProperty -LiteralPath $REG_DVR1 -Name GameDVR_Enabled -ErrorAction Stop).GameDVR_Enabled; if ($v -eq 0) { $dvr = $false } } catch {}

    $pesados = @()
    if (-not $SinProcesos) {
        try {
            $pesados = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $CERRABLES -contains $_.ProcessName -or @('Discord', 'steamwebhelper') -contains $_.ProcessName } |
                Group-Object ProcessName | ForEach-Object {
                    [pscustomobject]@{ nombre = $_.Name; mb = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB); cerrable = ($CERRABLES -contains $_.Name) }
                } | Where-Object { $_.mb -ge 150 } | Sort-Object mb -Descending)
        } catch {}
    }

    $estado = LeerEstado
    $cacheMB = 0
    try { $cacheMB = TamanoMB (CarpetasCache) } catch {}
    $pendiente = $false
    if ($estado -and ($estado.PSObject.Properties.Name -contains 'pendiente')) { $pendiente = [bool]$estado.pendiente }
    Salir @{
        ok = $true
        tarjetas = $tarjetas; ramGB = $ram; disco = $disco; laptop = (EsLaptop)
        energia = $plan; gameBarGraba = $dvr
        fivem = @{ instalado = (Test-Path -LiteralPath $RUTA_FIVEM_EXE); abierto = (JuegoAbierto); cacheMB = $cacheMB }
        settings = @{ existe = (Test-Path -LiteralPath $RUTA_SETTINGS) }
        optimizado = [bool]$estado; perfil = $(if ($estado) { [string]$estado.perfil } else { '' }); extremo = $(if ($estado) { [bool]$estado.windows } else { $false })
        pendiente = $pendiente
        pesados = $pesados
    }
}

# ===== Acciones =====
try {
    switch ($Accion) {
        'revisar' { Revisar }

        'aplicar' {
            if (JuegoAbierto) { Fallar 'Cierra FiveM y el GTA primero: el juego guarda sus gráficos al salir y borraría el cambio.' }
            $estado = LeerEstado
            if (-not $estado) { $estado = EstadoNuevo }
            $g = @{ aplicado = $false; motivo = '' }; $w = @{ hecho = @(); fallos = @() }
            # Pase lo que pase, lo anotado se guarda: así "Volver como estaba" siempre puede deshacerlo
            try {
                $g = AplicarGraficos $estado $Perfil
                if ($g.aplicado) { $estado.perfil = $Perfil }
                if ($Windows) { $w = AplicarWindows $estado; if ($w.hecho.Count) { $estado.windows = $true } }
            } finally {
                if ($estado.settingsRespaldo -or @($estado.registro).Count -or $estado.energiaAnterior) { GuardarEstado $estado }
            }
            if (-not $g.aplicado -and $w.hecho.Count -eq 0) { Fallar $g.motivo }
            Anotar ('aplicado ' + $Perfil + ' graficos=' + $g.aplicado + ' windows=' + ($w.hecho -join ',') + ' fallos=' + ($w.fallos -join ','))
            Salir @{ ok = $true; perfil = $Perfil; graficos = $g; windows = $w.hecho; fallos = $w.fallos }
        }

        'restaurar' {
            $estado = LeerEstado
            if (-not $estado) { Salir @{ ok = $true; nada = $true } }
            if ($estado.settingsRespaldo -and (JuegoAbierto)) { Fallar 'Cierra FiveM y el GTA primero para devolver tus gráficos.' }
            $avisos = @(); $quedan = @()

            if ($estado.settingsRespaldo) {
                if (Test-Path -LiteralPath $estado.settingsRespaldo) {
                    try {
                        $bytes = [IO.File]::ReadAllBytes($estado.settingsRespaldo)
                        if ((Test-Path -LiteralPath $RUTA_SETTINGS) -and (Get-Item -LiteralPath $RUTA_SETTINGS).IsReadOnly) { (Get-Item -LiteralPath $RUTA_SETTINGS).IsReadOnly = $false }
                        $tmp = $RUTA_SETTINGS + '.tmp_sa'
                        try { [IO.File]::WriteAllBytes($tmp, $bytes); ReemplazarArchivo $tmp $RUTA_SETTINGS }
                        finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
                        if ($estado.settingsSoloLectura) { (Get-Item -LiteralPath $RUTA_SETTINGS).IsReadOnly = $true }
                        $estado.settingsRespaldo = $null
                    } catch { $avisos += 'graficos'; Anotar ('restaurar graficos: ' + $_.Exception.Message) }
                } else {
                    $avisos += 'respaldo_perdido'; $estado.settingsRespaldo = $null
                    Anotar 'el respaldo de settings.xml ya no existe'
                }
            }

            foreach ($r in @($estado.registro)) {
                try { DevolverRegistro $r } catch { $quedan += $r; Anotar ('restaurar registro ' + $r.nombre + ': ' + $_.Exception.Message) }
            }
            $estado.registro = $quedan

            if (-not $SinEnergia) {
                if ($estado.energiaAnterior) {
                    $r = Powercfg /setactive $estado.energiaAnterior
                    if ($r.codigo -eq 0) { $estado.energiaAnterior = $null } else { Anotar 'no se pudo devolver el plan de energía' }
                }
                if ($estado.energiaCreada -and -not $estado.energiaAnterior) { Powercfg /delete $estado.energiaCreada | Out-Null; $estado.energiaCreada = $null }
            } else { $estado.energiaAnterior = $null; $estado.energiaCreada = $null }

            if ($estado.settingsRespaldo -or @($estado.registro).Count -or $estado.energiaAnterior) {
                $estado | Add-Member -NotePropertyName pendiente -NotePropertyValue $true -Force
                GuardarEstado $estado
                Fallar 'Se devolvió casi todo, pero quedó algo pendiente. Vuelve a darle a "Volver como estaba".'
            }
            Remove-Item -LiteralPath $RUTA_ESTADO -Force -ErrorAction SilentlyContinue
            Anotar ('restaurado' + $(if ($avisos.Count) { ' con avisos: ' + ($avisos -join ',') } else { '' }))
            Salir @{ ok = $true; avisos = $avisos }
        }

        'cache' { Salir @{ ok = $true; cacheMB = (TamanoMB (CarpetasCache)); abierto = (JuegoAbierto) } }

        'limpiar' {
            if (JuegoAbierto) { Fallar 'Cierra FiveM y el GTA primero para limpiar la caché.' }
            $rutas = CarpetasCache
            $antes = TamanoMB $rutas
            $fallos = 0
            foreach ($r in $rutas) { try { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction Stop } catch { $fallos++ } }
            $despues = TamanoMB (CarpetasCache)
            Anotar ('limpiado ' + ($antes - $despues) + ' MB, fallos=' + $fallos)
            Salir @{ ok = $true; liberadoMB = [math]::Max(0, $antes - $despues); fallos = $fallos }
        }

        'cerrar' {
            $cerrados = @()
            foreach ($n in @($Nombres | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() })) {
                if ($CERRABLES -notcontains $n) { continue }
                $p = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
                if ($p.Count) { $p | Stop-Process -ErrorAction SilentlyContinue; $cerrados += $n }
            }
            Salir @{ ok = $true; cerrados = $cerrados }
        }
    }
} catch {
    Fallar ('Algo falló: ' + $_.Exception.Message + ' (línea ' + $_.InvocationInfo.ScriptLineNumber + ')')
}
