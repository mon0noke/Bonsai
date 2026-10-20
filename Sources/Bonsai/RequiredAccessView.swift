import SwiftUI
import BonsaiCore

struct RequiredAccessView:View {
    @EnvironmentObject var model:AppModel
    let need:FileAccessNeed
    private var title:String {
        switch need.route {
        case .administrator:return "Application folder unavailable"
        case .filePermissions:return "This folder is locked"
        case .systemProtection:return "This location is still restricted"
        case .fullDiskAccess:return "Allow access to protected folders"
        case .filesAndFolders:return "Allow access to this folder"
        }
    }
    private var explanation:String {
        switch need.route {
        case .administrator:return "This private application folder is skipped. Other cleaning can continue without administrator access. Unverified app leftovers are left untouched."
        case .filePermissions:return "The folder’s file permissions block your account. Full Disk Access does not override those permissions. Inspect Sharing & Permissions in Finder, or leave this folder out of the scan."
        case .systemProtection:return "Bonsai can read the checked protected personal folders. This location is still restricted by macOS, its file permissions, or an access control list. Its unreadable contents stay unmeasured. Full Disk Access does not grant access to every system location."
        case .fullDiskAccess:return "Enable Bonsai in System Settings → Privacy & Security → Full Disk Access. If needed, add /Applications/Bonsai.app. Complete macOS’s Quit & Reopen step, then scan again."
        case .filesAndFolders:return "Choose this folder or its parent in the macOS folder picker, or enable its access in System Settings → Privacy & Security → Files & Folders. Then retry the scan."
        }
    }
    @ViewBuilder var body:some View {
        if need.operation == "Analyze scan" {diskAccess} else {details}
    }
    private var diskAccess:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Allow access to map your disk?").font(.system(size:20,weight:.semibold,design:.rounded))
            Text(need.route == .fullDiskAccess ? "Enable Full Disk Access for Bonsai to include protected data." : need.route == .filesAndFolders ? "Choose the folder to include it in your disk map." : "This location is restricted. You can continue without it.").foregroundStyle(Palette.muted)
            if !model.accessMessage.isEmpty {Text(model.accessMessage).font(.system(size:12)).foregroundStyle(Palette.muted)}
            HStack {
                Button("Not now") {model.accessRequest=nil}.buttonStyle(QuietTextStyle()).handCursor().keyboardShortcut(.cancelAction)
                Spacer()
                switch need.route {
                case .fullDiskAccess:
                    Button("Grant Access") {model.accessRequest=nil;model.settings()}.buttonStyle(SoftCapsuleStyle()).handCursor()
                case .filesAndFolders:
                    Button("Allow Access",action:model.choosePermissionFolder).buttonStyle(SoftCapsuleStyle()).handCursor()
                case .administrator,.filePermissions,.systemProtection:
                    Button("Retry",action:model.retryRequestedAccess).buttonStyle(SoftCapsuleStyle()).handCursor().disabled(!model.canNavigateDisk)
                }
            }
        }.padding(26).frame(width:420).background(Palette.background).bonsaiAppearance()
    }
    private var details:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(spacing:12) {
                Image(systemName:need.route == .administrator ? "person.badge.key.fill":"folder.badge.questionmark").font(.system(size:25)).foregroundStyle(Palette.sage).accessibilityHidden(true)
                Text(title).font(.system(size:21,weight:.semibold))
                Spacer()
                Button {model.accessRequest=nil} label: {Image(systemName:"xmark")}.handCursor().buttonStyle(QuietIconStyle()).accessibilityLabel("Close permissions").keyboardShortcut(.cancelAction)
            }
            Text(need.operation).font(.system(size:12,weight:.semibold)).foregroundStyle(Palette.muted)
            Text(need.url.path.replacingOccurrences(of:FileManager.default.homeDirectoryForCurrentUser.path,with:"~")).font(.system(size:11,design:.monospaced)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true).padding(12).frame(maxWidth:.infinity,alignment:.leading).quietSurface(radius:10)
            Text(explanation).font(.system(size:13)).fixedSize(horizontal:false,vertical:true)
            if !model.accessMessage.isEmpty {Text(model.accessMessage).font(.system(size:12)).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)}
            HStack {
                Button("Not now") {model.accessRequest=nil}.handCursor().buttonStyle(QuietTextStyle())
                Spacer()
                switch need.route {
                case .administrator:
                    Button("Reveal in Finder") {model.reveal(need.url)}.handCursor().buttonStyle(SoftCapsuleStyle())
                case .filePermissions,.systemProtection:
                    Button("Reveal in Finder") {model.reveal(need.url)}.handCursor().buttonStyle(SoftCapsuleStyle())
                    Button("Retry scan",action:model.retryRequestedAccess).handCursor().bonsaiPrimary().disabled(model.busy)
                case .fullDiskAccess:
                    Button("Retry scan",action:model.retryRequestedAccess).handCursor().buttonStyle(SoftCapsuleStyle()).disabled(model.busy)
                    Button("Open Full Disk Access") {model.settings()}.handCursor().bonsaiPrimary()
                case .filesAndFolders:
                    Button("Files & Folders") {model.settings("Privacy_FilesAndFolders")}.handCursor().buttonStyle(SoftCapsuleStyle())
                    Button("Allow folder…",action:model.choosePermissionFolder).handCursor().bonsaiPrimary()
                }
            }
        }.padding(26).frame(width:600).background(Palette.background).bonsaiAppearance()
    }
}
