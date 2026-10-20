import Foundation
import CryptoKit

/// Pinned upstream code is actually executed for application protection.
/// macOS telemetry, third-party updates and managed login items do not expose
/// suitable APIs through Bonsai's public CLI and stay behind native services.
public enum ProtectionBackend {
    public static let revision="c430bac637929ebede043df81d3bef319428309c"
    private static let hashes:[String:String]=[
        "protection.sh":"ca1779b0355414b9e73351e42afb8cd51cf191c68400e0394ea0eb7bc0d85b05",
        "app_protection_data.sh":"0aa1b21cc6cbdb625c22f543a8eb23081b6c9bfccaf268993954973143507db7",
    ]
    public static func validatedScript(directory:URL?=nil) throws -> URL {
        guard let root=directory ?? Bundle.main.resourceURL?.appendingPathComponent("ProtectionBackend") else {throw BonsaiError.unavailable("Bonsai protection backend is missing. Reinstall Bonsai.")}
        for (name,hash) in hashes {
            let file=root.appendingPathComponent(name);let identity=try Identity.read(file)
            guard !identity.isSymlink,!identity.isDirectory else {throw BonsaiError.refused("Bonsai backend resource was replaced.")}
            let data=try Data(contentsOf:file)
            guard data.count<262_144,SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==hash else {throw BonsaiError.refused("Bonsai backend integrity check failed. Reinstall Bonsai.")}
        }
        return root.appendingPathComponent("protection.sh")
    }
    public static func protectedIdentifiers(_ identifiers:[String],directory:URL?=nil) async throws -> Set<String> {
        let ids=Array(Set(identifiers.filter {!$0.isEmpty})).sorted()
        guard ids.count<=512,ids.allSatisfy({$0.range(of:"^[A-Za-z0-9][A-Za-z0-9._+-]*$",options:.regularExpression) != nil}) else {throw BonsaiError.refused("Invalid application identifier for Bonsai protection review.")}
        let script=try validatedScript(directory:directory)
        let result=try await CommandRunner.runProtection(script,ids)
        guard result.succeeded else {throw BonsaiError.unavailable("Bonsai protection review failed. No change was made.")}
        var classified=Set<String>();var protected=Set<String>()
        for row in result.standardOutput.split(separator:"\n") {
            let fields=row.split(separator:"\t",omittingEmptySubsequences:false)
            guard fields.count==3,ids.contains(String(fields[0])),["0","1"].contains(fields[1]),classified.insert(String(fields[0])).inserted else {throw BonsaiError.unavailable("Bonsai returned an incomplete protection review.")}
            if fields[1]=="1" {protected.insert(String(fields[0]))}
        }
        guard classified==Set(ids) else {throw BonsaiError.unavailable("Bonsai protection review was incomplete. Retry before making changes.")}
        return protected
    }
}
