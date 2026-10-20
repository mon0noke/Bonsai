import SwiftUI
import BonsaiCore

struct FileAccessPanel:View {
    @EnvironmentObject var model:AppModel
    @ViewState private var report:FileAccessReport?
    @ViewState private var checking=false
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Access to protected folders").font(.headline)
            Text("Full Disk Access lets Bonsai measure protected app folders and report more complete sizes. Enable Bonsai in System Settings → Privacy & Security → Full Disk Access. If it is missing, use + and choose /Applications/Bonsai.app.").secondaryText()
            HStack {Button("Open Full Disk Access") {model.settings()}.handCursor();Button("Files & Folders") {model.settings("Privacy_FilesAndFolders")}.handCursor();Spacer();Button(checking ? "Checking…" : "Check access",action:check).handCursor().disabled(checking)}
            if let report {
                Text(report.summary).font(.system(size:12,weight:.medium))
                ForEach(report.probes) {probe in HStack {Image(systemName:probe.status == .readable ? "checkmark.circle.fill" : probe.status == .blocked ? "lock.fill" : "questionmark.circle").foregroundStyle(probe.status == .readable ? Palette.sage : Palette.muted);Text(probe.title);Spacer();Text(probe.status == .readable ? "Readable" : probe.status == .blocked ? "Access needed" : probe.status == .missing ? "Not present" : "Could not check").foregroundStyle(Palette.muted)}.font(.system(size:11)).help(probe.detail)}
                Text("Checked \(report.date.formatted(date:.omitted,time:.shortened)). These checks read directory metadata only; they do not query macOS's permission switch or open personal contents.").secondaryText()
            }
            Text("Approve macOS folder prompts when you scan those locations. After changing access, check again and refresh. If access remains blocked, quit and reopen Bonsai. This development build may need permission again after an update.").secondaryText()
            Text("Bonsai does not need camera, microphone, Screen Recording or Accessibility access for disk scanning. Protected and other-owned files remain guarded during removal.").secondaryText()
        }.task {if report==nil {check()}}
    }
    private func check() {guard !checking else {return};checking=true;Task {let value=await Task.detached {FileAccess.check()}.value;report=value;checking=false}}
}
