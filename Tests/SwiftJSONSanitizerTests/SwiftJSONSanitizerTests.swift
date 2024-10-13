//  SwiftJSONSanitizerTests
//
//  Created by Fahad Gilani on 13/10/2024.
//

import XCTest
import Foundation
@testable import SwiftJSONSanitizer

final class SwiftJSONSanitizerTests: XCTestCase {
  
  func testValidJSON() {
    let input = "{\"key\": [11, 12, 13]}"
    let expected = """
        {
          "key": [
            11,
            12,
            13
          ]
        }
        """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testMissingBrace() {
    let input = "{\"key\": [1, 2, 3]}"
    let expected = """
        {
          "key": [
            1,
            2,
            3
          ]
        }
        """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testMissingClosingBracket() {
    let input = "{\"key\": [1, 2, 3"
    let expected = """
        {
          "key": [
            1,
            2,
            3
          ]
        }
        """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testMissingClosingBrace() {
    let input = "{\"key\": {\"nested\": true"
    let expected = """
        {
          "key": {
            "nested": true
          }
        }
        """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testExtraClosingBracket() {
    let input = "{\"key\": [1, 2, 3]]}"
    let expected = """
        {
          "key": [
            1,
            2,
            3
          ]
        }
        """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testMultipleMissingClosingBrackets() {
    let input = "{\"key\": [[[1, 2, 3"
    let expected = """
            {
              "key": [
                [
                  [
                    1,
                    2,
                    3
                  ]
                ]
              ]
            }
            """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testExtraClosingBrace() {
    let input = "{\"key\": {\"nested\": true}}}"
    let expected = """
        {
          "key": {
            "nested": true
          }
        }
        """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testMultipleMissingClosingBraces() {
    let input = "{\"key\": {\"nested\": {\"deep\": true"
    let expected = """
            {
              "key": {
                "nested": {
                  "deep": true
                }
              }
            }
            """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testMixedMissingClosingBracketsAndBraces() {
    let input = "{\"key\": [1, {\"nested\": [2, 3"
    let expected = """
            {
              "key": [
                1,
                {
                  "nested": [
                    2,
                    3
                  ]
                }
              ]
            }
            """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testMismatchedBrackets() {
    let input = "{\"key\": [1, 2, 3}"
    let expected = """
        {
          "key": [
            1,
            2,
            3
          ]
        }
        """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testMismatchedBraces() {
    let input = "{\"key\": {\"nested\": true]"
    let expected = """
        {
          "key": {
            "nested": true
          }
        }
        """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testMultipleExtraClosingBrackets() {
    let input = "{\"key\": [1, 2, 3]]]]]}"
    let expected = """
            {
              "key": [
                1,
                2,
                3
              ]
            }
            """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testMultipleExtraClosingBraces() {
    let input = "{\"key\": {\"nested\": true}}}}"
    let expected = """
            {
              "key": {
                "nested": true
              }
            }
            """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testMixedExtraClosingBracketsAndBraces() {
    let input = "{\"key\": [1, {\"nested\": [2, 3]}]}}]"
    let expected = """
            {
              "key": [
                1,
                {
                  "nested": [
                    2,
                    3
                  ]
                }
              ]
            }
            """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }

  func testMissingOpeningBrace() {
    let input = "\"key\": {\"nested\": true}}"
    let expected = """
            {
              "key": {
                "nested": true
              }
            }
            """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testUnbalancedMixOfBracketsAndBraces() {
    let input = "{\"data\": [{\"key\": 1}, {\"another\": 2]}"
    let expected = """
    {
      "data": [
        {
          "key": 1
        },
        {
          "another": 2
        }
      ]
    }
    """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testTrailingComma() {
    let input = "{\"key\": [1, 2,]}"
    let expected = """
        {
          "key": [
            1,
            2
          ]
        }
        """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testEscapedQuotesInString() {
    let input = "{\"key\": \"string with \\\"quotes\\\"\"}"
    let expected = """
        {
          "key": "string with \\"quotes\\""
        }
        """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testNestedStructures() {
    let input = "{\"key1\": [1, {\"nested\": true}, 3], \"key2\": {\"a\": 1, \"b\": [2, 3]}}"
    let expected = """
        {
          "key1": [
            1,
            {
              "nested": true
            },
            3
          ],
          "key2": {
            "a": 1,
            "b": [
              2,
              3
            ]
          }
        }
        """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testDeeplyNestedStructures() {
    let input = "{\"key1\": [{\"nested\": [{\"deep\": [1,2]}]}]}"
    let expected = """
    {
      "key1": [
        {
          "nested": [
            {
              "deep": [
                1,
                2
              ]
            }
          ]
        }
      ]
    }
    """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testArraysTrailingComma() {
    let input = """
    {
      "key1": [
        "value1",
        "value2",
        "value3",
        "value4",
        {
          "nested": true
        },
      ]
    }
    """
    let expected = """
    {
      "key1": [
        "value1",
        "value2",
        "value3",
        "value4",
        {
          "nested": true
        }
      ]
    }
    """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testStringArrayExtraBrace() {
    let input = """
    {
      "key1": [
        "value1",
        "value2",
        "value3",
      ]]
    }
    """
    let expected = """
    {
      "key1": [
        "value1",
        "value2",
        "value3"
      ]
    }
    """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testMinification() {
    let input = """
        {
          "key1": [
            1,
            2,
            3
          ],
          "key2": {
            "nested": true
          }
        }
        """
    let expected = "{\"key1\":[1,2,3],\"key2\":{\"nested\":true}}"
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input, options: .minify), expected)
  }
  
  func testCustomFormatting() {
    let input = "{\"key\": [1, 2, 3]}"
    let options = SwiftJSONSanitizer.Options(indentChar: "    ", newLineChar: "\n", valueSeparationChar: " ")
    let expected = """
        {
            "key": [
                1,
                2,
                3
            ]
        }
        """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input, options: options), expected)
  }
  
  func testMalformedJSONRecovery() {
    let input = "{\"key\":{\"key1\": true}, \"key2\":{\"key2\": false}"
    let expected = """
    {
      "key": {
        "key1": true
      },
      "key2": {
        "key2": false
      }
    }
    """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input), expected)
  }
  
  func testBrokenArray() {
    let input = """
    {"responses":[{"body":{"key":[{"error":{"code":"404"}}},{"body":{"key":[{"error":{"code":"404"}}}]}
    """
    let expected = """
    {"responses":[{"body":{"key":[{"error":{"code":"404"}}]}},{"body":{"key":[{"error":{"code":"404"}}]}}]}
    """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input, options: .minify), expected)
  }
  
  func testExtraEndingBraces() {
    let input = """
    {
      "key": [{      
      }]}}}
    }
    """
    
    let expected = """
    {"key":[{}]}
    """
    XCTAssertEqual(SwiftJSONSanitizer.sanitize(input, options: .minify), expected)
  }
  
//  func testLargeJSONPerformance() {
//    let largeInput = generateLargeJSON(depth: 5, breadth: 10)
//    
//    measure {
//      let result = SwiftJSONSanitizer.sanitize(largeInput, options: .minify)
//      XCTAssertTrue(result.starts(with: "{"), "Sanitized output should start with '{'")
//      XCTAssertTrue(result.hasSuffix("}"), "Sanitized output should end with '}'")
//    }
//  }
}


extension SwiftJSONSanitizerTests {
  private func generateLargeJSON(depth: Int, breadth: Int) -> String {
    func generateObject(_ currentDepth: Int) -> String {
      if currentDepth == 0 {
        return "{\"leaf\":\"value\"}"
      }
      
      var object = "{"
      for i in 0..<breadth {
        object += "\"key\(i)\":"
        object += generateObject(currentDepth - 1)
        if i < breadth - 1 {
          object += ","
        }
      }
      object += "}"
      return object
    }
    
    return generateObject(depth)
  }
}
