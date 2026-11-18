# Salto Ángel Launcher (v0.1.0)

Un programa de Windows que abre el **FiveM oficial** y te conecta a Salto Ángel. También muestra el estado del servidor, los jugadores, las novedades y el Discord. Plan completo: `docs/disenos/LAUNCHER.md`.

**Estado (18/11/2026):** el código de la v0.1 está escrito y la pantalla se probó en el navegador. **Falta compilarlo**, cosa que se hace en GitHub, y para eso hace falta la cuenta (ver "Para publicarlo").

## Qué hace la v0.1
- Botón **JUGAR**: abre `fivem://connect/cfx.re/join/m4qzz8q`. Si no encuentra FiveM, explica cómo bajarlo de la página oficial. Después de abrirlo, el launcher se minimiza (se puede apagar en Ajustes).
- Estado del servidor **en vivo** cada 30 s, desde la API pública de Cfx.re (la misma lista de FiveM): En línea, Apagado o Sin conexión, y los jugadores `x / 128`.
- Botones de enlaces (Discord ahora; Normas, Guía y Web aparecen cuando tengan dirección), 3 novedades y una franja de aviso del staff.
- **Se actualiza solo**: revisa GitHub al abrir, y la versión nueva tiene que venir firmada con la clave del launcher.
- Si ya está abierto, no abre otro: trae al frente el que ya está.
- **Optimizar mi PC con el modo extremo** (pedido del dueño, viene desde la v0.1). Todo pasa por `src-tauri/scripts/optimizar.ps1`:
  - **Revisión**: tarjeta de video (avisa si es integrada), antigüedad del driver (con botón a la página oficial de NVIDIA, AMD o Intel), RAM, espacio libre y si el disco es SSD, plan de energía, si Game Bar está grabando y los programas pesados abiertos.
  - **⚡ Modo extremo** (un clic, pide confirmación): gráficos del GTA al mínimo (32 opciones de `settings.xml`), que FiveM use la tarjeta de video potente en PCs con dos tarjetas o laptops, plan Alto rendimiento (o una copia de Máximo rendimiento si la PC no lo tiene), apagar la grabación de Game Bar y prender el Modo juego.
  - **Perfiles** Extremo, Bajo, Medio y Alto, con uno marcado "Para ti" según la PC.
  - **Volver como estaba**: devuelve el `settings.xml` original (idéntico, respetando si era de solo lectura), los valores del registro y el plan de energía.
  - **Limpiar caché** (`server-cache`, `server-cache-priv` y `cache` menos `cache\game`) y **cerrar programas pesados** de una lista fija (navegadores, Spotify, OBS). Nunca cierra Steam, Epic ni Rockstar.
  - Si FiveM está abierto, no deja cambiar gráficos ni limpiar, porque el juego borraría el cambio al salir.
  - **El escalado de resolución no se toca solo**: no hay una fuente confiable del número que usa `SamplingMode` y un número equivocado pondría el juego a doble resolución. La pantalla le dice al jugador cómo ponerlo en el menú del GTA (Escalado de fotogramas → 1/2).
  - El respaldo y el estado quedan en `%APPDATA%\SaltoAngelLauncher\optimizador\` (`estado.json` y `respaldos\`).

**Lo que nunca hace:** no toca la carpeta de FiveM ni el GTA, no inyecta nada y no lee la memoria de ningún programa. Solo mira si FiveM está abierto, igual que el Administrador de tareas.

## Carpetas
| Carpeta | Qué hay |
|---|---|
| `src/` | La pantalla: `index.html`, `estilo.css`, `app.js`, `config.json` (la configuración que trae por dentro) e `img/` |
| `src-tauri/` | La parte nativa (Rust y Tauri 2): `src/lib.rs` (Jugar, detectar FiveM, abrir enlaces, actualizar), `tauri.conf.json` (ventana, instalador, actualizador) e `icons/` |
| `publicar/config.json` | La configuración **remota**: lo que se cambie aquí y se suba a GitHub les llega a todos al abrir el launcher, sin sacar versión nueva |
| `.github/workflows/compilar.yml` | La compilación en GitHub |

## Cambiar las noticias, el aviso o los enlaces (sin sacar versión)
Edita `publicar/config.json` y súbelo a GitHub:
- `aviso`: un texto corto, por ejemplo `"Reinicio a las 6 p. m. por mantenimiento"`. Vacío `""` lo esconde.
- `noticias`: se muestran las 3 primeras. `tipo` puede ser `oro`, `vio`, `verde` o `rojo`. `url` es opcional (https).
- `enlaces`: `url` vacío lo esconde. Solo acepta `https://`.
- `servidor.codigo`: si algún día cambia el `cfx.re/join`.

## Para publicarlo (una sola vez)
1. **El dueño** crea una cuenta en github.com para el servidor (por ejemplo `SaltoAngelRP`).
2. En esta PC se instala **GitHub CLI** y el dueño inicia sesión él mismo (`gh auth login`, se abre el navegador). Nadie le pide ni copia contraseñas.
3. La sesión de Claude crea el repositorio `salto-angel-launcher`, sube esta carpeta y genera la **clave de las actualizaciones** con `npx @tauri-apps/cli signer generate`. La clave privada se guarda **fuera** de esta carpeta, en `C:\FXServer\_privado_launcher\` (no se sube ni se imprime), y va a los secretos de GitHub (`TAURI_SIGNING_PRIVATE_KEY` y `_PASSWORD`).
4. Reemplazar los `PENDIENTE_*` en `src-tauri/tauri.conf.json` (`pubkey` y `endpoints`) y en `src/app.js` (`CONFIG_REMOTA`) con la clave pública y el usuario de GitHub.
5. Subir a `main`: GitHub compila la prueba (Actions → Artifacts → `SaltoAngelLauncher.exe`).
6. Crear la etiqueta `v0.1.0`: GitHub arma el instalador `Salto Angel Launcher_0.1.0_x64-setup.exe` y lo deja como borrador en Releases. Se prueba (ver abajo) y se publica.
7. Enlace de descarga para la web y Discord: `https://github.com/<usuario>/salto-angel-launcher/releases/latest`.

## Sacar una versión nueva
Sube el número en `src-tauri/tauri.conf.json`, `src-tauri/Cargo.toml` y `package.json`, sube los cambios y crea la etiqueta `vX.Y.Z`. Cuando el borrador esté probado y publicado, los launchers instalados avisan "Hay una versión nueva" y se actualizan con un clic.

## A prueba de errores (18/11)
| Qué puede pasar en la PC del jugador | Qué hace el launcher |
|---|---|
| Se va la luz o se cierra a mitad de un cambio | `settings.xml` y `estado.json` se escriben con un temporal y se reemplazan de una vez: nunca quedan a medias. Lo anotado para "Volver como estaba" se guarda **antes** de cambiar cada cosa |
| `settings.xml` dañado, vacío o sin la parte de gráficos | Avisa y no lo toca |
| No hay `settings.xml` (nunca abrió el GTA) | Los gráficos avisan. Lo de Windows del modo extremo igual se aplica y se puede deshacer |
| `estado.json` dañado | Lo aparta (`estado_danado_*.json`) y sigue |
| Borraron la copia de los gráficos | "Volver como estaba" devuelve el resto y avisa |
| Una parte no se puede deshacer | Devuelve todo lo que puede, anota lo que falta y deja reintentar ("Falta deshacer algo") |
| PC de empresa o permisos: un ajuste de Windows falla | Los demás igual se aplican, y la pantalla dice cuál no se pudo |
| FiveM o el GTA (`GTA5`, `PlayGTAV`...) abiertos | No cambia gráficos ni limpia la caché |
| Windows tarda o se cuelga al responder | Las consultas tienen 10 s de límite. El optimizador completo tiene 60–300 s; después se corta solo y avisa |
| Doble clic o dos acciones juntas | Solo corre una a la vez (candado en `lib.rs`), y los botones se bloquean mientras tanto |
| Antivirus o política de Windows bloquean PowerShell | Mensaje claro en español que dice qué hacer |
| Configuración remota rota o maliciosa | Se limpia y valida: textos cortados, solo enlaces `https://`, código del servidor solo con letras y números |
| Cualquier error suelto en la pantalla | Aviso tranquilo; la ventana sigue funcionando |
| Disco donde no se puede reemplazar un archivo de una vez (USB, red) | Copia y borra el temporal |

Soporte: lo que hace el optimizador queda en `%APPDATA%\SaltoAngelLauncher\optimizador\registro.log` (máximo 256 KB).

**Pruebas automáticas:** `src-tauri/scripts/probar_optimizador.ps1` arma una PC de mentira en una carpeta con espacios, tildes y ñ, y prueba 33 casos. Entre ellos: restaurar deja el `settings.xml` idéntico, lo de solo lectura se respeta, no quedan temporales, con "FiveM" abierto no toca nada (usa un `ping.exe` renombrado) y no cierra programas fuera de la lista. **Resultado del 18/11: 33 de 33.** GitHub las corre antes de cada compilación junto con `node --check`, la validación de los JSON, la revisión de los `.ps1` (sintaxis y BOM) y `cargo clippy` con avisos como error. Si algo falla, no se arma el instalador. En una versión etiquetada tampoco puede quedar ningún `PENDIENTE`.
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src-tauri\scripts\probar_optimizador.ps1
```

## Probar el optimizador sin el launcher
El script se prueba solo, con una PC de mentira, sin tocar la de verdad:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src-tauri\scripts\optimizar.ps1 -Accion revisar -Raiz C:\prueba_opt -RegBase 'HKCU:\Software\SaltoAngelPrueba' -SinEnergia
```
`-Raiz` cambia Documentos y AppData por `C:\prueba_opt\Documents|Local|Roaming`, `-RegBase` manda el registro a una clave de prueba y `-SinEnergia` no toca el plan de energía. El 18/11 se probó así: aplicar extremo, cambiar a medio, restaurar (el `settings.xml` quedó idéntico y el registro volvió a sus valores), limpiar (`cache\game` intacto), cerrar con nombres no permitidos (no cierra nada) y aplicar sin `settings.xml` (avisa y no hace nada). **Falta probar en una PC de jugador:** el cambio real de plan de energía y la tarjeta de video en una laptop.

**Ojo:** el script tiene que quedar guardado en UTF-8 **con BOM**. Si no, Windows PowerShell 5.1 muestra mal las tildes de los mensajes.

## Revisar el diseño sin compilar
`.claude/launch.json` → `launcher` → `http://127.0.0.1:8900/`. En el navegador, los comandos nativos se simulan:
- `#sinfivem`: hace como si FiveM no estuviera instalado (sale la ventana para bajarlo).
- `#actualizacion`: muestra la franja de "versión nueva".

## Prueba paso a paso (con el instalador)
1. Abre el `-setup.exe`. Si sale "Windows protegió su PC": **Más información → Ejecutar de todas formas**. Se instala sin pedir administrador.
2. Abre **Salto Angel Launcher** desde el escritorio. Debe salir la ventana con el logo y, en "Servidor", **En línea** con los jugadores reales (compara con la lista de FiveM).
3. Arrastra la ventana desde la barra de arriba. Prueba minimizar y cerrar.
4. Ábrelo dos veces: la segunda vez solo trae al frente la primera.
5. **JUGAR**: se abre FiveM y conecta a Salto Ángel. El launcher se minimiza a los 2–3 s.
6. En una PC sin FiveM: JUGAR muestra "No encontramos FiveM" y "Bajar FiveM" abre fivem.net en el navegador.
7. **Discord** abre `discord.gg/EP7ZVHtQrU` en el navegador.
8. Desconecta el internet: el estado pasa a **Sin conexión** y el launcher no se cuelga.
9. Ajustes → apaga "Minimizar al darle a Jugar", cierra y abre: se queda apagado.
10. **Optimizar** (con FiveM cerrado): sale la revisión con semáforos. Activa el **modo extremo**: pide confirmación y queda "Activo". Abre FiveM, entra y compara los FPS (F8 → `cl_drawfps 1`). Cierra FiveM y dale a **Volver como estaba**: en el GTA deben estar tus gráficos de antes, y en Windows el plan de energía anterior.
11. Con FiveM abierto, Optimizar avisa "FiveM está abierto" y no deja aplicar.
12. Limpiar caché: muestra cuánto liberó, y la próxima entrada al servidor baja todo de nuevo.
13. Actualización: con la v0.1.0 instalada, publica una v0.1.1 de prueba, abre el launcher y debe salir la franja "Hay una versión nueva". "Actualizar ahora" la instala y se reinicia.
