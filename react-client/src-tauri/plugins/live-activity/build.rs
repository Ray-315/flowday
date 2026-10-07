fn main() {
    tauri_plugin::Builder::new(&["status", "start", "end", "schedule"])
        .ios_path("ios")
        .build();
}
