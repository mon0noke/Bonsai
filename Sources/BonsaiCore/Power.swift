import Foundation
import IOKit.pwr_mgt
public final class PowerAssertion {
    private var assertions:[IOPMAssertionID]=[]
    private var behavior:AwakeBehavior?
    public var active:Bool {!assertions.isEmpty}
    public init() {}
    public func set(_ enabled:Bool,behavior:AwakeBehavior = .screenAndWork) throws {
        if !enabled {release();return}
        if active && self.behavior==behavior {return}
        let types:[CFString]=behavior == .screenAndWork ? [kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,kIOPMAssertionTypePreventUserIdleSystemSleep as CFString] : [behavior == .workOnly ? kIOPMAssertionTypePreventUserIdleSystemSleep as CFString : kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString]
        var created:[IOPMAssertionID]=[]
        for type in types {
            var identifier:IOPMAssertionID=0
            let code=IOPMAssertionCreateWithName(type,IOPMAssertionLevel(kIOPMAssertionLevelOn),"Bonsai Keep Screen On" as CFString,&identifier)
            guard code==kIOReturnSuccess else {created.forEach {IOPMAssertionRelease($0)};throw BonsaiError.unavailable("macOS refused the power assertion (\(code)).")}
            created.append(identifier)
        }
        release();assertions=created;self.behavior=behavior
    }
    private func release() {assertions.forEach {IOPMAssertionRelease($0)};assertions=[];behavior=nil}
    deinit {release()}
}
