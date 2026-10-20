import Foundation

/// Visual growth reflects measured allocation, not a judgment about a folder.
public enum BonsaiGrowth {
    public static let pruningDuration:Double=1.6
    public static func level(bytes:UInt64)->Double {
        // 10 MB is lightly grown; 100 GB reaches the densest silhouette.
        min(1,max(0,(log10(max(1,Double(bytes)))-7)/4))
    }
    public static func pruningProgress(elapsed:Double)->Double {
        guard elapsed.isFinite else {return elapsed == .infinity ? 1 : 0}
        return min(1,max(0,elapsed/pruningDuration))
    }
    /// Top-down portrait coordinates. Expansion fades out before the pot/root.
    public static func canopyScale(topY:Double,growth:Double,pruning:Double)->Double {
        guard topY.isFinite,growth.isFinite,pruning.isFinite else {return 1}
        let t=min(1,max(0,(0.60-topY)/0.32)),weight=t*t*(3-2*t)
        let p=min(1,max(0,pruning)),remaining=pow(1-p,3)
        return 1+(0.03+min(1,max(0,growth))*0.22)*weight*remaining
    }
}
