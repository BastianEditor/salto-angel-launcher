// En la versión final no se abre la consola negra de Windows junto al launcher
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    salto_angel_launcher_lib::run()
}
