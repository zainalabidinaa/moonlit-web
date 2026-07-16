pub mod deeplink;
pub mod player;

#[cfg(windows)]
mod mpv_setup {
    use crate::player;

    pub fn init(builder: tauri::Builder<tauri::Wry>) -> tauri::Builder<tauri::Wry> {
        builder.setup(|app| {
            let (tx, rx) = std::sync::mpsc::channel();
            let handle = app.handle().clone();
            std::thread::Builder::new()
                .name("mpv-player".into())
                .spawn(move || player::thread::run(handle, rx))
                .expect("spawn player thread");
            use tauri::Manager;
            app.manage(player::PlayerState(parking_lot::Mutex::new(Some(tx))));
            Ok(())
        })
    }
}

pub fn run() {
    let mut builder = tauri::Builder::default();

    #[cfg(desktop)]
    {
        builder = builder.plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            use tauri::Manager;
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.set_focus();
            }
        }));
    }

    #[cfg(windows)]
    {
        builder = mpv_setup::init(builder);
    }

    let builder = {
        #[cfg(windows)]
        {
            builder.invoke_handler(tauri::generate_handler![
                player::mpv_probe,
                player::mpv_start,
                player::mpv_stop,
                player::mpv_set_property,
                player::mpv_get_property,
                player::mpv_command,
                player::mpv_sub_add,
                player::mpv_screenshot,
                player::mpv_set_geometry,
                player::shader_dir,
            ])
        }
        #[cfg(not(windows))]
        {
            builder.invoke_handler(tauri::generate_handler![
                player::mpv_probe,
                player::mpv_start,
                player::mpv_stop,
            ])
        }
    };

    builder
        .plugin(tauri_plugin_deep_link::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
