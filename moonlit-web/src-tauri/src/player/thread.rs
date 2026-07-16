/// Player thread owning the libmpv handle (Windows-only).
/// Commands arrive via mpsc; mpv events are emitted as `mpv://event` Tauri events.
use serde_json::{json, Value};
use std::sync::mpsc::{Receiver, Sender};
use tauri::{AppHandle, Emitter};

#[derive(Debug)]
pub enum Cmd {
    Start(StartArgs),
    Stop,
    SetProp(String, Value),
    GetProp(String, Sender<Result<Value, String>>),
    Command(Vec<String>),
    SubAdd {
        url: String,
        title: Option<String>,
        lang: Option<String>,
        select: bool,
    },
    Screenshot {
        path: Option<String>,
        reply: Sender<Result<String, String>>,
    },
    Shutdown,
}

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StartArgs {
    pub url: String,
    pub start_at_sec: Option<f64>,
    pub headers: Option<std::collections::HashMap<String, String>>,
    pub wid: i64,
}

const OBSERVED: &[(&str, libmpv2::Format)] = &[
    ("time-pos", libmpv2::Format::Double),
    ("duration", libmpv2::Format::Double),
    ("pause", libmpv2::Format::Flag),
    ("eof-reached", libmpv2::Format::Flag),
    ("mute", libmpv2::Format::Flag),
    ("volume", libmpv2::Format::Double),
    ("speed", libmpv2::Format::Double),
    ("track-list", libmpv2::Format::String),
    ("sub-delay", libmpv2::Format::Double),
    ("audio-delay", libmpv2::Format::Double),
    ("demuxer-cache-time", libmpv2::Format::Double),
    ("video-params/aspect", libmpv2::Format::Double),
    ("paused-for-cache", libmpv2::Format::Flag),
];

fn emit(app: &AppHandle, payload: Value) {
    let _ = app.emit("mpv://event", payload);
}

/// Force C numeric locale — libmpv asserts on comma-decimal locales on Windows.
fn force_c_numeric_locale() {
    extern "C" {
        fn setlocale(category: i32, locale: *const std::ffi::c_char) -> *mut std::ffi::c_char;
    }
    const LC_NUMERIC: i32 = 4;
    unsafe {
        setlocale(LC_NUMERIC, c"C".as_ptr());
    }
}

fn j(data: libmpv2::events::PropertyData) -> Value {
    use libmpv2::events::PropertyData as P;
    match data {
        P::Double(d) => json!(d),
        P::Flag(b) => json!(b),
        P::String(s) => {
            // try to parse as JSON (e.g. track-list is a JSON array)
            serde_json::from_str::<Value>(s.as_ref()).unwrap_or_else(|_| json!(s.as_ref()))
        }
        P::Int64(i) => json!(i),
        P::Node(n) => json!(format!("{:?}", n)),
    }
}

fn end_reason_str(r: Option<libmpv2::EndFileReason>) -> String {
    use libmpv2::EndFileReason as E;
    match r {
        Some(E::Eof) => "Eof".into(),
        Some(E::Stop) => "Stop".into(),
        Some(E::Quit) => "Quit".into(),
        Some(E::Error) => "Error".into(),
        Some(E::Redirect) => "Redirect".into(),
        Some(E::Abort) => "Abort".into(),
        None => "Unknown".into(),
    }
}

pub fn run(app: AppHandle, rx: Receiver<Cmd>) {
    let mut mpv: Option<libmpv2::Mpv> = None;
    let mut pending_start_pos: Option<f64> = None;

    loop {
        while let Ok(cmd) = rx.try_recv() {
            match cmd {
                Cmd::Shutdown => {
                    drop(mpv.take());
                    return;
                }
                Cmd::Start(args) => {
                    drop(mpv.take());
                    force_c_numeric_locale();
                    let result = libmpv2::Mpv::with_initializer(|init| {
                        init.set_property("wid", args.wid)?;
                        init.set_property("vo", "gpu-next")?;
                        init.set_property("gpu-api", "d3d11")?;
                        init.set_property("hwdec", "auto-safe")?;
                        init.set_property("force-window", "immediate")?;
                        init.set_property("keep-open", "yes")?;
                        init.set_property("idle", "yes")?;
                        init.set_property("input-default-bindings", "no")?;
                        init.set_property("osc", "no")?;
                        init.set_property("osd-level", "0")?;
                        init.set_property("terminal", "no")?;
                        init.set_property("audio-client-name", "Moonlit")?;
                        init.set_property("user-agent", "Moonlit Desktop")?;
                        init.set_property("screenshot-format", "png")?;
                        if let Some(ref headers) = args.headers {
                            let fields: Vec<String> =
                                headers.iter().map(|(k, v)| format!("{k}: {v}")).collect();
                            if !fields.is_empty() {
                                init.set_property(
                                    "http-header-fields",
                                    fields.join(",").as_str(),
                                )?;
                            }
                        }
                        Ok(())
                    });
                    match result {
                        Ok(m) => {
                            for (name, fmt) in OBSERVED {
                                let _ = m.observe_property(name, *fmt, 0);
                            }
                            let _ = m.command("loadfile", &[&args.url, "replace"]);
                            pending_start_pos = args.start_at_sec;
                            mpv = Some(m);
                            emit(&app, json!({"event":"started"}));
                        }
                        Err(e) => emit(&app, json!({"event":"error","message": e.to_string()})),
                    }
                }
                Cmd::Stop => {
                    if let Some(ref m) = mpv {
                        let _ = m.command("stop", &[]);
                    }
                    drop(mpv.take());
                    emit(&app, json!({"event":"stopped"}));
                }
                Cmd::SetProp(name, value) => {
                    if let Some(ref m) = mpv {
                        let r: libmpv2::Result<()> = match &value {
                            Value::Bool(b) => m.set_property(&name, *b),
                            Value::Number(n) => {
                                if let Some(f) = n.as_f64() {
                                    m.set_property(&name, f)
                                } else if let Some(i) = n.as_i64() {
                                    m.set_property(&name, i)
                                } else {
                                    Err(libmpv2::Error::Generic(
                                        "non-numeric number".into(),
                                    ))
                                }
                            }
                            Value::String(s) => m.set_property(&name, s.as_str()),
                            _ => Err(libmpv2::Error::Generic("unsupported type".into())),
                        };
                        if let Err(e) = r {
                            emit(
                                &app,
                                json!({"event":"log","level":"warn","text": format!("set {name}: {e}")}),
                            );
                        }
                    }
                }
                Cmd::GetProp(name, reply) => {
                    let result = mpv
                        .as_ref()
                        .ok_or_else(|| "no player".to_string())
                        .and_then(|m| {
                            // Try String first (for track-list etc.), then f64, then Bool
                            m.get_property::<libmpv2::String>(&name)
                                .map(|s| json!(s.as_ref()))
                                .or_else(|_| {
                                    m.get_property::<f64>(&name).map(|v| json!(v))
                                })
                                .or_else(|_| {
                                    m.get_property::<bool>(&name).map(|v| json!(v))
                                })
                                .or_else(|_| {
                                    m.get_property::<i64>(&name).map(|v| json!(v))
                                })
                                .map_err(|e| e.to_string())
                        });
                    let _ = reply.send(result);
                }
                Cmd::Command(parts) => {
                    if let Some(ref m) = mpv {
                        if let Some((head, tail)) = parts.split_first() {
                            let refs: Vec<&str> = tail.iter().map(String::as_str).collect();
                            if let Err(e) = m.command(head, &refs) {
                                emit(
                                    &app,
                                    json!({"event":"log","level":"warn","text": format!("cmd {head}: {e}")}),
                                );
                            }
                        }
                    }
                }
                Cmd::SubAdd {
                    url,
                    title,
                    lang,
                    select,
                } => {
                    if let Some(ref m) = mpv {
                        let mode = if select { "select" } else { "auto" };
                        let title = title.unwrap_or_else(|| "External".into());
                        let lang = lang.unwrap_or_else(|| "und".into());
                        let _ = m.command("sub-add", &[&url, mode, &title, &lang]);
                    }
                }
                Cmd::Screenshot { path, reply } => {
                    let out = mpv
                        .as_ref()
                        .ok_or_else(|| "no player".to_string())
                        .and_then(|m| match &path {
                            Some(p) => m
                                .command("screenshot-to-file", &[p.as_str(), "video"])
                                .map(|()| p.clone())
                                .map_err(|e| e.to_string()),
                            None => Err("path required".into()),
                        });
                    let _ = reply.send(out);
                }
            }
        }

        if let Some(ref m) = mpv {
            match m.wait_event(0.05) {
                Some(Ok(ev)) => {
                    use libmpv2::events::Event as E;
                    match ev {
                        E::PropertyChange {
                            name,
                            change,
                            reply_userdata: _,
                        } => {
                            emit(
                                &app,
                                json!({"event":"property-change","name": name, "data": j(change)}),
                            );
                        }
                        E::EndFile(reason) => {
                            emit(
                                &app,
                                json!({"event":"end-file","reason": end_reason_str(reason)}),
                            );
                        }
                        E::FileLoaded => {
                            // Apply pending start position
                            if let Some(pos) = pending_start_pos.take() {
                                let _ = m.set_property("time-pos", pos);
                            }
                            emit(&app, json!({"event":"file-loaded"}));
                        }
                        E::PlaybackRestart => emit(&app, json!({"event":"playback-restart"})),
                        E::Seek => emit(&app, json!({"event":"seek"})),
                        E::Shutdown => emit(&app, json!({"event":"shutdown"})),
                        E::LogMessage {
                            prefix,
                            level,
                            text,
                            ..
                        } => {
                            emit(
                                &app,
                                json!({"event":"log","prefix":prefix,"level":level,"text":text}),
                            );
                        }
                        E::StartFile => {}
                        E::QueueOverflow => {}
                        _ => {
                            if cfg!(debug_assertions) {
                                emit(&app, json!({"event":"log","level":"debug","text": format!("mpv event: {ev:?}")}));
                            }
                        }
                    }
                }
                Some(Err(e)) => {
                    emit(
                        &app,
                        json!({"event":"log","level":"warn","text": e.to_string()}),
                    );
                }
                None => {} // timeout, no event ready
            }
        } else {
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
    }
}
