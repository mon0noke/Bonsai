import SwiftUI

/// Scale layout proposals and rendering together, preserving scroll extents,
/// hit testing and accessibility frames. Native macOS window chrome is unchanged.
struct InterfaceScaleLayout: Layout {
    static let factor: CGFloat = 0.924
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let size = view.sizeThatFits(ProposedViewSize(width: proposal.width.map { $0 / Self.factor }, height: proposal.height.map { $0 / Self.factor }))
        return CGSize(width: size.width * Self.factor, height: size.height * Self.factor)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width / Self.factor, height: bounds.height / Self.factor))
    }
}
extension View {
    func compactInterface() -> some View {
        InterfaceScaleLayout { self.scaleEffect(InterfaceScaleLayout.factor, anchor: .topLeading) }
    }
}
