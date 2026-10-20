import Foundation

public struct CacheRule: Sendable {
    public let relative:String; public let category:String; public let explanation:String; public let runningIDs:[String]
}
public enum CacheRules {
    public static let electronLeaves=["Cache","Code Cache","GPUCache","CachedData","DawnCache","DawnGraphiteCache","DawnWebGPUCache","Crashpad/completed","Service Worker/CacheStorage","Service Worker/ScriptCache"]
    public static var rules:[CacheRule] {
        var result:[CacheRule]=[]
        let electron:[(String,String,String)]=[
            ("Code","Developer artifacts","com.microsoft.VSCode"),("Cursor","AI tools","com.todesktop.230313mzl4w4u92"),("Claude","AI tools","com.anthropic.claudefordesktop"),("Codex","AI tools","com.openai.codex"),("com.openai.chat","AI tools","com.openai.chat"),("ai.opencode.desktop","AI tools","ai.opencode.desktop"),
            ("Slack","Communication","com.tinyspeck.slackmacgap"),("discord","Communication","com.hnc.Discord"),("Microsoft Teams","Communication","com.microsoft.teams2"),("Figma","Design tools","com.figma.Desktop"),("Notion","Productivity","notion.id"),("obsidian","Productivity","md.obsidian"),("Logseq","Productivity","com.electron.logseq")]
        for (folder,category,id) in electron { for leaf in electronLeaves { result.append(CacheRule(relative:"Library/Application Support/\(folder)/\(leaf)",category:category,explanation:"\(folder) generated \(leaf) data. Quit the app first. Offline resources may be fetched again; conversations, workspace settings and credentials are outside this rule.",runningIDs:[id])) } }
        for (path,category,detail) in [
            (".bun/install/cache","Developer artifacts","Bun downloaded package cache."),(".cargo/registry/cache","Developer artifacts","Rust downloaded registry archives; packages will download again."),(".gradle/caches","Developer artifacts","Gradle dependency and build cache. Close builds before cleanup."),(".m2/repository","Developer artifacts","Maven downloaded dependencies. Offline builds may no longer work."),
            ("Library/Caches/Homebrew/downloads","Developer artifacts","Homebrew downloaded archives. Installed packages are kept."),
            (".npm/_logs","Developer artifacts","npm diagnostic logs."),(".cache/opencode","AI tools","OpenCode generated cache. Conversations, projects and local models are outside this path."),
            ("Library/Developer/CoreSimulator/Caches","Developer artifacts","Simulator generated cache; devices and application data are kept."),
            ("Library/Developer/Xcode/Products","Developer artifacts","Xcode build products. Rebuild projects afterward."),
            ("Library/Caches/org.swift.swiftpm","Developer artifacts","Swift Package Manager cache."),
            ("Library/Application Support/Code/logs","Developer artifacts","Visual Studio Code diagnostic logs."),
            ("Library/Application Support/Code/CachedExtensionVSIXs","Developer artifacts","Downloaded editor extension installers."),
            ("Library/Application Support/Cursor/CachedExtensionVSIXs","AI tools","Downloaded editor extension installers."),
            ("Library/Developer/Xcode/iOS DeviceSupport","Developer artifacts","Device debugging symbols. Xcode may download them again."),
            (".cache/lm-studio","AI tools","Generated LM Studio cache; retain anything needed offline."),(".cache/tensorflow","AI tools","TensorFlow downloaded cache."),(".lmstudio/models","AI tools","Downloaded local models. High risk: offline models and large downloads may be lost."),(".ollama/models","AI tools","Ollama model blobs. Quit Ollama and retain models needed offline. Large downloads may be required."),
            ("Library/Application Support/Steam/logs","Misc","Steam diagnostic logs."),("Library/Application Support/Steam/appcache","Misc","Steam generated app cache. Close Steam first."),("Library/Application Support/Steam/htmlcache","Misc","Steam browser cache."),("Library/Application Support/Steam/shadercache","Misc","Generated shaders; initial game loads may be slower."),("Library/Application Support/Spotify/PersistentCache","Games & media","Spotify downloaded media cache. Offline availability may be lost.")
        ] { result.append(CacheRule(relative:path,category:category,explanation:detail,runningIDs:category=="AI tools" ? ["com.ollama.ollama","ai.elementlabs.lmstudio"] : ["Games & media","Misc"].contains(category) ? ["com.valvesoftware.steam","com.spotify.client"] : [])) }
        return result
    }
    public static func selectionRisk(category:String,relative:String)->String {
        if category=="Logs" {return "Low"}
        if ["Temporary files","Potential app leftovers","Old installers"].contains(category) {return "High"}
        if [".cache/huggingface/hub",".lmstudio/models",".ollama/models","Library/Developer/Xcode/Archives","Library/Developer/Xcode/iOS DeviceSupport"].contains(relative) {return "High"}
        if relative.contains("Service Worker/") {return "High"}
        return ["Application caches","Browsers","Games & media","Productivity","Misc","Cloud clients","Developer artifacts","AI tools","Communication","Design tools"].contains(category) ? "Review" : "High"
    }
    public static let chromium:[(String,String)]=[
        ("Google/Chrome","com.google.Chrome"),("Google/Chrome Beta","com.google.Chrome.beta"),("Chromium","org.chromium.Chromium"),("BraveSoftware/Brave-Browser","com.brave.Browser"),("Microsoft Edge","com.microsoft.edgemac"),("Vivaldi","com.vivaldi.Vivaldi"),("company.thebrowser.Browser","company.thebrowser.Browser"),("Dia","company.thebrowser.dia"),("net.imput.helium","net.imput.helium"),("com.operasoftware.Opera","com.operasoftware.Opera")]
    public static func browserCandidates(home:URL) throws -> [CacheRule] {
        var result:[CacheRule]=[]
        for (folder,id) in chromium {
            try Task.checkCancellation(); let relative="Library/Application Support/"+folder; let root=home.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath:root.path) else { continue }
            let identity=try Identity.read(root); guard identity.isDirectory,!identity.isSymlink else { continue }
            for profile in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) where profile.lastPathComponent=="Default" || profile.lastPathComponent.hasPrefix("Profile ") || profile.lastPathComponent=="Guest Profile" {
                let identity=try Identity.read(profile); guard identity.isDirectory,!identity.isSymlink else { continue }
                for leaf in ["Cache","Code Cache","GPUCache","Service Worker/CacheStorage","Service Worker/ScriptCache"] {
                    result.append(CacheRule(relative:relative+"/"+profile.lastPathComponent+"/"+leaf,category:"Browsers",explanation:"Generated \(folder) profile cache. Saved passwords, cookies, history and bookmarks are not targeted. Offline web apps may need network access again.",runningIDs:[id]))
                }
            }
        }
        return result
    }
}
