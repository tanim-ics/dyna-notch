import Foundation

/// Test-only environment switches (`DYNANOTCH_AGENT_DIR`, `DYNANOTCH_INSTALL_DIR`, `DYNANOTCH_DMG_AUTOCONFIRM`,
/// `DYNANOTCH_ZSHRC`, `DYNANOTCH_CLAUDE_SETTINGS`). They redirect files or press buttons, so a release build ignores
/// them: whoever launches the app can't make it auto-install a disk image or write hooks elsewhere (docs/SECURITY.md).
enum DebugEnvironment {
    static func value(_ name: String) -> String? {
        #if DEBUG
        let value = ProcessInfo.processInfo.environment[name]
        return value?.isEmpty == false ? value : nil
        #else
        return nil
        #endif
    }
}
