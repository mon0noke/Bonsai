// Stable scene keys retain existing state; each portrait is now a miniature bonsai.
enum NatureScene:String,CaseIterable { case oak, pine, maple, elm, olive
    var name:String { switch self { case .oak:return "Cherry blossom bonsai";case .pine:return "Black pine bonsai";case .maple:return "Japanese maple bonsai";case .elm:return "Chinese elm bonsai";case .olive:return "Olive bonsai" } }
    var botanicalName:String { switch self { case .oak:return "Prunus serrulata";case .pine:return "Pinus thunbergii";case .maple:return "Acer palmatum";case .elm:return "Ulmus parvifolia";case .olive:return "Olea europaea" } }
    var resource:String { switch self {case .oak:return "CherryBonsai";case .pine:return "PineBonsai";case .maple:return "MapleBonsai";case .elm:return "ElmBonsai";case .olive:return "OliveBonsai"} }
    var verse:String {
        switch self {
        case .oak:return "A little space. A little calm.\nCare for what matters."
        case .pine:return "Every branch has a story.\nFind where your space grows."
        case .maple:return "Small rituals. Lasting balance.\nA fresh start for your Mac."
        case .elm:return "Room for what you use.\nLet the rest grow lighter."
        case .olive:return "A steady rhythm. A healthy balance.\nKnow how your Mac is feeling."
        }
    }
}
