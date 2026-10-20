import Foundation

/// A check is not an optimization. Count only known changing tasks as refreshed.
public struct MaintenanceSummary:Sendable,Equatable {
    public let refreshed:Int
    public let checked:Int
    public let otherCompleted:Int
    public let attention:Int
    public let skipped:Int
    public let unchanged:Int
    public let unavailable:Int
    public var completed:Int {refreshed+checked+otherCompleted}
    public init(tasks:[MaintenanceTask],outcomes:[ItemOutcome]) {
        var refreshed=0,checked=0,other=0,attention=0,skipped=0,unchanged=0,unavailable=0
        for outcome in outcomes {
            if outcome.status=="Unchanged" {unchanged+=1}
            else if outcome.status=="Unavailable" {unavailable+=1}
            else if outcome.status=="Skipped" {skipped+=1}
            else if outcome.status != "Completed" {attention+=1}
            else if let task=tasks.first(where:{$0.preview==outcome.path}) {
                if task.readOnly {checked+=1} else {refreshed+=1}
            } else {other+=1}
        }
        self.refreshed=refreshed;self.checked=checked;self.otherCompleted=other
        self.attention=attention;self.skipped=skipped;self.unchanged=unchanged;self.unavailable=unavailable
    }
    public var label:String {
        var parts:[String]=[]
        if refreshed>0 {parts.append("\(refreshed) refreshed")}
        if checked>0 {parts.append("\(checked) checked")}
        if otherCompleted>0 {parts.append("\(otherCompleted) completed")}
        if unchanged>0 {parts.append("\(unchanged) already healthy")}
        if unavailable>0 {parts.append("\(unavailable) unavailable")}
        if attention>0 {parts.append("\(attention) need attention")}
        if skipped>0 {parts.append("\(skipped) skipped")}
        return parts.isEmpty ? "No tasks ran" : parts.joined(separator:" · ")
    }
    public func headline(cancelled:Bool)->String {
        if cancelled {return "Maintenance stopped"}
        return attention>0 ? "A little more care needed" : "Maintenance complete"
    }
}
