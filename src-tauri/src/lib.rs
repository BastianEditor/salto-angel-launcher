// Salto Ángel Launcher: parte nativa (Rust).
// Reglas del proyecto (docs/disenos/LAUNCHER.md §2): solo abre el FiveM oficial con el enlace fivem://,
// nunca escribe en la carpeta de FiveM, no lee ni toca procesos (solo mira si están abiertos).

use serde::Serialize;
use std::io::Read;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tauri::{AppHandle, Manager};
use tauri_plugin_opener::OpenerExt;
use tauri_plugin_updater::UpdaterExt;

/// Código de cfx.re/join del servidor. La pantalla puede mandar otro (configuración remota), pero se limpia.
const JOIN_POR_DEFECTO: &str = "m4qzz8q";

#[cfg(windows)]
const SIN_VENTANA: u32 = 0x0800_0000; // CREATE_NO_WINDOW: que no parpadee una consola

/// Una sola acción del optimizador a la vez (dos clics seguidos no pueden pisarse)
static CANDADO_OPTIMIZADOR: Mutex<()> = Mutex::new(());

const AYUDA: &str = "Si sigue pasando, pide ayuda en el Discord de Salto Ángel.";

#[derive(Serialize)]
struct EstadoFivem {
    instalado: bool,
    abierto: bool,
}

#[derive(Serialize)]
struct InfoActualizacion {
    version: String,
    notas: Option<String>,
}

/// FiveM se instala por defecto en %LOCALAPPDATA%\FiveM\FiveM.exe
fn exe_fivem() -> Option<PathBuf> {
    let base = std::env::var_os("LOCALAPPDATA")?;
    let ruta = PathBuf::from(base).join("FiveM").join("FiveM.exe");
    ruta.exists().then_some(ruta)
}

/// Si lo instalaron en otra carpeta, igual queda registrado el enlace fivem:// en Windows
#[cfg(windows)]
fn protocolo_registrado() -> bool {
    use std::os::windows::process::CommandExt;
    std::process::Command::new("reg")
        .args(["query", r"HKCU\Software\Classes\fivem", "/ve"])
        .creation_flags(SIN_VENTANA)
        .output()
        .map(|s| s.status.success())
        .unwrap_or(false)
}

#[cfg(not(windows))]
fn protocolo_registrado() -> bool {
    false
}

/// Solo mira la lista de programas abiertos (lo mismo que el Administrador de tareas)
fn fivem_abierto() -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        if let Ok(salida) = std::process::Command::new("tasklist")
            .args(["/FO", "CSV", "/NH"])
            .creation_flags(SIN_VENTANA)
            .output()
        {
            let texto = String::from_utf8_lossy(&salida.stdout).to_lowercase();
            return texto.contains("\"fivem.exe\"") || texto.contains("\"fivem_");
        }
    }
    false
}

#[tauri::command]
fn estado_fivem() -> EstadoFivem {
    EstadoFivem {
        instalado: exe_fivem().is_some() || protocolo_registrado(),
        abierto: fivem_abierto(),
    }
}

/// Abre FiveM oficial y lo conecta al servidor
#[tauri::command]
fn jugar(app: AppHandle, codigo: Option<String>) -> Result<(), String> {
    let limpio: String = codigo
        .unwrap_or_default()
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect();
    let codigo = if limpio.is_empty() || limpio.len() > 16 {
        JOIN_POR_DEFECTO.to_string()
    } else {
        limpio
    };
    let url = format!("fivem://connect/cfx.re/join/{codigo}");
    // FiveM solo acepta que lo abra Windows (el explorador) o un navegador: si lo abre el launcher
    // directo sale "This application should be launched directly from the shell or a web browser".
    // Por eso se le pasa el enlace al explorador de Windows, igual que un clic en un acceso directo.
    if abrir_con_explorador(&url) {
        return Ok(());
    }
    // Plan B: la página oficial cfx.re/join en el navegador, que ofrece abrir FiveM
    app.opener()
        .open_url(format!("https://cfx.re/join/{codigo}"), None::<&str>)
        .map_err(|e| format!("No se pudo abrir FiveM: {e}"))
}

#[cfg(windows)]
fn abrir_con_explorador(url: &str) -> bool {
    use std::os::windows::process::CommandExt;
    let windir = std::env::var_os("WINDIR").unwrap_or_else(|| "C:\\Windows".into());
    let explorador = PathBuf::from(windir).join("explorer.exe");
    // explorer.exe responde con código 1 aunque funcione: solo importa que haya arrancado
    std::process::Command::new(explorador)
        .arg(url)
        .creation_flags(SIN_VENTANA)
        .spawn()
        .is_ok()
}

#[cfg(not(windows))]
fn abrir_con_explorador(_url: &str) -> bool {
    false
}

/// Abre un enlace en el navegador. Solo https, para que nadie pueda usarlo para abrir otra cosa.
#[tauri::command]
fn abrir_enlace(app: AppHandle, url: String) -> Result<(), String> {
    if !url.starts_with("https://") || url.len() > 300 || url.contains(char::is_whitespace) {
        return Err("Enlace no permitido".into());
    }
    app.opener()
        .open_url(url, None::<&str>)
        .map_err(|e| format!("No se pudo abrir el enlace: {e}"))
}

/// Optimizador (src-tauri/scripts/optimizar.ps1, probado aparte). Solo pasa acciones y valores de listas fijas.
#[tauri::command]
async fn optimizador(
    app: AppHandle,
    accion: String,
    perfil: Option<String>,
    windows: Option<bool>,
    nombres: Option<Vec<String>>,
) -> Result<serde_json::Value, String> {
    const ACCIONES: [&str; 6] = ["revisar", "aplicar", "restaurar", "cache", "limpiar", "cerrar"];
    const PERFILES: [&str; 4] = ["extremo", "bajo", "medio", "alto"];
    if !ACCIONES.contains(&accion.as_str()) {
        return Err("Acción no permitida".into());
    }
    let script = app
        .path()
        .resolve("scripts/optimizar.ps1", tauri::path::BaseDirectory::Resource)
        .map_err(|e| e.to_string())?;

    let mut args: Vec<String> = vec![
        "-NoProfile".into(),
        "-NonInteractive".into(),
        "-ExecutionPolicy".into(),
        "Bypass".into(),
        "-File".into(),
        script.to_string_lossy().into_owned(),
        "-Accion".into(),
        accion.clone(),
    ];
    if accion == "aplicar" {
        let p = perfil.unwrap_or_else(|| "extremo".into());
        if !PERFILES.contains(&p.as_str()) {
            return Err("Perfil no permitido".into());
        }
        args.push("-Perfil".into());
        args.push(p);
        if windows.unwrap_or(false) {
            args.push("-Windows".into());
        }
    }
    if accion == "cerrar" {
        let lista: Vec<String> = nombres
            .unwrap_or_default()
            .into_iter()
            .filter(|n| !n.is_empty() && n.len() < 40 && n.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-'))
            .collect();
        if lista.is_empty() {
            return Ok(serde_json::json!({ "ok": true, "cerrados": [] }));
        }
        args.push("-Nombres".into());
        args.push(lista.join(","));
    }

    // Tiempo límite: limpiar una caché grande tarda; lo demás es rápido
    let limite = Duration::from_secs(match accion.as_str() {
        "limpiar" => 300,
        "revisar" => 60,
        _ => 90,
    });

    // Se corre aparte para que la ventana no se congele mientras revisa o limpia
    tauri::async_runtime::spawn_blocking(move || {
        let _turno = CANDADO_OPTIMIZADOR.lock().unwrap_or_else(|e| e.into_inner());
        correr_powershell(&args, limite)
    })
    .await
    .map_err(|_| format!("El optimizador se cerró de golpe. {AYUDA}"))?
}

/// Corre PowerShell con tiempo límite y convierte cualquier falla en un mensaje claro en español
fn correr_powershell(args: &[String], limite: Duration) -> Result<serde_json::Value, String> {
    let mut cmd = std::process::Command::new("powershell.exe");
    cmd.args(args).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(SIN_VENTANA);
    }
    let mut hijo = cmd.spawn().map_err(|e| {
        if e.kind() == std::io::ErrorKind::NotFound {
            format!("Esta PC no tiene PowerShell, que Windows trae de fábrica. {AYUDA}")
        } else {
            format!("Windows o el antivirus no dejaron abrir el optimizador. {AYUDA}")
        }
    })?;

    // La salida se lee en hilos aparte para que nunca se tranque si es larga
    let mut out = hijo.stdout.take();
    let mut err = hijo.stderr.take();
    let lector_out = std::thread::spawn(move || {
        let mut v = Vec::new();
        if let Some(o) = out.as_mut() {
            let _ = o.read_to_end(&mut v);
        }
        v
    });
    let lector_err = std::thread::spawn(move || {
        let mut v = Vec::new();
        if let Some(e) = err.as_mut() {
            let _ = e.read_to_end(&mut v);
        }
        v
    });

    let fin = Instant::now() + limite;
    loop {
        match hijo.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) => {
                if Instant::now() >= fin {
                    let _ = hijo.kill();
                    let _ = hijo.wait();
                    return Err(format!("El optimizador tardó demasiado y se detuvo. No se cambió nada a medias: lo que alcanzó a hacer se puede deshacer con \"Volver como estaba\". {AYUDA}"));
                }
                std::thread::sleep(Duration::from_millis(100));
            }
            Err(_) => return Err(format!("No se pudo esperar al optimizador. {AYUDA}")),
        }
    }

    let salida = lector_out.join().unwrap_or_default();
    let errores = lector_err.join().unwrap_or_default();
    let texto = String::from_utf8_lossy(&salida);
    let linea = texto.lines().rev().find(|l| l.trim_start().starts_with('{')).unwrap_or("");
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(linea.trim()) {
        return Ok(v);
    }

    // No respondió JSON: se explica la causa más probable
    let detalle = String::from_utf8_lossy(&errores).to_lowercase();
    if detalle.contains("execution polic") || detalle.contains("directiva de ejecuci") || detalle.contains("running scripts is disabled") || detalle.contains("ejecución de scripts") {
        Err(format!("Windows no deja correr el optimizador en esta PC (política de seguridad). {AYUDA}"))
    } else if detalle.contains("virus") || detalle.contains("malicious") || detalle.contains("malintencionado") || detalle.contains("blocked") || detalle.contains("bloque") {
        Err(format!("El antivirus bloqueó el optimizador. Agrega el launcher a sus excepciones o desactiva la protección un momento. {AYUDA}"))
    } else {
        Err(format!("El optimizador no respondió bien. {AYUDA}"))
    }
}

#[tauri::command]
fn version(app: AppHandle) -> String {
    app.package_info().version.to_string()
}

/// Revisa en GitHub si hay versión nueva (firmada con la clave del launcher)
#[tauri::command]
async fn buscar_actualizacion(app: AppHandle) -> Result<Option<InfoActualizacion>, String> {
    let updater = app.updater().map_err(|e| e.to_string())?;
    match updater.check().await {
        Ok(Some(u)) => Ok(Some(InfoActualizacion {
            version: u.version.clone(),
            notas: u.body.clone(),
        })),
        Ok(None) => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

/// Baja la versión nueva, verifica la firma, la instala y reinicia el launcher
#[tauri::command]
async fn instalar_actualizacion(app: AppHandle) -> Result<(), String> {
    let updater = app.updater().map_err(|e| e.to_string())?;
    if let Some(u) = updater.check().await.map_err(|e| e.to_string())? {
        u.download_and_install(|_, _| {}, || {})
            .await
            .map_err(|e| e.to_string())?;
        app.restart();
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // Si ya está abierto, se trae al frente en vez de abrir otro
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(ventana) = app.get_webview_window("principal") {
                let _ = ventana.unminimize();
                let _ = ventana.show();
                let _ = ventana.set_focus();
            }
        }))
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .invoke_handler(tauri::generate_handler![
            estado_fivem,
            jugar,
            abrir_enlace,
            optimizador,
            version,
            buscar_actualizacion,
            instalar_actualizacion
        ])
        .run(tauri::generate_context!())
        .expect("no se pudo abrir el launcher");
}
