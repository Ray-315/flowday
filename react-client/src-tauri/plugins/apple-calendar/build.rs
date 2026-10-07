fn main() {
    // The shared Swift package lives outside ios_path; track it for both targets.
    println!("cargo:rerun-if-changed=../../apple-calendar-core");
    tauri_plugin::Builder::new(&["request"]).ios_path("ios").build();
    if std::env::var("CARGO_CFG_TARGET_OS").unwrap() == "macos" {
        swift_rs::SwiftLinker::new("11.0").with_package("FlowCalendarCore", "../../apple-calendar-core").link();
        println!("cargo:rustc-link-lib=framework=EventKit");
    }
}
