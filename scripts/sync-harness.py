from pathlib import Path
import re
source=Path('Tests/BonsaiCoreTests/CoreTests.swift').read_text()
source=source.replace('import XCTest\n','').replace('@testable import BonsaiCore','import BonsaiCore').replace('class CoreTests: XCTestCase','class CoreTests: HarnessCase')
Path('Sources/BonsaiVerify/CoreChecks.swift').write_text('// Generated from Tests/BonsaiCoreTests/CoreTests.swift by scripts/sync-harness.py\n'+source)
entries=[]
for name,asynchronous,throwing in re.findall(r'func (test\w+)\(\)( async)?( throws)?',source):
    entries.append(f'("{name}", {{ '+('try ' if throwing else '')+('await ' if asynchronous else '')+f'tests.{name}()'+ ' })')
main='''import Foundation
import BonsaiCore
import Darwin
@main struct Verify {
 static func main() async {
  print("Bonsai verification harness · disposable fixtures only")
  let tests=CoreTests()
  let suite: [(String,() async throws -> Void)] = [
'''+',\n'.join(entries)+'''
  ]
  for (name,run) in suite {
   let prior=Checks.failures
   do { try tests.setUpWithError(); try await run() } catch { XCTFail("\\(name): \\(error.localizedDescription)") }
   try? tests.tearDownWithError()
   print("\\(Checks.failures==prior ? "PASS" : "FAIL") \\(name)")
  }
  print("RESULT: \\(suite.count) cases, \\(Checks.assertions) assertions, \\(Checks.failures) failures")
  exit(Checks.failures==0 ? 0 : 1)
 }
}
'''
Path('Sources/BonsaiVerify/Verify.swift').write_text(main)
