fn main() {
    tauri_plugin::Builder::new(&["status", "start", "end"])
        .ios_path("ios")
        .build();
}
