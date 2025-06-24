import XCTest
@testable import SwiftJSONSanitizer

final class BenchmarkTests: XCTestCase {
  
  func testBenchmarkOriginal() {
    print("\n=== ORIGINAL IMPLEMENTATION BENCHMARK ===")
    runBenchmarks()
  }
  
  func testBenchmarkOptimized() {
    print("\n=== OPTIMIZED IMPLEMENTATION BENCHMARK ===")
    runBenchmarks()
  }
  
  func testBenchmarkZeroCopy() {
    print("\n=== ZERO-COPY IMPLEMENTATION BENCHMARK ===")
    runBenchmarks()
  }
  
  private func runBenchmarks() {
    // Generate test data
    let sizes = [
      ("Small", generateJSON(depth: 3, breadth: 5)),
      ("Medium", generateJSON(depth: 4, breadth: 6)),
      ("Large", generateJSON(depth: 5, breadth: 8))
    ]
    
    for (label, json) in sizes {
      print("\n\(label) JSON (\(json.count) bytes):")
      
      // Minify benchmark
      let minifyTime = measure(iterations: 100) {
        _ = SwiftJSONSanitizer.sanitize(json, options: .minify)
      }
      
      // Pretty print benchmark
      let prettyTime = measure(iterations: 100) {
        _ = SwiftJSONSanitizer.sanitize(json, options: .prettyPrint)
      }
      
      print("  Minify: \(String(format: "%.3f", minifyTime * 1000))ms per iteration")
      print("  Pretty: \(String(format: "%.3f", prettyTime * 1000))ms per iteration")
      print("  Throughput (minify): \(String(format: "%.1f", Double(json.count) / minifyTime / 1_000_000)) MB/s")
      print("  Throughput (pretty): \(String(format: "%.1f", Double(json.count) / prettyTime / 1_000_000)) MB/s")
    }
  }
  
  private func measure(iterations: Int, block: () -> Void) -> TimeInterval {
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
      block()
    }
    let end = CFAbsoluteTimeGetCurrent()
    return (end - start) / Double(iterations)
  }
  
  private func generateJSON(depth: Int, breadth: Int) -> String {
    func generateObject(_ currentDepth: Int) -> String {
      if currentDepth == 0 {
        return "{\"leaf\":\"value with some text content here\"}"
      }
      
      var object = "{"
      for i in 0..<breadth {
        object += "\"key\(i)\":"
        if i % 3 == 0 {
          object += "[1,2,3,4,5"  // Missing closing bracket
        } else if i % 3 == 1 {
          object += generateObject(currentDepth - 1)
        } else {
          object += "\"string with special: {}, []"  // Missing quote
        }
        if i < breadth - 1 {
          object += ","
        }
      }
      if currentDepth % 2 == 0 {
        object += "}"
      }
      return object
    }
    
    return generateObject(depth)
  }
}