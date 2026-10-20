import Foundation
import BonsaiCore
import Darwin

class HarnessCase {
    func setUpWithError() throws {}
    func tearDownWithError() throws {}
}
enum Checks {
    static var failures=0; static var assertions=0
    static func assert(_ condition: Bool,_ message: String,_ file: StaticString,_ line: UInt) { assertions += 1; if !condition { failures += 1; print("FAIL \(file):\(line) \(message)") } }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool,_ message: String="",file: StaticString=#filePath,line: UInt=#line) { do { Checks.assert(try value(),message.isEmpty ? "Expected true" : message,file,line) } catch { Checks.assert(false,error.localizedDescription,file,line) } }
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool,file: StaticString=#filePath,line: UInt=#line) { do { Checks.assert(!(try value()),"Expected false",file,line) } catch { Checks.assert(false,error.localizedDescription,file,line) } }
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T,_ b: @autoclosure () throws -> T,file: StaticString=#filePath,line: UInt=#line) { do { let x=try a(),y=try b(); Checks.assert(x==y,"\(x) != \(y)",file,line) } catch { Checks.assert(false,error.localizedDescription,file,line) } }
func XCTAssertEqual<T: BinaryFloatingPoint>(_ a: T,_ b: T,accuracy: T,file: StaticString=#filePath,line: UInt=#line) { Checks.assert(abs(a-b)<=accuracy,"\(a) != \(b) ± \(accuracy)",file,line) }
func XCTAssertGreaterThan<T: Comparable>(_ a: T,_ b: T,file: StaticString=#filePath,line: UInt=#line) { Checks.assert(a>b,"Expected \(a) > \(b)",file,line) }
func XCTAssertNotNil<T>(_ value: T?,file: StaticString=#filePath,line: UInt=#line) { Checks.assert(value != nil,"Expected non-nil",file,line) }
func XCTAssertNil<T>(_ value: T?,file: StaticString=#filePath,line: UInt=#line) { Checks.assert(value == nil,"Expected nil",file,line) }
func XCTAssertNoThrow<T>(_ value: @autoclosure () throws -> T,file: StaticString=#filePath,line: UInt=#line) { do { _=try value(); Checks.assert(true,"",file,line) } catch { Checks.assert(false,error.localizedDescription,file,line) } }
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T,file: StaticString=#filePath,line: UInt=#line) { do { _=try value(); Checks.assert(false,"Expected error",file,line) } catch { Checks.assert(true,"",file,line) } }
func XCTFail(_ message: String="Failed",file: StaticString=#filePath,line: UInt=#line) { Checks.assert(false,message,file,line) }
