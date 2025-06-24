import Foundation

// Benchmark comparison between original and optimized versions
public struct BenchmarkComparison {
  
  public static func run() {
    print("=== SwiftJSONSanitizer Performance Benchmark ===\n")
    
    // Generate test data
    let smallJSON = generateJSON(depth: 3, breadth: 5)
    let mediumJSON = generateJSON(depth: 4, breadth: 6)
    let largeJSON = generateJSON(depth: 5, breadth: 8)
    let veryLargeJSON = generateJSON(depth: 6, breadth: 8)
    
    print("Test data sizes:")
    print("- Small: \(smallJSON.count) bytes")
    print("- Medium: \(mediumJSON.count) bytes")
    print("- Large: \(largeJSON.count) bytes")
    print("- Very Large: \(veryLargeJSON.count) bytes")
    print("")
    
    // Warm up
    _ = SwiftJSONSanitizer.sanitize(smallJSON, options: .minify)
    _ = SwiftJSONSanitizer.sanitize(smallJSON, options: .prettyPrint)
    
    // Run benchmarks
    print("Running benchmarks (100 iterations each)...")
    print("")
    
    // Small JSON
    print("Small JSON:")
    benchmarkSize(smallJSON, label: "Small", iterations: 100)
    
    // Medium JSON
    print("\nMedium JSON:")
    benchmarkSize(mediumJSON, label: "Medium", iterations: 100)
    
    // Large JSON
    print("\nLarge JSON:")
    benchmarkSize(largeJSON, label: "Large", iterations: 100)
    
    // Very Large JSON
    print("\nVery Large JSON:")
    benchmarkSize(veryLargeJSON, label: "Very Large", iterations: 50)
    
    // Memory pressure test
    print("\n=== Memory Pressure Test ===")
    memoryPressureTest()
  }
  
  private static func benchmarkSize(_ json: String, label: String, iterations: Int) {
    // Minify benchmark
    let minifyStart = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
      _ = SwiftJSONSanitizer.sanitize(json, options: .minify)
    }
    let minifyTime = CFAbsoluteTimeGetCurrent() - minifyStart
    
    // Pretty print benchmark
    let prettyStart = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
      _ = SwiftJSONSanitizer.sanitize(json, options: .prettyPrint)
    }
    let prettyTime = CFAbsoluteTimeGetCurrent() - prettyStart
    
    // Calculate and print results
    let minifyPerIteration = (minifyTime / Double(iterations)) * 1000
    let prettyPerIteration = (prettyTime / Double(iterations)) * 1000
    
    print("  Minify: \(String(format: "%.3f", minifyPerIteration))ms per iteration")
    print("  Pretty: \(String(format: "%.3f", prettyPerIteration))ms per iteration")
    print("  Throughput (minify): \(String(format: "%.1f", Double(json.count * iterations) / minifyTime / 1_000_000)) MB/s")
    print("  Throughput (pretty): \(String(format: "%.1f", Double(json.count * iterations) / prettyTime / 1_000_000)) MB/s")
  }
  
  private static func memoryPressureTest() {
    let hugeJSON = generateJSON(depth: 7, breadth: 5)
    print("Testing with \(hugeJSON.count) bytes...")
    
    let start = CFAbsoluteTimeGetCurrent()
    _ = SwiftJSONSanitizer.sanitize(hugeJSON, options: .prettyPrint)
    let time = CFAbsoluteTimeGetCurrent() - start
    
    print("  Time: \(String(format: "%.3f", time * 1000))ms")
    print("  Throughput: \(String(format: "%.1f", Double(hugeJSON.count) / time / 1_000_000)) MB/s")
  }
  
  private static func generateJSON(depth: Int, breadth: Int) -> String {
    func generateObject(_ currentDepth: Int) -> String {
      if currentDepth == 0 {
        return "{\"leaf\":\"value with some text content here that makes it realistic\"}"
      }
      
      var object = "{"
      for i in 0..<breadth {
        object += "\"key\(i)\":"
        if i % 4 == 0 {
          object += "[1,2,3,4,5"  // Missing closing bracket
        } else if i % 4 == 1 {
          object += generateObject(currentDepth - 1)
        } else if i % 4 == 2 {
          object += "\"string value with special chars: {}, [], and a comma,"  // Missing closing quote
        } else {
          object += "true"
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
}

// Function to run from command line
func runBenchmark() {
  BenchmarkComparison.run()
}