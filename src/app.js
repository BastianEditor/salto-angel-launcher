// Salto Ángel Launcher - lógica de la pantalla.
// Dentro del launcher usa los comandos de src-tauri/src/lib.rs. Abierto en un navegador (para revisar el diseño),
// simula esos comandos para que todo se pueda probar.
'use strict';

// Configuración remota: se cambia en GitHub (publicar/config.json) sin sacar versión nueva.
// Configuración remota (se edita en GitHub: publicar/config.json). Si no responde, se usa la que trae el launcher.
const CONFIG_REMOTA = 'https://raw.githubusercontent.com/BastianEditor/salto-angel-launcher/main/publicar/config.json';
const API_ESTADO = 'https://frontend.cfx-services.net/api/servers/single/';
const CADA_CUANTO = 30000; // estado del servidor cada 30 s
const PAGINA_FIVEM = 'https://fivem.net/';

const TAURI = window.__TAURI__ || null;
const $ = (id) => document.getElementById(id);

// ===== Puente con la parte nativa (o simulación en el navegador) =====
const simulado = {
    estado_fivem: async () => ({ instalado: !location.hash.includes('sinfivem'), abierto: false }),
    jugar: async () => {},
    abrir_enlace: async ({ url }) => { window.open(url, '_blank', 'noopener'); },
    version: async () => '0.1.0',
    buscar_actualizacion: async () => (location.hash.includes('actualizacion') ? { version: '0.2.0', notas: 'Modo extremo' } : null),
    instalar_actualizacion: async () => {},
    // PC inventada para ver todos los casos en el navegador (laptop con driver viejo y poco disco)
    optimizador: async ({ accion, perfil, windows, nombres }) => {
        await new Promise((r) => setTimeout(r, 700));
        const s = simulado._pc;
        if (accion === 'revisar') return Object.assign({ ok: true }, JSON.parse(JSON.stringify(s)));
        if (accion === 'cache') return { ok: true, cacheMB: s.fivem.cacheMB, abierto: false };
        if (accion === 'limpiar') { const l = s.fivem.cacheMB; s.fivem.cacheMB = 0; return { ok: true, liberadoMB: l, fallos: 0 }; }
        if (accion === 'aplicar') { s.optimizado = true; s.perfil = perfil; if (windows) { s.extremo = true; s.gameBarGraba = false; s.energia = { guid: '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', nombre: 'Alto rendimiento' }; } return { ok: true, perfil, graficos: { aplicado: true, cambiados: 32 }, windows: windows ? ['gpu', 'gamebar', 'modojuego', 'energia'] : [] }; }
        if (accion === 'restaurar') { Object.assign(s, { optimizado: false, perfil: '', extremo: false, gameBarGraba: true, energia: { guid: '381b4222-f694-41f0-9685-ff5bb260df2e', nombre: 'Equilibrado' } }); return { ok: true }; }
        if (accion === 'cerrar') { s.pesados = s.pesados.filter((p) => !(nombres || []).includes(p.nombre)); return { ok: true, cerrados: nombres }; }
        return { ok: false, error: 'Acción desconocida' };
    },
    _pc: {
        tarjetas: [{ nombre: 'Intel(R) UHD Graphics 620', driver: '27.20.100.8681', driverMeses: 30, vramMB: 1024 }, { nombre: 'NVIDIA GeForce MX150', driver: '31.0.15.1694', driverMeses: 19, vramMB: 2048 }],
        ramGB: 8, disco: { unidad: 'C:', libreGB: 14, totalGB: 237, ssd: true }, laptop: true,
        energia: { guid: '381b4222-f694-41f0-9685-ff5bb260df2e', nombre: 'Equilibrado' }, gameBarGraba: true,
        fivem: { instalado: true, abierto: false, cacheMB: 3480 }, settings: { existe: true },
        optimizado: false, perfil: '', extremo: false,
        pesados: [{ nombre: 'chrome', mb: 1830, cerrable: true }, { nombre: 'Discord', mb: 420, cerrable: false }, { nombre: 'Spotify', mb: 260, cerrable: true }],
    },
};
function llamar(cmd, args) {
    if (TAURI && TAURI.core) return TAURI.core.invoke(cmd, args || {});
    return simulado[cmd](args || {});
}
function ventana() {
    return TAURI && TAURI.window ? TAURI.window.getCurrentWindow() : null;
}

// ===== Preferencias de esta PC (si el almacenamiento falla, se usan los valores por defecto) =====
function leerPref(clave, porDefecto) {
    try { const v = localStorage.getItem('sa_' + clave); return v === null ? porDefecto : JSON.parse(v); } catch (e) { return porDefecto; }
}
function guardarPref(clave, valor) {
    try { localStorage.setItem('sa_' + clave, JSON.stringify(valor)); } catch (e) { /* sin almacenamiento */ }
}

// ===== Aviso flotante =====
let temporizadorToast;
function avisar(texto, opciones) {
    const o = opciones || {};
    const t = $('toast');
    t.replaceChildren();
    if (o.cargando) { const g = document.createElement('span'); g.className = 'giro'; t.appendChild(g); }
    const s = document.createElement('span'); s.textContent = texto; t.appendChild(s);
    t.classList.toggle('error', !!o.error);
    t.classList.add('ver');
    clearTimeout(temporizadorToast);
    temporizadorToast = setTimeout(() => t.classList.remove('ver'), o.duracion || 3200);
}

// ===== Configuración =====
let config = null;

const CONFIG_BASE = { servidor: { nombre: 'Salto Ángel', codigo: 'm4qzz8q', maxJugadores: 128 }, lema: '', aviso: '', enlaces: [{ id: 'discord', texto: 'Discord', url: 'https://discord.gg/EP7ZVHtQrU' }], noticias: [] };

function configValida(c) {
    return !!(c && typeof c === 'object' && c.servidor && typeof c.servidor.codigo === 'string' && /^[a-z0-9]{3,16}$/i.test(c.servidor.codigo));
}

// Deja la configuración siempre usable, venga como venga (textos cortados, tipos raros, campos que faltan)
function texto(v, max) { return typeof v === 'string' ? v.slice(0, max) : ''; }
function normalizarConfig(c) {
    if (!configValida(c)) return JSON.parse(JSON.stringify(CONFIG_BASE));
    const s = c.servidor;
    const max = Number(s.maxJugadores);
    return {
        servidor: { nombre: texto(s.nombre, 40) || 'Salto Ángel', codigo: s.codigo, maxJugadores: Number.isFinite(max) && max > 0 && max <= 2048 ? Math.round(max) : 128 },
        lema: texto(c.lema, 200),
        aviso: texto(c.aviso, 160),
        enlaces: (Array.isArray(c.enlaces) ? c.enlaces : []).filter((e) => e && typeof e === 'object').slice(0, 6)
            .map((e) => ({ id: texto(e.id, 20), texto: texto(e.texto, 24), url: texto(e.url, 300) })),
        noticias: (Array.isArray(c.noticias) ? c.noticias : []).filter((n) => n && typeof n === 'object').slice(0, 3)
            .map((n) => ({ fecha: texto(n.fecha, 12), tipo: texto(n.tipo, 10), etiqueta: texto(n.etiqueta, 20), titulo: texto(n.titulo, 60), texto: texto(n.texto, 140), url: texto(n.url, 300) })),
    };
}

async function cargarConfig() {
    let base = null;
    try {
        const r = await fetch('config.json', { cache: 'no-store' });
        base = await r.json();
    } catch (e) { /* se usa CONFIG_BASE */ }
    config = normalizarConfig(base);
    const guardada = leerPref('config_remota', null);
    if (configValida(guardada)) config = normalizarConfig(guardada);
    pintarConfig();

    try {
        const r = await fetchConTiempo(CONFIG_REMOTA + '?t=' + Date.now(), 8000);
        if (!r.ok) return;
        const remota = await r.json();
        if (!configValida(remota)) return;
        config = normalizarConfig(remota);
        guardarPref('config_remota', remota);
        pintarConfig();
    } catch (e) { /* sin internet o archivo roto: se queda la que había */ }
}

const ICONOS = {
    discord: '<svg class="ico" viewBox="0 0 24 24"><path d="M8 12h.01M16 12h.01"/><path d="M7 17c-2 0-4-1-4-1V7c0-1 3-3 5-3l1 2h6l1-2c2 0 5 2 5 3v9s-2 1-4 1l-1-2"/><path d="M8 15c2.5 1 5.5 1 8 0"/></svg>',
    normas: '<svg class="ico" viewBox="0 0 24 24"><path d="M12 3l8 4v5c0 5-3.5 8-8 9-4.5-1-8-4-8-9V7z"/></svg>',
    guia: '<svg class="ico" viewBox="0 0 24 24"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20V3H6.5A2.5 2.5 0 0 0 4 5.5z"/></svg>',
    web: '<svg class="ico" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/></svg>',
    tienda: '<svg class="ico" viewBox="0 0 24 24"><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><path d="M3 6h18M16 10a4 4 0 0 1-8 0"/></svg>',
};
const TIPOS_NOTICIA = ['oro', 'vio', 'verde', 'rojo'];

function enlaceSeguro(url) {
    return typeof url === 'string' && url.startsWith('https://') && url.length <= 300 && !/\s/.test(url);
}

function pintarConfig() {
    const s = config.servidor || {};
    $('nombre-servidor').textContent = s.nombre || 'Salto Ángel';
    $('lema').textContent = config.lema || '';
    $('dato-codigo').textContent = s.codigo || 'm4qzz8q';
    $('max').textContent = s.maxJugadores || 128;

    const aviso = (config.aviso || '').trim();
    $('banda-aviso').classList.toggle('oculto', !aviso);
    $('aviso-txt').textContent = aviso;

    const cajaEnlaces = $('enlaces');
    cajaEnlaces.replaceChildren();
    (config.enlaces || []).filter((e) => enlaceSeguro(e.url)).forEach((e) => {
        const b = document.createElement('button');
        b.className = 'chip' + (e.id === 'discord' ? ' discord' : '');
        b.innerHTML = ICONOS[e.id] || ICONOS.web; // íconos fijos nuestros, nunca texto de la configuración
        const t = document.createElement('span'); t.textContent = e.texto || 'Enlace'; b.appendChild(t);
        b.addEventListener('click', () => abrirEnlace(e.url, e.texto));
        cajaEnlaces.appendChild(b);
    });

    const cajaNoticias = $('noticias');
    cajaNoticias.replaceChildren();
    (config.noticias || []).slice(0, 3).forEach((n) => {
        const a = document.createElement('article');
        a.className = 'noticia' + (enlaceSeguro(n.url) ? ' con-enlace' : '');
        const fecha = document.createElement('span'); fecha.className = 'fecha'; fecha.textContent = n.fecha || '';
        const tag = document.createElement('span'); tag.className = 'tag ' + (TIPOS_NOTICIA.includes(n.tipo) ? n.tipo : 'oro'); tag.textContent = n.etiqueta || 'Noticia';
        const h = document.createElement('h3'); h.textContent = n.titulo || '';
        const p = document.createElement('p'); p.textContent = n.texto || '';
        a.append(fecha, tag, h, p);
        if (enlaceSeguro(n.url)) a.addEventListener('click', () => abrirEnlace(n.url, n.titulo));
        cajaNoticias.appendChild(a);
    });
}

async function abrirEnlace(url, nombre) {
    try {
        await llamar('abrir_enlace', { url });
        avisar('Abriendo ' + (nombre || 'el enlace') + ' en tu navegador');
    } catch (e) {
        avisar('No se pudo abrir el enlace', { error: true });
    }
}

// ===== Estado del servidor (API pública de Cfx.re, la misma lista de FiveM) =====
function fetchConTiempo(url, ms) {
    const control = new AbortController();
    const t = setTimeout(() => control.abort(), ms);
    return fetch(url, { signal: control.signal, cache: 'no-store' }).finally(() => clearTimeout(t));
}

let servidorPrendido = null;
let animacionJug;

function pintarEstado(clase, texto, jugadores, max) {
    const pill = $('pill');
    pill.className = 'pill ' + clase;
    $('pill-txt').textContent = texto;
    const el = $('jug');
    clearInterval(animacionJug);
    if (jugadores === null) { el.textContent = '–'; $('barra').style.width = '0%'; return; }
    $('max').textContent = max;
    $('barra').style.width = Math.max(jugadores > 0 ? 2 : 0, Math.min(100, jugadores / max * 100)) + '%';
    const desde = parseInt(el.textContent, 10) || 0;
    let n = desde; const paso = Math.max(1, Math.ceil(Math.abs(jugadores - desde) / 25));
    animacionJug = setInterval(() => {
        n = n < jugadores ? Math.min(jugadores, n + paso) : Math.max(jugadores, n - paso);
        el.textContent = n;
        if (n === jugadores) clearInterval(animacionJug);
    }, 30);
}

async function revisarServidor() {
    const codigo = (config && config.servidor && config.servidor.codigo) || 'm4qzz8q';
    const max = (config && config.servidor && config.servidor.maxJugadores) || 128;
    try {
        const r = await fetchConTiempo(API_ESTADO + encodeURIComponent(codigo), 8000);
        if (r.status === 404) { servidorPrendido = false; pintarEstado('off', 'Apagado', 0, max); $('fuente').textContent = 'Puede estar reiniciando. Prueba en unos minutos.'; return; }
        if (!r.ok) throw new Error('http ' + r.status);
        const d = (await r.json()).Data || {};
        const visto = Date.parse(d.lastSeen || '');
        const reciente = !visto || (Date.now() - visto) < 5 * 60 * 1000;
        servidorPrendido = reciente;
        const total = Number(d.sv_maxclients || d.svMaxclients || max);
        if (reciente) pintarEstado('on', 'En línea', Number(d.clients || 0), total);
        else pintarEstado('off', 'Apagado', 0, total);
        $('fuente').textContent = 'En vivo · se actualiza cada 30 s';
    } catch (e) {
        servidorPrendido = null;
        pintarEstado('sinred', 'Sin conexión', null);
        $('fuente').textContent = 'No pudimos revisar el servidor. ¿Tienes internet?';
    }
}

// ===== FiveM =====
async function revisarFivem() {
    try {
        const e = await llamar('estado_fivem');
        const b = $('dato-fivem');
        b.textContent = e.instalado ? (e.abierto ? 'Abierto' : 'Instalado ✓') : 'No encontrado';
        b.className = e.instalado ? 'bien' : 'mal';
        return e;
    } catch (err) {
        return { instalado: true, abierto: false }; // si no se puede revisar, no bloqueamos
    }
}

async function conectar() {
    const boton = $('jugar'), texto = $('jugar-txt');
    boton.classList.add('ocupado'); texto.textContent = 'ABRIENDO FIVEM…';
    avisar('Abriendo FiveM y conectando a ' + ((config.servidor && config.servidor.nombre) || 'Salto Ángel') + '…', { cargando: true, duracion: 5000 });
    try {
        await llamar('jugar', { codigo: (config.servidor && config.servidor.codigo) || '' });
        if (leerPref('minimizar', true) && ventana()) setTimeout(() => ventana().minimize(), 2500);
    } catch (e) {
        avisar('No se pudo abrir FiveM. Revisa que esté instalado.', { error: true, duracion: 5000 });
    } finally {
        setTimeout(() => { boton.classList.remove('ocupado'); texto.textContent = 'JUGAR'; }, 3000);
    }
}

async function alJugar() {
    const e = await revisarFivem();
    if (!e.instalado) { $('modal-fivem').classList.remove('oculto'); return; }
    if (servidorPrendido === false) avisar('El servidor parece apagado o reiniciando. Igual te intentamos conectar.', { duracion: 4500 });
    conectar();
}

// ===== Actualizaciones =====
async function buscarActualizacion(manual) {
    try {
        const info = await llamar('buscar_actualizacion');
        if (info && info.version) {
            $('act-ver').textContent = 'v' + info.version;
            $('banda-act').classList.remove('oculto');
            if (manual) avisar('Hay una versión nueva: v' + info.version);
        } else if (manual) {
            avisar('Ya tienes la última versión');
        }
    } catch (e) {
        if (manual) avisar('No se pudo revisar si hay versión nueva', { error: true });
    }
}

async function instalarActualizacion() {
    $('act-instalar').disabled = true;
    avisar('Bajando la versión nueva… el launcher se reinicia solo', { cargando: true, duracion: 60000 });
    try {
        await llamar('instalar_actualizacion');
    } catch (e) {
        $('act-instalar').disabled = false;
        avisar('No se pudo actualizar. Prueba más tarde.', { error: true });
    }
}

// ===== Optimizar mi PC (src-tauri/scripts/optimizar.ps1) =====
const PLAN_ALTO = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c';
const PLAN_MAXIMO = 'e9a42b02-d5df-448d-aa00-03f14749eb61';
const NOMBRE_PERFIL = { extremo: 'Extremo', bajo: 'Bajo', medio: 'Medio', alto: 'Alto' };
const FPS_DEL_PERFIL = { extremo: 'Bajo', bajo: 'Bajo', medio: 'Medio', alto: 'Alto' };
const NOMBRE_PROGRAMA = { chrome: 'Google Chrome', msedge: 'Microsoft Edge', firefox: 'Firefox', opera: 'Opera', brave: 'Brave', Spotify: 'Spotify', obs64: 'OBS', obs32: 'OBS', Discord: 'Discord (apaga su overlay)', steamwebhelper: 'Steam (navegador interno)' };
let pc = null;            // última revisión
let perfilElegido = null; // el que marcó el jugador
let ocupadoOpt = false;

async function opt(accion, extra) {
    const r = await llamar('optimizador', Object.assign({ accion }, extra || {}));
    if (!r || r.ok === false) throw new Error((r && r.error) || 'No se pudo completar');
    return r;
}

function esIntegrada(nombre) { return /intel|uhd|iris|vega \d|radeon\(tm\) graphics|radeon graphics/i.test(nombre || ''); }

function perfilRecomendado(p) {
    const tarjetas = p.tarjetas || [];
    const dedicada = tarjetas.find((t) => !esIntegrada(t.nombre));
    if (!dedicada || p.ramGB < 8) return 'extremo';
    if (p.ramGB < 12 || /mx\s?\d|gt\s?\d|rx\s?5[0-6]0|gtx\s?(7|9)\d\d|gtx\s?10[35]0/i.test(dedicada.nombre)) return 'bajo';
    if (/rtx\s?(30[6-9]0|40\d0|50\d0)|rx\s?(6[7-9]|7[7-9])\d\d/i.test(dedicada.nombre) && p.ramGB >= 16) return 'alto';
    return 'medio';
}

function pagDriver(nombre) {
    if (/nvidia|geforce/i.test(nombre)) return 'https://www.nvidia.com/es-la/drivers/';
    if (/amd|radeon/i.test(nombre)) return 'https://www.amd.com/es/support/download/drivers.html';
    if (/intel/i.test(nombre)) return 'https://www.intel.la/content/www/xl/es/support/detect.html';
    return '';
}

function agregarCheck(caja, nivel, titulo, detalle, valor) {
    const fila = document.createElement('div'); fila.className = 'check';
    const punto = document.createElement('span'); punto.className = 'punto p-' + nivel;
    const q = document.createElement('div'); q.className = 'q'; q.textContent = titulo;
    if (detalle) { const s = document.createElement('small'); s.textContent = detalle; q.appendChild(s); }
    const v = document.createElement('span'); v.className = 'v'; v.textContent = valor;
    fila.append(punto, q, v); caja.appendChild(fila);
}

function pintarRevision(p) {
    const caja = $('checks'); caja.replaceChildren();
    const tarjetas = p.tarjetas || [];
    const dedicada = tarjetas.find((t) => !esIntegrada(t.nombre));
    const principal = dedicada || tarjetas[0];

    // Tarjeta de video
    if (!principal) agregarCheck(caja, 'nd', 'Tarjeta de video', 'No pudimos leerla', '—');
    else if (!dedicada) agregarCheck(caja, 'av', 'Tarjeta de video', principal.nombre + ' (integrada). Usa el modo extremo.', 'Débil');
    else agregarCheck(caja, 'ok', 'Tarjeta de video', dedicada.nombre + (tarjetas.length > 1 ? ' · el modo extremo hace que FiveM la use siempre' : ''), 'Bien');

    // Driver
    const btnDriver = $('rev-driver');
    btnDriver.classList.add('oculto');
    if (principal && principal.driverMeses !== null && principal.driverMeses !== undefined) {
        const viejo = principal.driverMeses >= 12;
        agregarCheck(caja, viejo ? 'av' : 'ok', 'Driver de video', viejo ? 'Tiene ' + principal.driverMeses + ' meses. Actualizarlo da más FPS y menos crasheos.' : 'Al día (' + principal.driverMeses + ' meses)', viejo ? 'Actualizar' : 'Bien');
        const url = pagDriver(principal.nombre);
        if (viejo && url) { btnDriver.classList.remove('oculto'); btnDriver.onclick = () => abrirEnlace(url, 'la página oficial del driver'); }
    }

    // RAM
    if (p.ramGB) {
        const nivel = p.ramGB < 8 ? 'mal' : p.ramGB < 12 ? 'av' : 'ok';
        agregarCheck(caja, nivel, 'Memoria RAM', p.ramGB + ' GB · ' + (nivel === 'ok' ? 'suficiente para la ciudad' : nivel === 'av' ? 'justa: cierra programas antes de jugar' : 'muy poca: usa el modo extremo'), nivel === 'ok' ? 'Bien' : nivel === 'av' ? 'Justa' : 'Poca');
    }

    // Disco
    if (p.disco) {
        const d = p.disco;
        const nivel = d.libreGB < 20 ? 'mal' : (d.libreGB < 40 || d.ssd === false) ? 'av' : 'ok';
        let txt = 'Quedan ' + d.libreGB + ' GB libres en ' + d.unidad + '.';
        if (d.libreGB < 20) txt += ' Libera al menos 20 GB.';
        if (d.ssd === false) txt += ' Es un disco mecánico: el GTA en un SSD carga mucho más rápido.';
        agregarCheck(caja, nivel, 'Espacio en disco', txt, nivel === 'ok' ? 'Bien' : nivel === 'mal' ? 'Poco' : 'Ojo');
    }

    // Energía
    if (p.energia) {
        const bueno = p.energia.guid === PLAN_ALTO || p.energia.guid === PLAN_MAXIMO || p.extremo;
        agregarCheck(caja, bueno ? 'ok' : 'av', 'Plan de energía', '"' + (p.energia.nombre || 'Desconocido') + '"' + (bueno ? '' : (p.laptop ? '. En laptop conviene Alto rendimiento (conectada a la corriente).' : '. Alto rendimiento ayuda un poco.')), bueno ? 'Bien' : 'Cambiar');
    }

    // Game Bar
    agregarCheck(caja, p.gameBarGraba ? 'av' : 'ok', 'Grabación de Xbox Game Bar', p.gameBarGraba ? 'Está grabando en segundo plano y roba FPS.' : 'Apagada', p.gameBarGraba ? 'Apagar' : 'Bien');

    // Programas pesados
    const pes = p.pesados || [];
    $('pesados').classList.toggle('oculto', pes.length === 0);
    const lista = $('pes-lista'); lista.replaceChildren();
    pes.forEach((x) => {
        const fila = document.createElement('label'); fila.className = 'pes' + (x.cerrable ? '' : ' fijo');
        const caja2 = document.createElement('input'); caja2.type = 'checkbox'; caja2.value = x.nombre; caja2.disabled = !x.cerrable;
        caja2.addEventListener('change', () => { $('pes-cerrar').disabled = !lista.querySelector('input:checked'); });
        const n = document.createElement('span'); n.textContent = NOMBRE_PROGRAMA[x.nombre] || x.nombre;
        const mb = document.createElement('small'); mb.textContent = (x.mb >= 1024 ? (x.mb / 1024).toFixed(1) + ' GB' : x.mb + ' MB');
        fila.append(caja2, n, mb); lista.appendChild(fila);
    });
    $('pes-cerrar').disabled = true;

    const hora = new Date().toLocaleTimeString('es-VE', { hour: 'numeric', minute: '2-digit' });
    $('rev-cuando').textContent = 'Revisada a las ' + hora + (p.laptop ? ' · laptop' : '');
}

function pintarOptimizar() {
    if (!pc) return;
    const abierto = pc.fivem && pc.fivem.abierto;
    $('opt-fivem-abierto').classList.toggle('oculto', !abierto);

    // Modo extremo
    const on = !!pc.extremo;
    $('extremo').classList.toggle('on', on);
    $('ext-estado').textContent = pc.pendiente ? 'Falta deshacer algo' : on ? 'Activo' : (pc.optimizado ? (pc.perfil ? 'Perfil ' + (NOMBRE_PERFIL[pc.perfil] || '') : 'Con cambios') : 'Apagado');
    $('ext-boton').textContent = on ? 'ACTIVO ✓' : 'ACTIVAR';
    $('ext-boton').disabled = ocupadoOpt || on;
    $('ext-volver').disabled = ocupadoOpt || !pc.optimizado;

    // Perfiles
    const rec = perfilRecomendado(pc);
    if (!perfilElegido) perfilElegido = pc.perfil || rec;
    document.querySelectorAll('.perfil').forEach((b) => {
        const p = b.dataset.perfil;
        b.classList.toggle('sel', p === perfilElegido);
        b.classList.toggle('actual', p === pc.perfil);
        b.classList.toggle('rec', p === rec);
    });
    $('fps-rec').textContent = '/fps → ' + FPS_DEL_PERFIL[perfilElegido];
    $('perfil-aplicar').disabled = ocupadoOpt || !pc.settings || !pc.settings.existe || perfilElegido === pc.perfil;
    $('perfil-aplicar').textContent = (!pc.settings || !pc.settings.existe) ? 'Abre el GTA una vez' : 'Aplicar ' + NOMBRE_PERFIL[perfilElegido];

    // Caché
    const mb = (pc.fivem && pc.fivem.cacheMB) || 0;
    const caja = $('cache-mb'); caja.replaceChildren();
    caja.append(document.createTextNode(mb >= 1024 ? (mb / 1024).toFixed(1).replace('.', ',') : String(mb)));
    const u = document.createElement('small'); u.textContent = mb >= 1024 ? ' GB' : ' MB'; caja.appendChild(u);
    $('cache-limpiar').disabled = ocupadoOpt || mb === 0;
}

async function revisarPC() {
    if (ocupadoOpt) return; // mientras se aplica un cambio no se revisa encima
    $('rev-cuando').textContent = 'Revisando…';
    try {
        pc = await opt('revisar');
        pintarRevision(pc);
        pintarOptimizar();
    } catch (e) {
        $('rev-cuando').textContent = 'No se pudo revisar: ' + e.message;
    }
}

// Ventana de confirmación (devuelve true si el jugador acepta)
function confirmar(titulo, texto, puntos) {
    return new Promise((resolver) => {
        $('conf-titulo').textContent = titulo;
        $('conf-texto').textContent = texto;
        const ul = $('conf-lista'); ul.replaceChildren();
        (puntos || []).forEach((t) => { const li = document.createElement('li'); li.textContent = t; ul.appendChild(li); });
        const modal = $('modal-confirmar');
        modal.classList.remove('oculto');
        const cerrar = (valor) => { modal.classList.add('oculto'); $('conf-si').onclick = null; $('conf-no').onclick = null; resolver(valor); };
        $('conf-si').onclick = () => cerrar(true);
        $('conf-no').onclick = () => cerrar(false);
    });
}

const NOMBRE_AJUSTE = { gpu: 'la tarjeta de video', gamebar: 'apagar Game Bar', modojuego: 'el Modo juego', energia: 'el plan de energía' };
function explicarFallos(r) {
    const f = (r && Array.isArray(r.fallos)) ? r.fallos : [];
    return f.map((x) => NOMBRE_AJUSTE[x] || x).join(', ');
}

async function conCarga(texto, fn) {
    ocupadoOpt = true; pintarOptimizar();
    avisar(texto, { cargando: true, duracion: 60000 });
    try { return await fn(); } finally { ocupadoOpt = false; }
}

async function activarExtremo() {
    if (!pc) return;
    if (pc.fivem && pc.fivem.abierto) { avisar('Cierra FiveM primero', { error: true }); return; }
    const puntos = ['Gráficos del GTA al mínimo y distancia de dibujo mínima', 'Plan de energía Alto rendimiento', 'Apagar la grabación de Xbox Game Bar y activar el Modo juego'];
    if ((pc.tarjetas || []).length > 1 || pc.laptop) puntos.splice(1, 0, 'Que FiveM use siempre tu tarjeta de video potente');
    const si = await confirmar('¿Activar el modo extremo?', 'Esto es lo que se cambia. Antes se guarda una copia de todo, y con "Volver como estaba" queda igual que ahora.', puntos);
    if (!si) return;
    try {
        const r = await conCarga('Respaldando y aplicando el modo extremo…', () => opt('aplicar', { perfil: 'extremo', windows: true }));
        perfilElegido = 'extremo';
        const faltan = explicarFallos(r);
        if (faltan) avisar('Modo extremo activo, pero no se pudo: ' + faltan + '. Lo demás quedó bien.', { duracion: 7000 });
        else if (r.graficos && !r.graficos.aplicado) avisar('Se aplicó lo de Windows. Los gráficos no: ' + (r.graficos.motivo || 'abre el GTA una vez'), { duracion: 7000 });
        else avisar('Modo extremo activo. En el juego usa /fps → Bajo', { duracion: 5000 });
    } catch (e) {
        avisar(e.message, { error: true, duracion: 6000 });
    }
    revisarPC();
}

async function aplicarPerfil() {
    if (!pc || !perfilElegido) return;
    if (pc.fivem && pc.fivem.abierto) { avisar('Cierra FiveM primero', { error: true }); return; }
    try {
        await conCarga('Aplicando el perfil ' + NOMBRE_PERFIL[perfilElegido] + '…', () => opt('aplicar', { perfil: perfilElegido, windows: false }));
        avisar('Perfil ' + NOMBRE_PERFIL[perfilElegido] + ' aplicado. Tu configuración anterior quedó respaldada.', { duracion: 4500 });
    } catch (e) {
        avisar(e.message, { error: true, duracion: 6000 });
    }
    revisarPC();
}

async function volverComoEstaba() {
    const si = await confirmar('¿Volver como estaba?', 'Se devuelven tus gráficos del GTA, el plan de energía y los ajustes de Windows a como estaban antes del primer cambio.');
    if (!si) return;
    try {
        const r = await conCarga('Devolviendo todo como estaba…', () => opt('restaurar'));
        perfilElegido = null;
        if ((r.avisos || []).includes('respaldo_perdido')) avisar('Listo. Ojo: la copia de tus gráficos se había borrado, así que esos quedan como están ahora.', { duracion: 7000 });
        else avisar('Listo: todo quedó como estaba antes', { duracion: 4000 });
    } catch (e) {
        avisar(e.message, { error: true, duracion: 6000 });
    }
    revisarPC();
}

async function limpiarCache() {
    if (pc && pc.fivem && pc.fivem.abierto) { avisar('Cierra FiveM primero', { error: true }); return; }
    const si = await confirmar('¿Limpiar la caché de FiveM?', 'Se borran los archivos que FiveM bajó del servidor. La próxima vez que entres los vuelve a bajar (tarda un poco más). No se borra nada del GTA.');
    if (!si) return;
    try {
        const r = await conCarga('Limpiando la caché…', () => opt('limpiar'));
        const mb = r.liberadoMB || 0;
        avisar('Caché limpia: se liberaron ' + (mb >= 1024 ? (mb / 1024).toFixed(1).replace('.', ',') + ' GB' : mb + ' MB'), { duracion: 4500 });
    } catch (e) {
        avisar(e.message, { error: true, duracion: 6000 });
    }
    revisarPC();
}

async function cerrarPesados() {
    const nombres = Array.from(document.querySelectorAll('#pes-lista input:checked')).map((c) => c.value);
    if (!nombres.length) return;
    const si = await confirmar('¿Cerrar estos programas?', 'Guarda lo que tengas abierto en ellos antes. Se cierran de una vez.', nombres.map((n) => NOMBRE_PROGRAMA[n] || n));
    if (!si) return;
    try {
        await opt('cerrar', { nombres });
        avisar('Programas cerrados');
    } catch (e) {
        avisar(e.message, { error: true });
    }
    revisarPC();
}

// ===== Navegación y botones =====
let optimizarAbierto = false;
function irA(vista) {
    document.querySelectorAll('.nav[data-vista]').forEach((n) => n.classList.toggle('activo', n.dataset.vista === vista));
    document.querySelectorAll('.vista').forEach((v) => v.classList.toggle('activa', v.id === 'v-' + vista));
    if (vista === 'optimizar' && !optimizarAbierto) { optimizarAbierto = true; revisarPC(); }
}

function iniciar() {
    document.querySelectorAll('.nav[data-vista]').forEach((b) => b.addEventListener('click', () => irA(b.dataset.vista)));
    $('btn-min').addEventListener('click', () => { if (ventana()) ventana().minimize(); });
    $('btn-cerrar').addEventListener('click', () => { if (ventana()) ventana().close(); else avisar('En el launcher esto cierra la ventana'); });
    $('jugar').addEventListener('click', alJugar);

    $('modal-bajar').addEventListener('click', () => { $('modal-fivem').classList.add('oculto'); abrirEnlace(PAGINA_FIVEM, 'la página de FiveM'); });
    $('modal-igual').addEventListener('click', () => { $('modal-fivem').classList.add('oculto'); conectar(); });
    $('modal-cerrar').addEventListener('click', () => $('modal-fivem').classList.add('oculto'));
    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape') return;
        $('modal-fivem').classList.add('oculto');
        if (!$('modal-confirmar').classList.contains('oculto')) $('conf-no').click();
    });

    const minimizar = $('aj-minimizar');
    minimizar.checked = !!leerPref('minimizar', true);
    minimizar.addEventListener('change', () => guardarPref('minimizar', minimizar.checked));
    $('aj-buscar').addEventListener('click', () => buscarActualizacion(true));
    $('aj-fivem').addEventListener('click', () => abrirEnlace(PAGINA_FIVEM, 'la página de FiveM'));
    $('act-instalar').addEventListener('click', instalarActualizacion);

    $('ext-boton').addEventListener('click', activarExtremo);
    $('ext-volver').addEventListener('click', volverComoEstaba);
    $('perfil-aplicar').addEventListener('click', aplicarPerfil);
    $('cache-limpiar').addEventListener('click', limpiarCache);
    $('rev-otra').addEventListener('click', revisarPC);
    $('pes-cerrar').addEventListener('click', cerrarPesados);
    document.querySelectorAll('.perfil').forEach((b) => b.addEventListener('click', () => { perfilElegido = b.dataset.perfil; pintarOptimizar(); }));

    // El menú del clic derecho del navegador no pinta nada en un launcher
    document.addEventListener('contextmenu', (e) => e.preventDefault());

    llamar('version').then((v) => { $('version').textContent = 'v' + v; $('aj-version').textContent = 'v' + v; }).catch(() => {});
    cargarConfig().then(() => { revisarServidor(); setInterval(revisarServidor, CADA_CUANTO); });
    revisarFivem();
    setTimeout(() => buscarActualizacion(false), 3000);
}

// Red de seguridad: cualquier error que se escape se muestra con calma y la ventana sigue funcionando
window.addEventListener('error', () => { try { avisar('Algo salió mal, pero puedes seguir usando el launcher.', { error: true }); } catch (e) { /* nada */ } });
window.addEventListener('unhandledrejection', (ev) => { ev.preventDefault(); try { avisar('Algo salió mal, pero puedes seguir usando el launcher.', { error: true }); } catch (e) { /* nada */ } });

document.addEventListener('DOMContentLoaded', () => {
    try { iniciar(); } catch (e) { avisar('El launcher abrió con un problema. Ciérralo y ábrelo otra vez.', { error: true, duracion: 8000 }); }
});
