import Foundation

public struct SoftwareUpdateProgress:Sendable,Equatable {
    public enum Phase:Int,Sendable {
        case queued,preparing,downloading,verifying,extracting,installing,checking
        public var title:String {
            switch self {
            case .queued:return "Queued"
            case .preparing:return "Preparing…"
            case .downloading:return "Downloading"
            case .verifying:return "Verifying…"
            case .extracting:return "Unpacking…"
            case .installing:return "Installing…"
            case .checking:return "Checking…"
            }
        }
    }
    public let phase:Phase
    public let fraction:Double?
    public init(_ phase:Phase,fraction:Double?=nil) {
        self.phase=phase
        self.fraction=fraction.flatMap {$0.isFinite ? min(1,max(0,$0)):nil}
    }
    public static func download(received:Int64,total:Int64)->Self {
        Self(.downloading,fraction:total>0 && received>=0 ? Double(received)/Double(total):nil)
    }
}
public typealias SoftwareUpdateProgressHandler = @Sendable (SoftwareUpdateProgress)->Void

public enum PackageReceipt {
    public static func version(_ identifier:String)->String? {
        guard identifier.range(of:"^[A-Za-z0-9][A-Za-z0-9._-]{1,254}$",options:.regularExpression) != nil else {return nil}
        let path=URL(fileURLWithPath:"/var/db/receipts").appendingPathComponent(identifier+".plist")
        guard let info=try? Identity.read(path),!info.isSymlink,info.size<1_048_576,let data=try? Data(contentsOf:path),let plist=try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else {return nil}
        return plist["PackageVersion"] as? String
    }
}
