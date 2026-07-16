fn main() {
    // NOTE: build.rs runs on the HOST, so #[cfg(windows)] on the HOST may not
    // match CARGO_CFG_TARGET_OS. Use the env var to gate Windows-only link-search.
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        let manifest = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let libmpv = manifest.join("libmpv");
        if libmpv.join("mpv.lib").exists() {
            println!("cargo:rustc-link-search=native={}", libmpv.display());
        } else {
            println!(
                "cargo:warning=src-tauri/libmpv/mpv.lib missing — run `npm run setup:desktop`"
            );
        }
    }
    tauri_build::build()
}
