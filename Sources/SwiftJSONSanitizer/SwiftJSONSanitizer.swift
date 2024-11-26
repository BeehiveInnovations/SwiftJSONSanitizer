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
    /// Expecting `{`
    case objectStart
    /// Expecting `}`
    case objectEnd
    /// Expecting `[`
    case arrayStart
    /// Expecting `]`
    case arrayEnd
    /// Expecting `"` after a `{` or `[`
    case keyStart
    /// Expecting a `"` after a `.keyStart` found
    case keyEnd
    /// Expecting a `:` after a `.keyEnd`
    case colon
    /// Expecting `"` to mark the start of a string value
    case valueStringStart
    /// Expecting a `"` to find the end of the string value
    case valueStringEnd
    /// Expecting a number to mark the start of a number value or its continuation
    case valueNumber
    /// Expecting a boolean `t` or `f` to mark the start of a boolean word `true` or `false`
    case valueBoolean
    /// Expecting a `null` word
    case valueNull
    /// Expecting a `,` after a value ends
    case comma
    /// Expecting a double quotation mark
    case doubleQuotes
    
    func char() -> Character {
      switch self {
        case .objectStart:
          "{"
        case .objectEnd:
          "}"
        case .arrayStart:
          "["
        case .arrayEnd:
          "]"
        case .colon:
          ":"
        case .valueNumber:
          fatalError()
        case .valueBoolean:
          fatalError()
        case .valueNull:
          fatalError()
        case .comma:
          ","
        case .keyStart, .keyEnd, .valueStringStart, .valueStringEnd, .doubleQuotes:
          "\""
      }
    }
    
    static var allValueTypes: Set<ExpectedType> {
      return [.valueStringStart, .valueNumber, .valueBoolean, .valueNull]
    }
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
    
    /// Flag set when we're escaping an encountered `\` character within a key / value
    var escaping = false
    
    /// Flat set when we've encountered a key and are now looking for a valid value type
    var valueWillStart = false
    /// Flag set when a value is being ignored as bogus
    var valueBeingIgnored = false
    
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
      if firstNonWhitespace == ExpectedType.objectStart.char() || firstNonWhitespace == ExpectedType.arrayStart.char() {
        isValidJsonStart = true
        startingStructure = firstNonWhitespace
      }
      else {
        // Determine the starting structure (object or array)
        let firstRelevantIndex = json.firstIndex { char in
          char == ExpectedType.objectEnd.char() || char == ExpectedType.arrayEnd.char()
        } ?? json.endIndex
        
        let firstRelevantChar = json[firstRelevantIndex]
        startingStructure = firstRelevantChar == ExpectedType.objectEnd.char()
        ? ExpectedType.objectStart.char()
        : ExpectedType.arrayStart.char()
        
        isValidJsonStart = false
      }
    }
    else {
      isValidJsonStart = false
      startingStructure = ExpectedType.objectStart.char()
    }
    
    if !isValidJsonStart {
      // Prepend with an opening brace or bracket if the JSON does not start with a valid opening character
      processOpenBracket(startingStructure, &indentLevel, options, &formatted)
      openedStructures.append(startingStructure)
      
      if startingStructure == ExpectedType.objectStart.char() {
        expectedTypes = [.keyStart, .objectEnd]
      }
      else if startingStructure == ExpectedType.arrayStart.char() {
        expectedTypes = [.keyStart, .arrayEnd]
      }
      else {
        valueWillStart = true
        
        expectedTypes = [
          .valueStringStart,
          .valueNumber,
          .valueBoolean,
          .valueNull,
          .objectStart,
          .arrayStart,
          .arrayEnd
        ]
      }
    }
    
    while currentIndex < json.endIndex {
      let char = json[currentIndex]
      
      switch char {
        case ExpectedType.objectStart.char():
          if !openedStructures.isEmpty, indentLevel > 0, !expectedTypes.contains(.arrayStart) {
            removeTrailingComma(&formatted)
            
            // Close any open structures if necessary
            closeOpenStructures(&indentLevel, &openedStructures, &expectedTypes, options, &formatted, limit: 1)
            
            // Add a trailing comma
            processComma(indentLevel, options, &formatted)
          }
          
          processOpenBracket(char, &indentLevel, options, &formatted)
          openedStructures.append(char)
          expectedTypes = [.keyStart, .objectEnd]
          
        case ExpectedType.arrayStart.char():
          if !openedStructures.isEmpty, indentLevel > 0, !expectedTypes.contains(.arrayStart) {
            removeTrailingComma(&formatted)
            
            // Close any open structures if necessary
            closeOpenStructures(&indentLevel, &openedStructures, &expectedTypes, options, &formatted, limit: 1)
            
            // Add a trailing comma
            processComma(indentLevel, options, &formatted)
          }
          
          processOpenBracket(char, &indentLevel, options, &formatted)
          openedStructures.append(char)
          
          valueWillStart = true
          
          expectedTypes = [
            .valueStringStart,
            .valueNumber,
            .valueBoolean,
            .valueNull,
            .objectStart,
            .arrayStart,
            .arrayEnd
          ]
        case ExpectedType.objectEnd.char():
          if expectedTypes.contains(.objectEnd) {
            removeTrailingComma(&formatted)

            // Before processing the end of object, see if we've got an open array and close that first
            if !openedStructures.isEmpty, openedStructures.last == ExpectedType.arrayStart.char() {
              processCloseBracket(ExpectedType.arrayEnd.char(), &indentLevel, options, &formatted)
              openedStructures.removeLast()
            }
            
            if !openedStructures.isEmpty, openedStructures.last == ExpectedType.objectStart.char() {
              processCloseBracket(char, &indentLevel, options, &formatted)
              openedStructures.removeLast()
            }
            expectedTypes = [.comma, .objectEnd, .arrayEnd]
          }
          
        case ExpectedType.arrayEnd.char():
          if expectedTypes.contains(.arrayEnd) {
            removeTrailingComma(&formatted)

            // Before processing the end of array, see if we've got an open object and close that first
            if !openedStructures.isEmpty, openedStructures.last == ExpectedType.objectStart.char() {
              processCloseBracket(ExpectedType.objectEnd.char(), &indentLevel, options, &formatted)
              openedStructures.removeLast()
            }
            
            if !openedStructures.isEmpty, openedStructures.last == ExpectedType.arrayStart.char() {
              processCloseBracket(char, &indentLevel, options, &formatted)
              openedStructures.removeLast()
            }
            expectedTypes = [.comma, .objectEnd, .arrayEnd]
          }
        case ExpectedType.doubleQuotes.char():
          if expectedTypes.contains(.keyEnd) {
            formatted.append(char)

            if escaping {
              // this quote is being escaped, we haven't ended yet
              escaping = false
            }
            else {
              expectedTypes = [.colon]
            }
          }
          else if expectedTypes.contains(.valueStringStart) {
            formatted.append(char)

            // Found start of string, expect it to end
            expectedTypes = [.valueStringEnd]
          }
          else if expectedTypes.contains(.valueStringEnd) {
            formatted.append(char)

            if escaping {
              // quote within the value is being escaped, we haven't ended yet
              escaping = false
            }
            else {
              // Expect a comma for more strings in an array, or a } or ]
              expectedTypes = [.comma, .objectEnd, .arrayEnd]
            }
          }
          else if !openedStructures.isEmpty, openedStructures.last == ExpectedType.objectStart.char(), expectedTypes.contains(.keyStart) {
            formatted.append(char)

            expectedTypes = [.keyEnd]
          }
        case ExpectedType.colon.char():
          if expectedTypes.contains(.colon) {
            formatted.append(ExpectedType.colon.char())
            formatted.append(options.valueSeparationChar)
            
            valueWillStart = true
            
            expectedTypes = [
              .valueStringStart,
              .valueNumber,
              .valueBoolean,
              .valueNull,
              .objectStart,
              .arrayStart
            ]
          }
        case ExpectedType.comma.char():
          if expectedTypes.contains(.comma), !expectedTypes.contains(.valueStringEnd) {
            if valueBeingIgnored {
              valueBeingIgnored.toggle()
            }
            else {
              processComma(indentLevel, options, &formatted)
            }
            
            if !openedStructures.isEmpty, openedStructures.last == ExpectedType.objectStart.char() {
              // Inside of an object, a comma should be followed by another key and nothing else
              expectedTypes = [.keyStart]
            }
            else {
              valueWillStart = true
              
              expectedTypes = [
                .keyStart,
                .valueStringStart,
                .valueNumber,
                .valueBoolean,
                .valueNull,
                .objectStart,
                .arrayStart,
                .arrayEnd
              ]
            }
          }
        default:
          // Handle unknown characters, could be accumulating a string or looking
          // to start a new structure
          
          if expectedTypes.containsAny(of: [.keyEnd, .valueStringEnd]) {
            // accumulating a string, expecting to end eventually
            formatted.append(char)
            
            if escaping {
              escaping = false
            }
            else if char == "\\" {
              escaping = true
            }
          }
          else if !char.isWhitespace {
            // When we're here, we're not accumulating characters for a string (key or value)
            // and we haven't encountered any of the known object structures
            
            // [.valueStringStart, .valueNumber, .valueBoolean, .valueNull]
            
            if valueWillStart {
              valueWillStart = false
              
              // We haven't found an a beginning of a string, an array or an object,
              // the only valid values can now be:
              // * null
              // * number
              // * boolean
              
              // If it's neither of these, we're going to assume this is a string with a missing
              // double quotes and insert it ourselves
              if expectedTypes.contains(.valueNull), json.peek(aheadFrom: currentIndex, match: "null") {
                // Handle null
                formatted.append("null")
                
                // Advance past "null"
                currentIndex = json.index(currentIndex, offsetBy: 4)
                
                expectedTypes = [
                  .comma,
                  .objectEnd,
                  .arrayEnd
                ]
                
                continue
              }
              else if expectedTypes.contains(.valueBoolean), json.peek(aheadFrom: currentIndex, match: "true") {
                // Handle true
                formatted.append("true")
                
                // Advance past "true"
                currentIndex = json.index(currentIndex, offsetBy: 4)
                
                expectedTypes = [
                  .comma,
                  .objectEnd,
                  .arrayEnd
                ]
                continue
              }
              else if expectedTypes.contains(.valueBoolean), json.peek(aheadFrom: currentIndex, match: "false") {
                // Handle false
                formatted.append("false")
                
                // Advance past "false"
                currentIndex = json.index(currentIndex, offsetBy: 5)
                
                expectedTypes = [
                  .comma,
                  .objectEnd,
                  .arrayEnd
                ]
                continue
              }
              else if expectedTypes.contains(.valueNumber),
                      char.isNumber || char == "." || char == "-" {
                // Accumulate number
                formatted.append(char)
                
                // We expect more numbers or a comma (if within an array) or an end of structure
                expectedTypes = [
                  .valueNumber,
                  .comma,
                  .objectEnd,
                  .arrayEnd
                ]
              }
              else {
                // This is an unknown value, we cannot know where it ends and so
                // the only sensible thing to do is to add a `null` and then wait for it to end
                formatted.append("null")
                
                valueBeingIgnored = true
                
                // We expect to end the string
                expectedTypes = [
                  .comma,
                  .objectEnd,
                  .arrayEnd
                ]
              }
            }
            else if expectedTypes.contains(.valueNumber) {
              // Accumulate number
              formatted.append(char)
              
              // We expect more numbers or a comma (if within an array) or an end of structure
              expectedTypes = [
                .valueNumber,
                .comma,
                .objectEnd,
                .arrayEnd
              ]
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
      if str[lastNonWhitespaceIndex] == ExpectedType.comma.char() {
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
    formatted.append(ExpectedType.comma.char())
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
      let closingBracket: Character = lastOpen == ExpectedType.objectStart.char() ? ExpectedType.objectEnd.char() : ExpectedType.arrayEnd.char()
      processCloseBracket(closingBracket, &indentLevel, options, &formatted)
      closedCount += 1
    }
    
    // After closing structures, we expect either the end of input, a comma, or more closing brackets
    expectedTypes = openedStructures.isEmpty ? [.comma] : [.comma, .objectEnd, .arrayEnd]
  }
}

extension Set {
  /// Checks if the set contains any element from the provided array.
  func containsAny<S: Sequence>(of elements: S) -> Bool where S.Element == Element {
    return elements.contains { self.contains($0) }
  }
}

extension String {
  /// Peek ahead to see if the next characters match a specific word (supports `Int` or `String.Index`).
  func peek(aheadFrom index: Int, match word: String) -> Bool {
    // Validate the intIndex
    guard index >= 0, index < self.count else { return false }
    let stringIndex = self.index(self.startIndex, offsetBy: index)
    return peek(aheadFrom: stringIndex, match: word)
  }
  
  func peek(aheadFrom index: String.Index, match word: String) -> Bool {
    let endIndex = self.index(index, offsetBy: word.count, limitedBy: self.endIndex) ?? self.endIndex
    return self[index..<endIndex].lowercased() == word.lowercased()
  }
    
  /// Peek ahead to check if the next characters form a number (supports `Int` index).
  func peekNumber(aheadFrom intIndex: Int) -> Double? {
    // Validate the intIndex
    guard intIndex >= 0, intIndex < self.count else { return nil }
    let stringIndex = self.index(self.startIndex, offsetBy: intIndex)
    return peekNumber(aheadFrom: stringIndex)
  }
  
  /// Peek ahead to check if the next characters form a number (supports `String.Index`).
  func peekNumber(aheadFrom index: String.Index) -> Double? {
    var currentIndex = index
    var hasDigits = false
    var isNegative = false
    
    // Check for a leading negative sign
    if currentIndex < self.endIndex && self[currentIndex] == "-" {
      isNegative = true
      currentIndex = self.index(after: currentIndex)
    }
    
    // Track the start of the number
    let numberStart = currentIndex
    var hasDecimalPoint = false
    
    // Loop through the string to check for valid number characters
    while currentIndex < self.endIndex {
      let char = self[currentIndex]
      if char.isNumber {
        hasDigits = true
      } else if char == "." {
        if hasDecimalPoint { // Multiple decimal points are invalid
          break
        }
        hasDecimalPoint = true
      } else {
        break // Stop on invalid characters
      }
      currentIndex = self.index(after: currentIndex)
    }
    
    // If no digits were found, return nil
    guard hasDigits else { return nil }
    
    // Extract the number substring and convert to Double
    let numberSubstring = self[numberStart..<currentIndex]
    if let number = Double(numberSubstring) {
      return isNegative ? -number : number
    }
    
    return nil
  }
}
