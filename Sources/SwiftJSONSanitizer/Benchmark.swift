import Foundation

// Simple benchmark to measure performance improvements
func benchmark() {
  let largeJSON = generateLargeJSON(depth: 6, breadth: 8)
  let iterations = 100
  
  print("JSON size: \(largeJSON.count) bytes")
  
  // Warm up
  _ = SwiftJSONSanitizer.sanitize(largeJSON, options: .minify)
  
  // Benchmark minification
  let minifyStart = CFAbsoluteTimeGetCurrent()
  for _ in 0..<iterations {
    _ = SwiftJSONSanitizer.sanitize(largeJSON, options: .minify)
  }
  let minifyTime = CFAbsoluteTimeGetCurrent() - minifyStart
  
  // Benchmark pretty print
  let prettyStart = CFAbsoluteTimeGetCurrent()
  for _ in 0..<iterations {
    _ = SwiftJSONSanitizer.sanitize(largeJSON, options: .prettyPrint)
  }
  let prettyTime = CFAbsoluteTimeGetCurrent() - prettyStart
  
  print("Minify: \(minifyTime / Double(iterations) * 1000)ms per iteration")
  print("Pretty: \(prettyTime / Double(iterations) * 1000)ms per iteration")
  print("Total minify time: \(minifyTime)s")
  print("Total pretty time: \(prettyTime)s")
}

private func generateLargeJSON(depth: Int, breadth: Int) -> String {
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
        object += "\"string value with special chars: {}, []"  // Missing closing quote
      }
      if i < breadth - 1 {
        object += ","
      }
    }
    // Randomly omit closing brace
    if currentDepth % 2 == 0 {
      object += "}"
    }
    return object
  }
  
  return generateObject(depth)
}