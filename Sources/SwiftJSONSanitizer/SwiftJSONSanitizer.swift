//
//  SwiftJSONSanitizer.swift
//  SwiftJSONSanitizer
//
//  Created by Fahad Gilani on 13/10/2024.

import Foundation

/// Sanitizes and formats malformed JSON (missing closing brackets / braces etc).
public struct SwiftJSONSanitizer {
  
  /// Configuration options for formatting JSON output
  public struct Options: Sendable {
    /// Character string used for indentation when formatting JSON
    let indentChar: String
    /// Character string used for line breaks when formatting JSON
    let newLineChar: String
    /// Character string used for separating key-value pairs when formatting JSON
    let valueSeparationChar: String
    
    /// Default pretty print options with standard JSON indentation
    public static let prettyPrint = Options(indentChar: "  ", newLineChar: "\n", valueSeparationChar: " ")
    
    /// Default minify options to eliminate unnecessary whitespace
    public static let minify = Options(indentChar: "", newLineChar: "", valueSeparationChar: "")
    
    /// Initializes a new `Options` instance with specified formatting characters.
    /// - Parameters:
    ///   - indent: String to use for indentation.
    ///   - newLine: String to use for new lines.
    ///   - separator: String to use for separating values.
    public init(indentChar: String, newLineChar: String, valueSeparationChar: String) {
      self.indentChar = indentChar
      self.newLineChar = newLineChar
      self.valueSeparationChar = valueSeparationChar
    }
  }
  
  /// Represents the expected type of the next JSON token
  private enum ExpectedType {
    case null, objectStart, objectEnd, arrayStart, arrayEnd, key, colon, value, comma, stringEnd
  }
  
  /// Sanitizes and formats the input JSON string
  /// - Parameters:
  ///   - json: The input JSON string, potentially malformed
  ///   - options: Formatting options (default is .prettyPrint)
  /// - Returns: A sanitized and formatted JSON string
  public static func sanitize(_ json: String, options: Options = .prettyPrint) -> String {
    var formatted = StringBuilder()
    var indentLevel = 0
    var currentIndex = json.startIndex
    var escaping = false
    
    var currentType: ExpectedType = .null
    var expectedTypes: Set<ExpectedType> = [.objectStart, .arrayStart]
    var openedStructures = [Character]()
    
    // Skip leading whitespace
    while currentIndex < json.endIndex, json[currentIndex].isWhitespace {
      currentIndex = json.index(after: currentIndex)
    }
    
    // Check if the JSON starts with a valid JSON opening character
    let isValidJsonStart: Bool
    let startingStructure: Character
    
    if currentIndex < json.endIndex {
      let firstNonWhitespace = json[currentIndex]
      if firstNonWhitespace == "{" || firstNonWhitespace == "[" {
        isValidJsonStart = true
        startingStructure = firstNonWhitespace
      }
      else {
        // Determine if we should start with an object or an array
        startingStructure = json[json.firstIndex(where: { $0 == "}" || $0 == "]" }) ?? json.endIndex] == "}" ? "{" : "["
        isValidJsonStart = false
      }
    }
    else {
      isValidJsonStart = false
      startingStructure = "{"
    }
    
    if !isValidJsonStart {
      // Prepend with an opening brace or bracket if the JSON does not start with a valid opening character
      processOpenBracket(startingStructure, &indentLevel, options, &formatted)
      openedStructures.append(startingStructure)
      expectedTypes = startingStructure == "{" ? [.key, .objectEnd] : [.value, .objectStart, .arrayStart, .arrayEnd]
    }
    
    while currentIndex < json.endIndex {
      let char = json[currentIndex]
      
      if currentType == .key || currentType == .value {
        formatted.append(char)
        
        if escaping {
          escaping = false
        }
        else if char == "\\" {
          escaping = true
        }
        else if char == "\"" {
          if currentType == .key {
            expectedTypes = [.colon]
          }
          else {
            expectedTypes = [.comma, .objectEnd, .arrayEnd]
          }
          currentType = .null
        }
      }
      else {
        switch char {
          case "{":
            if !expectedTypes.contains(.arrayStart), !openedStructures.isEmpty, indentLevel > 0 {
              removeTrailingComma(&formatted)
              
              // Close any open structures if necessary
              closeOpenStructures(&indentLevel, &openedStructures, &expectedTypes, options, &formatted, limit: 1)
              
              // Add a trailing comma
              processComma(indentLevel, options, &formatted)
            }
            
            processOpenBracket(char, &indentLevel, options, &formatted)
            openedStructures.append(char)
            expectedTypes = [.key, .objectEnd]
            
          case "[":
            if !expectedTypes.contains(.arrayStart), !openedStructures.isEmpty, indentLevel > 0 {
              removeTrailingComma(&formatted)
              
              // Close any open structures if necessary
              closeOpenStructures(&indentLevel, &openedStructures, &expectedTypes, options, &formatted, limit: 1)
              
              // Add a trailing comma
              processComma(indentLevel, options, &formatted)
            }
            
            processOpenBracket(char, &indentLevel, options, &formatted)
            openedStructures.append(char)
            expectedTypes = [.value, .objectStart, .arrayStart, .arrayEnd]
            
          case "}":
            removeTrailingComma(&formatted)
            
            if expectedTypes.contains(.objectEnd) {
              // Before processing the end of object, see if we've got an open array and close that first
              if !openedStructures.isEmpty, openedStructures.last == "[" {
                processCloseBracket("]", &indentLevel, options, &formatted)
                openedStructures.removeLast()
              }
              
              if !openedStructures.isEmpty, openedStructures.last == "{" {
                processCloseBracket(char, &indentLevel, options, &formatted)
                openedStructures.removeLast()
              }
              expectedTypes = [.comma, .objectEnd, .arrayEnd]
            }
            
          case "]":
            removeTrailingComma(&formatted)
            
            if expectedTypes.contains(.arrayEnd) {
              // Before processing the end of array, see if we've got an open object and close that first
              if !openedStructures.isEmpty, openedStructures.last == "{" {
                processCloseBracket("}", &indentLevel, options, &formatted)
                openedStructures.removeLast()
              }
              
              if !openedStructures.isEmpty, openedStructures.last == "[" {
                processCloseBracket(char, &indentLevel, options, &formatted)
                openedStructures.removeLast()
              }
              expectedTypes = [.comma, .objectEnd, .arrayEnd]
            }
          case "\"":
            if expectedTypes.contains(.key), !openedStructures.isEmpty, openedStructures.last == "{" {
              currentType = .key
            }
            else if expectedTypes.contains(.value) {
              currentType = .value
            }
            
            formatted.append(char)
            expectedTypes = [.stringEnd]
          case ":":
            if expectedTypes.contains(.colon) {
              formatted.append(":")
              formatted.append(options.valueSeparationChar)
              expectedTypes = [.value, .objectStart, .arrayStart]
            }
            
          case ",":
            if expectedTypes.contains(.comma) {
              processComma(indentLevel, options, &formatted)
              
              if !openedStructures.isEmpty, openedStructures.last == "{" {
                // Inside of an object, a comma should be followed by another key and nothing else
                expectedTypes = [.key]
              }
              else {
                expectedTypes = [.key, .value, .objectStart, .arrayStart]
              }
            }
            
          default:
            if !char.isWhitespace, expectedTypes.contains(.value) {
              formatted.append(char)
              expectedTypes = [.value, .comma, .objectEnd, .arrayEnd]
            }
        }
      }
      
      currentIndex = json.index(after: currentIndex)
    }
    
    // Close any remaining open structures
    closeOpenStructures(&indentLevel, &openedStructures, &expectedTypes, options, &formatted)
    
    return formatted.toString()
  }
  
  /// Sanitizes and formats the input JSON string
  /// - Parameters:
  ///   - json: The input JSON data, potentially malformed
  ///   - options: Formatting options (default is .prettyPrint)
  /// - Returns: A sanitized and formatted JSON string
  public static func sanitize(_ data: Data, options: Options = .prettyPrint) -> String? {
    guard let json = String(data: data, encoding: .utf8) else {
      return nil
    }
    return SwiftJSONSanitizer.sanitize(json, options: options)
  }
  
  /// Sanitizes and formats the input JSON data
  /// - Parameters:
  ///   - data: The input JSON data, potentially malformed
  ///   - options: Formatting options (default is .prettyPrint)
  /// - Returns: Sanitized and formatted JSON data, or nil if the input couldn't be processed
  public static func sanitizeData(_ data: Data, options: Options = .prettyPrint) -> Data? {
    guard let json = String(data: data, encoding: .utf8) else {
      return nil
    }
    
    let sanitizedString = SwiftJSONSanitizer.sanitize(json, options: options)
    return sanitizedString.data(using: .utf8)
  }
}

// MARK: - Private

extension SwiftJSONSanitizer {
  /// Removes any trailing commas from the formatted string
  /// - Parameter str: The input StringBuilder
  private static func removeTrailingComma(_ str: inout StringBuilder) {
    if let lastNonWhitespaceIndex = str.lastIndex(where: { !$0.isWhitespace }) {
      if str[lastNonWhitespaceIndex] == "," {
        str.remove(at: lastNonWhitespaceIndex)
        
        // Remove any trailing whitespace
        while let lastChar = str.last, lastChar.isWhitespace {
          str.removeLast()
        }
      }
    }
  }
  
  /// Processes an opening bracket or brace
  /// - Parameters:
  ///   - bracket: The opening bracket or brace character
  ///   - indentLevel: The current indentation level (will be incremented)
  ///   - options: Formatting options
  ///   - formatted: The StringBuilder to append the formatted string
  private static func processOpenBracket(_ bracket: Character, _ indentLevel: inout Int, _ options: Options, _ formatted: inout StringBuilder) {
    indentLevel += 1
    formatted.append(bracket)
    formatted.append(options.newLineChar)
    formatted.append(String(repeating: options.indentChar, count: indentLevel))
  }
  
  /// Processes a closing bracket or brace
  /// - Parameters:
  ///   - bracket: The closing bracket or brace character
  ///   - indentLevel: The current indentation level (will be decremented)
  ///   - options: Formatting options
  ///   - formatted: The StringBuilder to append the formatted string
  private static func processCloseBracket(_ bracket: Character, _ indentLevel: inout Int, _ options: Options, _ formatted: inout StringBuilder) {
    indentLevel = max(0, indentLevel - 1)
    formatted.append(options.newLineChar)
    formatted.append(String(repeating: options.indentChar, count: indentLevel))
    formatted.append(bracket)
  }
  
  /// Processes a comma
  /// - Parameters:
  ///   - indentLevel: The current indentation level
  ///   - options: Formatting options
  ///   - formatted: The StringBuilder to append the formatted string
  private static func processComma(_ indentLevel: Int, _ options: Options, _ formatted: inout StringBuilder) {
    formatted.append(",")
    formatted.append(options.newLineChar)
    formatted.append(String(repeating: options.indentChar, count: indentLevel))
  }
  
  /// Closes open structures up to a specified limit
  /// - Parameters:
  ///   - indentLevel: The current indentation level (will be updated)
  ///   - openedStructures: Array of currently open structure characters
  ///   - expectedTypes: Set of expected next token types (will be updated)
  ///   - options: Formatting options
  ///   - formatted: The StringBuilder to append the formatted string
  ///   - limit: Maximum number of structures to close (default is Int.max)
  private static func closeOpenStructures(_ indentLevel: inout Int,
                                          _ openedStructures: inout [Character],
                                          _ expectedTypes: inout Set<ExpectedType>,
                                          _ options: Options,
                                          _ formatted: inout StringBuilder,
                                          limit: Int = Int.max) {
    // If indentLevel is 0 or there are no opened structures, we shouldn't close anything
    if indentLevel == 0 || openedStructures.isEmpty {
      return
    }
    
    var closedCount = 0
    while !openedStructures.isEmpty, indentLevel > 0, closedCount < limit {
      let lastOpen = openedStructures.removeLast()
      let closingBracket: Character = lastOpen == "{" ? "}" : "]"
      processCloseBracket(closingBracket, &indentLevel, options, &formatted)
      closedCount += 1
    }
    
    // After closing structures, we expect either the end of input, a comma, or more closing brackets
    expectedTypes = openedStructures.isEmpty ? [.comma] : [.comma, .objectEnd, .arrayEnd]
  }
}
