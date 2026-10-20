import SwiftUI
import AppKit

/// Scale measurement and drawing together, keeping surrounding layout responsive.
struct ElementDesignLayout:Layout {
    var x:CGFloat;var y:CGFloat
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        guard let view=subviews.first else {return .zero}
        let size=view.sizeThatFits(.init(width:proposal.width.map {$0/x},height:proposal.height.map {$0/y}))
        return .init(width:size.width*x,height:size.height*y)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        subviews.first?.place(at:bounds.origin,anchor:.topLeading,proposal:.init(width:bounds.width/x,height:bounds.height/y))
    }
}
private struct EditableDesignElement:ViewModifier {
    let id:String;var transform:Bool
    @ObservedObject private var design=DesignPreferences.shared
    func body(content:Content)->some View {
        let value=design.value(id)
        Group {
            if transform {
                ElementDesignLayout(x:value.scale*value.width,y:value.scale*value.height) {
                    content.scaleEffect(x:value.scale*value.width,y:value.scale*value.height,anchor:.topLeading)
                }.padding(value.spacing)
            } else {content}
        }.offset(x:transform ? value.x:0,y:transform ? value.y:0)
        #if BONSAI_DESIGN_EDITOR
        .anchorPreference(key:DesignRegionKey.self,value:.bounds) {[DesignRegion(id:id,bounds:$0)]}
        #endif
    }
}
extension View {
    func designElement(_ id:String)->some View {modifier(EditableDesignElement(id:id,transform:true))}
    func designSelectable(_ id:String)->some View {modifier(EditableDesignElement(id:id,transform:false))}
}
#if BONSAI_DESIGN_EDITOR
@MainActor final class DesignPanelController:NSObject,NSWindowDelegate {
    static let shared=DesignPanelController()
    private var panel:NSPanel?
    func show() {
        let design=DesignPreferences.shared;design.active=true
        if let panel {panel.makeKeyAndOrderFront(nil);return}
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:330,height:650),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
        panel.title="Bonsai Design";panel.isReleasedWhenClosed=false;panel.hidesOnDeactivate=true;panel.level = .floating
        panel.minSize=NSSize(width:310,height:480);panel.maxSize=NSSize(width:450,height:900);panel.delegate=self
        panel.contentView=NSHostingView(rootView:DesignInspector().bonsaiAppearance())
        if let main=NSApp.windows.first(where:{$0.title=="Bonsai"}),let screen=main.screen {
            let visible=screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x:min(visible.maxX-330,max(visible.minX,main.frame.maxX-340)),y:max(visible.minY,main.frame.maxY-650)))
        } else {panel.center()}
        self.panel=panel;panel.makeKeyAndOrderFront(nil)
    }
    func close() {DesignPreferences.shared.save();DesignPreferences.shared.active=false;panel?.close();panel=nil}
    func pickOnPage() {
        DesignPreferences.shared.picking=true
        let main=NSApp.mainWindow ?? NSApp.windows.first { !($0 is NSPanel) && $0.isVisible }
        main?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification:Notification) {DesignPreferences.shared.save();DesignPreferences.shared.active=false;panel=nil}
}
struct DesignInspector:View {
    @ObservedObject private var design=DesignPreferences.shared
    @ViewState private var exportStatus="Preview saved on this Mac."
    private var target:DesignTarget {DesignTarget.find(design.selection) ?? DesignTarget.all[0]}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {Text("Make it yours").font(.title3.weight(.semibold));Spacer();Button("Done") {DesignPanelController.shared.close()}.handCursor().keyboardShortcut(.cancelAction)}
            Toggle("Pick elements on screen",isOn:$design.picking).toggleStyle(.switch).controlSize(.small).handCursor()
            Text(design.picking ? "Click an outlined element to edit it.":"Preview mode · selection outlines are hidden.").font(.caption).foregroundStyle(.secondary)
            Button("Select on page") {DesignPanelController.shared.pickOnPage()}.handCursor()
            Menu {
                ForEach(["Navigation","Clean","Apps","Optimize","Analyze","Status","Settings"],id:\.self) {section in
                    Section(section) {ForEach(DesignTarget.all.filter {$0.section==section}) {target in Button(target.title) {design.select(target.id,navigating:true)}}}
                }
            } label:{HStack {Text(target.title).font(.system(size:13,weight:.semibold));Spacer();Image(systemName:"chevron.up.chevron.down")}.padding(10).background(Palette.text.opacity(0.06),in:RoundedRectangle(cornerRadius:8))}.menuStyle(.borderlessButton).menuIndicator(.hidden).handCursor().accessibilityLabel("Choose design element").accessibilityValue(target.title)
            SettingsScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if target.kind != .spacing {
                        adjustment(target.kind == .text ? "Text size":"Size",\.scale,range:0.65...1.4,percent:true)
                        if target.kind != .text {
                            adjustment("Width scale",\.width,range:0.75...1.3,percent:true)
                            adjustment("Height scale",\.height,range:0.75...1.3,percent:true)
                        }
                    }
                    adjustment(target.kind == .spacing ? "Extra button spacing":"Space around",\.spacing,range:0...18)
                    if target.kind != .navigation && target.kind != .spacing {
                        adjustment("Horizontal position",\.x,range:-80...80)
                        adjustment("Vertical position",\.y,range:-80...80)
                    }
                    if target.id.contains("Rows") || target.id.hasSuffix(".rows") {Text("Repeated rows share this style.").font(.caption).foregroundStyle(.secondary)}
                }.padding(.vertical,8).padding(.trailing,8)
            }
            HStack {Button("Undo") {design.undo()}.disabled(!design.undoAvailable);Spacer();Button("Reset element") {design.reset(target.id)}.disabled(design.value(target.id)==ElementDesign())}.handCursor()
            Button("Save build settings",action:exportDesign).handCursor()
            HStack {Text(exportStatus).font(.caption).foregroundStyle(.secondary);Spacer();Button("Reset all") {design.resetAll()}.disabled(design.values.isEmpty).handCursor()}
        }.padding(18).foregroundStyle(Palette.text).background(Palette.background).frame(minWidth:310,minHeight:450)
    }
    private func exportDesign() {
        do {
            guard let rootFile=Bundle.main.url(forResource:"StudioSourceRoot",withExtension:"txt") else {throw CocoaError(.fileNoSuchFile)}
            let root=try String(contentsOf:rootFile,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)
            let destination=URL(fileURLWithPath:root).appendingPathComponent("Resources/InterfaceDesign.json")
            guard FileManager.default.fileExists(atPath:URL(fileURLWithPath:root).appendingPathComponent("Package.swift").path) else {throw CocoaError(.fileNoSuchFile)}
            try design.export(to:destination);exportStatus="Saved to InterfaceDesign.json."
        } catch {exportStatus="Could not save: "+error.localizedDescription}
    }
    private func adjustment(_ title:String,_ key:WritableKeyPath<ElementDesign,Double>,range:ClosedRange<Double>,percent:Bool=false)->some View {
        let binding=Binding<Double>(get:{design.value(target.id)[keyPath:key]},set:{value in design.update(target.id) {$0[keyPath:key]=value}})
        return VStack(alignment:.leading,spacing:7) {
            HStack {Text(title).font(.system(size:12));Spacer();Text(percent ? "\(Int((binding.wrappedValue*100).rounded()))%":"\(Int(binding.wrappedValue.rounded())) pt").font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)}
            HStack(spacing:8) {
                Button {binding.wrappedValue=max(range.lowerBound,binding.wrappedValue-(percent ? 0.01:1))} label:{Image(systemName:"minus")}.buttonStyle(.plain).handCursor().accessibilityLabel("Decrease "+title)
                Slider(value:binding,in:range).accessibilityLabel(title)
                Button {binding.wrappedValue=min(range.upperBound,binding.wrappedValue+(percent ? 0.01:1))} label:{Image(systemName:"plus")}.buttonStyle(.plain).handCursor().accessibilityLabel("Increase "+title)
            }
        }
    }
}

struct DesignRegion {let id:String;let bounds:Anchor<CGRect>}
struct DesignRegionKey:PreferenceKey {
    static let defaultValue:[DesignRegion]=[]
    static func reduce(value:inout [DesignRegion],nextValue:()->[DesignRegion]) {value += nextValue()}
}
private struct DeveloperDesignSurface:ViewModifier {
    @ObservedObject private var design=DesignPreferences.shared
    func body(content:Content)->some View {
        content.allowsHitTesting(false).accessibilityHidden(true)
            .overlayPreferenceValue(DesignRegionKey.self) {regions in
                GeometryReader {geometry in
                    let ordered=regions.enumerated().sorted {geometry[$0.element.bounds].width*geometry[$0.element.bounds].height > geometry[$1.element.bounds].width*geometry[$1.element.bounds].height}
                    ZStack(alignment:.topLeading) {
                        if design.active && design.picking {
                            ForEach(ordered,id:\.offset) {_,region in
                                let rect=geometry[region.bounds].intersection(CGRect(origin:.zero,size:geometry.size))
                                if !rect.isNull && rect.width>1 && rect.height>1 {
                                    Button {design.select(region.id);DesignPanelController.shared.show()} label:{RoundedRectangle(cornerRadius:8).fill(Color.clear).contentShape(Rectangle()).overlay(RoundedRectangle(cornerRadius:8).stroke(design.selection==region.id ? Color.accentColor:Color.accentColor.opacity(0.3),style:.init(lineWidth:design.selection==region.id ? 2:1,dash:design.selection==region.id ? []:[4,4])))}
                                        .buttonStyle(.plain).handCursor().accessibilityLabel("Edit "+(DesignTarget.find(region.id)?.title ?? region.id))
                                        .frame(width:rect.width,height:rect.height).offset(x:rect.minX,y:rect.minY)
                                }
                            }
                        }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
                }
            }
    }
}
extension View {func developerDesignSurface()->some View {modifier(DeveloperDesignSurface())}}
#endif

// Developer previews omit global operational Return actions. Regular builds
// preserve the original default-button shortcut.
extension View {
    @ViewBuilder func bonsaiDefaultAction()->some View {
        #if BONSAI_DESIGN_EDITOR
        self
        #else
        self.keyboardShortcut(.defaultAction)
        #endif
    }
}
