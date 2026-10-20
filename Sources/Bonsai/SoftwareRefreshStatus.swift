import SwiftUI
/// Small native activity indicator; keeps rows and navigation in place.
struct SoftwareRefreshStatus:View {
    var title:String
    var cancel:(()->Void)?=nil
    var body:some View {
        HStack(spacing:9) {
            ProgressView().controlSize(.small).scaleEffect(0.7).frame(width:14,height:14)
            Text(title).font(.system(size:11)).foregroundStyle(Palette.muted).lineLimit(1)
            Spacer()
            if let cancel {Button("Stop",action:cancel).buttonStyle(QuietTextStyle()).handCursor()}
        }.padding(.vertical,3).accessibilityElement(children:.contain)
    }
}
