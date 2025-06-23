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

  /// Fast bitmask-based OptionSet for expected tokens (performance optimization)
  private struct ExpectedTokens: OptionSet {
    let rawValue: UInt16
    
    static let objectStart      = ExpectedTokens(rawValue: 1 << 0)  // {
    static let objectEnd        = ExpectedTokens(rawValue: 1 << 1)  // }
    static let arrayStart       = ExpectedTokens(rawValue: 1 << 2)  // [
    static let arrayEnd         = ExpectedTokens(rawValue: 1 << 3)  // ]
    static let keyStart         = ExpectedTokens(rawValue: 1 << 4)  // " (key start)
    static let keyEnd           = ExpectedTokens(rawValue: 1 << 5)  // " (key end)
    static let colon            = ExpectedTokens(rawValue: 1 << 6)  // :
    static let valueStringStart = ExpectedTokens(rawValue: 1 << 7)  // " (value start)
    static let valueStringEnd   = ExpectedTokens(rawValue: 1 << 8)  // " (value end)
    static let valueNumber      = ExpectedTokens(rawValue: 1 << 9)  // number
    static let valueBoolean     = ExpectedTokens(rawValue: 1 << 10) // true/false
    static let valueNull        = ExpectedTokens(rawValue: 1 << 11) // null
    static let comma            = ExpectedTokens(rawValue: 1 << 12) // ,
    static let doubleQuotes     = ExpectedTokens(rawValue: 1 << 13) // "
    
    static let allValueTypes: ExpectedTokens = [.valueStringStart, .valueNumber, .valueBoolean, .valueNull]
  }

  /// Pre-computed indentation cache for performance optimization
  private struct IndentationCache {
    private let newLineBytes: [UInt8]
    private let indentBytes: [UInt8]
    private let cache: [[UInt8]]
    private let maxDepth: Int
    
    init(indentBytes: [UInt8], newLineBytes: [UInt8], maxDepth: Int = 64) {
      self.indentBytes = indentBytes
      self.newLineBytes = newLineBytes
      self.maxDepth = maxDepth
      
      // Pre-compute indentation for up to maxDepth levels
      var cache: [[UInt8]] = []
      cache.reserveCapacity(maxDepth + 1)
      
      // Level 0: just newline
      cache.append(newLineBytes)
      
      // Levels 1 to maxDepth: newline + repeated indentation
      for level in 1...maxDepth {
        var levelBytes = newLineBytes
        for _ in 0..<level {
          levelBytes.append(contentsOf: indentBytes)
        }
        cache.append(levelBytes)
      }
      
      self.cache = cache
    }
    
    func getIndentation(level: Int) -> [UInt8] {
      if level < cache.count {
        return cache[level]
      } else {
        // Fallback for very deep nesting beyond cache
        var result = newLineBytes
        for _ in 0..<level {
          result.append(contentsOf: indentBytes)
        }
        return result
      }
    }
    
    func getNewLine() -> [UInt8] {
      return newLineBytes
    }
  }
  
  /// Sanitizes and formats the input JSON string using optimized byte-level processing
  /// - Parameters:
  ///   - json: The input JSON string, potentially malformed
  ///   - options: Formatting options (default is .prettyPrint)
  /// - Returns: A sanitized and formatted JSON string
  public static func sanitize(_ json: String, options: Options = .prettyPrint) -> String {
    // Use optimized UTF-8 byte processing for better performance
    let utf8Bytes = Array(json.utf8)
    return sanitizeBytes(utf8Bytes, options: options)
  }

  /// Internal method: Sanitizes and formats JSON using byte-level processing for optimal performance
  /// - Parameters:
  ///   - bytes: The input JSON as UTF-8 bytes, potentially malformed
  ///   - options: Formatting options
  /// - Returns: A sanitized and formatted JSON string
  private static func sanitizeBytes(_ bytes: [UInt8], options: Options) -> String {
    var outputBuffer = ContiguousArray<UInt8>()
    outputBuffer.reserveCapacity(bytes.count + (bytes.count / 2)) // Reserve extra space for formatting
    
    var indentLevel = 0
    var currentIndex = 0
    
    /// Flag set when we're escaping an encountered `\` character within a key / value
    var escaping = false
    
    /// Flag set when we've encountered a key and are now looking for a valid value type
    var valueWillStart = false
    /// Flag set when a value is being ignored as bogus
    var valueBeingIgnored = false
    
    var expectedTypes: ExpectedTokens = [.objectStart, .arrayStart]
    var openedStructures = [UInt8]()
    
    // Convert options to UTF-8 bytes for faster processing
    let indentBytes = Array(options.indentChar.utf8)
    let newLineBytes = Array(options.newLineChar.utf8)
    let valueSeparationBytes = Array(options.valueSeparationChar.utf8)
    
    // Create indentation cache for performance
    let indentCache = IndentationCache(indentBytes: indentBytes, newLineBytes: newLineBytes)
    
    // Skip leading whitespace
    while currentIndex < bytes.count, isWhitespace(bytes[currentIndex]) {
      currentIndex += 1
    }
    
    // Check if the JSON starts with a valid JSON opening character
    let isValidJsonStart: Bool
    let startingStructure: UInt8
    
    if currentIndex < bytes.count {
      let firstNonWhitespace = bytes[currentIndex]
      if firstNonWhitespace == 0x7B || firstNonWhitespace == 0x5B { // '{' or '['
        isValidJsonStart = true
        startingStructure = firstNonWhitespace
      } else {
        // Determine the starting structure (object or array)
        let firstRelevantIndex = bytes.firstIndex { byte in
          byte == 0x7D || byte == 0x5D // '}' or ']'
        } ?? bytes.count
        
        let firstRelevantByte = firstRelevantIndex < bytes.count ? bytes[firstRelevantIndex] : 0x7D
        startingStructure = firstRelevantByte == 0x7D ? 0x7B : 0x5B // '{' or '['
        
        isValidJsonStart = false
      }
    } else {
      isValidJsonStart = false
      startingStructure = 0x7B // '{'
    }
    
    if !isValidJsonStart {
      // Prepend with an opening brace or bracket if the JSON does not start with a valid opening character
      processOpenBracketBytes(startingStructure, &indentLevel, indentCache, &outputBuffer)
      openedStructures.append(startingStructure)
      
      if startingStructure == 0x7B { // '{'
        expectedTypes = [.keyStart, .objectEnd]
      } else if startingStructure == 0x5B { // '['
        expectedTypes = [.keyStart, .arrayEnd]
      } else {
        valueWillStart = true
        expectedTypes = [.valueStringStart, .valueNumber, .valueBoolean, .valueNull, .objectStart, .arrayStart, .arrayEnd]
      }
    }
    
    while currentIndex < bytes.count {
      let byte = bytes[currentIndex]
      
      switch byte {
        case 0x7B: // '{'
          if !openedStructures.isEmpty, indentLevel > 0, !expectedTypes.contains(.arrayStart) {
            removeTrailingCommaBytes(&outputBuffer)
            
            // Close any open structures if necessary
            closeOpenStructuresBytes(&indentLevel, &openedStructures, &expectedTypes, indentCache, &outputBuffer, limit: 1)
            
            // Add a trailing comma
            processCommaBytes(indentLevel, indentCache, &outputBuffer)
          }
          
          processOpenBracketBytes(byte, &indentLevel, indentCache, &outputBuffer)
          openedStructures.append(byte)
          expectedTypes = [.keyStart, .objectEnd]
          
        case 0x5B: // '['
          if !openedStructures.isEmpty, indentLevel > 0, !expectedTypes.contains(.arrayStart) {
            removeTrailingCommaBytes(&outputBuffer)
            
            // Close any open structures if necessary
            closeOpenStructuresBytes(&indentLevel, &openedStructures, &expectedTypes, indentCache, &outputBuffer, limit: 1)
            
            // Add a trailing comma
            processCommaBytes(indentLevel, indentCache, &outputBuffer)
          }
          
          processOpenBracketBytes(byte, &indentLevel, indentCache, &outputBuffer)
          openedStructures.append(byte)
          
          valueWillStart = true
          expectedTypes = [.valueStringStart, .valueNumber, .valueBoolean, .valueNull, .objectStart, .arrayStart, .arrayEnd]
          
        case 0x7D: // '}'
          if expectedTypes.contains(.objectEnd) {
            removeTrailingCommaBytes(&outputBuffer)

            // Before processing the end of object, see if we've got an open array and close that first
            if !openedStructures.isEmpty, openedStructures.last == 0x5B { // '['
              processCloseBracketBytes(0x5D, &indentLevel, indentCache, &outputBuffer) // ']'
              openedStructures.removeLast()
            }
            
            if !openedStructures.isEmpty, openedStructures.last == 0x7B { // '{'
              processCloseBracketBytes(byte, &indentLevel, indentCache, &outputBuffer)
              openedStructures.removeLast()
            }
            expectedTypes = [.comma, .objectEnd, .arrayEnd]
          }
          
        case 0x5D: // ']'
          if expectedTypes.contains(.arrayEnd) {
            removeTrailingCommaBytes(&outputBuffer)

            // Before processing the end of array, see if we've got an open object and close that first
            if !openedStructures.isEmpty, openedStructures.last == 0x7B { // '{'
              processCloseBracketBytes(0x7D, &indentLevel, indentCache, &outputBuffer) // '}'
              openedStructures.removeLast()
            }
            
            if !openedStructures.isEmpty, openedStructures.last == 0x5B { // '['
              processCloseBracketBytes(byte, &indentLevel, indentCache, &outputBuffer)
              openedStructures.removeLast()
            }
            expectedTypes = [.comma, .objectEnd, .arrayEnd]
          }
          
        case 0x22: // '"'
          if expectedTypes.contains(.keyEnd) {
            outputBuffer.append(byte)

            if escaping {
              // this quote is being escaped, we haven't ended yet
              escaping = false
            } else {
              expectedTypes = [.colon]
            }
          } else if expectedTypes.contains(.valueStringStart) {
            outputBuffer.append(byte)

            // Found start of string, expect it to end
            expectedTypes = [.valueStringEnd]
          } else if expectedTypes.contains(.valueStringEnd) {
            outputBuffer.append(byte)

            if escaping {
              // quote within the value is being escaped, we haven't ended yet
              escaping = false
            } else {
              // Expect a comma for more strings in an array, or a } or ]
              expectedTypes = [.comma, .objectEnd, .arrayEnd]
            }
          } else if !openedStructures.isEmpty, openedStructures.last == 0x7B, expectedTypes.contains(.keyStart) { // '{'
            outputBuffer.append(byte)

            expectedTypes = [.keyEnd]
          }
          
        case 0x3A: // ':'
          if expectedTypes.contains(.colon) {
            outputBuffer.append(byte)
            outputBuffer.append(contentsOf: valueSeparationBytes)
            
            valueWillStart = true
            expectedTypes = [.valueStringStart, .valueNumber, .valueBoolean, .valueNull, .objectStart, .arrayStart]
          }
          
        case 0x2C: // ','
          if expectedTypes.contains(.comma), !expectedTypes.contains(.valueStringEnd) {
            if valueBeingIgnored {
              valueBeingIgnored.toggle()
            } else {
              processCommaBytes(indentLevel, indentCache, &outputBuffer)
            }
            
            if !openedStructures.isEmpty, openedStructures.last == 0x7B { // '{'
              // Inside of an object, a comma should be followed by another key and nothing else
              expectedTypes = [.keyStart]
            } else {
              valueWillStart = true
              expectedTypes = [.keyStart, .valueStringStart, .valueNumber, .valueBoolean, .valueNull, .objectStart, .arrayStart, .arrayEnd]
            }
          }
          
        default:
          // Handle unknown characters, could be accumulating a string or looking
          // to start a new structure
          
          if expectedTypes.contains(.keyEnd) || expectedTypes.contains(.valueStringEnd) {
            // accumulating a string, expecting to end eventually
            outputBuffer.append(byte)
            
            if escaping {
              escaping = false
            } else if byte == 0x5C { // '\'
              escaping = true
            }
          } else if !isWhitespace(byte) {
            // When we're here, we're not accumulating characters for a string (key or value)
            // and we haven't encountered any of the known object structures
            
            if valueWillStart {
              valueWillStart = false
              
              // We haven't found an a beginning of a string, an array or an object,
              // the only valid values can now be:
              // * null
              // * number
              // * boolean
              
              // If it's neither of these, we're going to assume this is a string with a missing
              // double quotes and insert it ourselves
              if expectedTypes.contains(.valueNull), peekBytesMatch(bytes, from: currentIndex, match: [0x6E, 0x75, 0x6C, 0x6C]) { // "null"
                // Handle null
                outputBuffer.append(contentsOf: [0x6E, 0x75, 0x6C, 0x6C]) // "null"
                
                // Advance past "null"
                currentIndex += 4
                
                expectedTypes = [.comma, .objectEnd, .arrayEnd]
                continue
              } else if expectedTypes.contains(.valueBoolean), peekBytesMatch(bytes, from: currentIndex, match: [0x74, 0x72, 0x75, 0x65]) { // "true"
                // Handle true
                outputBuffer.append(contentsOf: [0x74, 0x72, 0x75, 0x65]) // "true"
                
                // Advance past "true"
                currentIndex += 4
                
                expectedTypes = [.comma, .objectEnd, .arrayEnd]
                continue
              } else if expectedTypes.contains(.valueBoolean), peekBytesMatch(bytes, from: currentIndex, match: [0x66, 0x61, 0x6C, 0x73, 0x65]) { // "false"
                // Handle false
                outputBuffer.append(contentsOf: [0x66, 0x61, 0x6C, 0x73, 0x65]) // "false"
                
                // Advance past "false"
                currentIndex += 5
                
                expectedTypes = [.comma, .objectEnd, .arrayEnd]
                continue
              } else if expectedTypes.contains(.valueNumber), isDigit(byte) || byte == 0x2E || byte == 0x2D { // '.' or '-'
                // Accumulate number
                outputBuffer.append(byte)
                
                // We expect more numbers or a comma (if within an array) or an end of structure
                expectedTypes = [.valueNumber, .comma, .objectEnd, .arrayEnd]
              } else {
                // This is an unknown value, we cannot know where it ends and so
                // the only sensible thing to do is to add a `null` and then wait for it to end
                outputBuffer.append(contentsOf: [0x6E, 0x75, 0x6C, 0x6C]) // "null"
                
                valueBeingIgnored = true
                
                // We expect to end the string
                expectedTypes = [.comma, .objectEnd, .arrayEnd]
              }
            } else if expectedTypes.contains(.valueNumber) {
              // Accumulate number
              outputBuffer.append(byte)
              
              // We expect more numbers or a comma (if within an array) or an end of structure
              expectedTypes = [.valueNumber, .comma, .objectEnd, .arrayEnd]
            }
          }
      }
      
      currentIndex += 1
    }
    
    // Close any remaining open structures
    closeOpenStructuresBytes(&indentLevel, &openedStructures, &expectedTypes, indentCache, &outputBuffer)
    
    return String(bytes: outputBuffer, encoding: .utf8) ?? ""
  }

  /// Original string-based sanitization method (kept for compatibility/comparison)
  /// - Parameters:
  ///   - json: The input JSON string, potentially malformed
  ///   - options: Formatting options (default is .prettyPrint)
  /// - Returns: A sanitized and formatted JSON string
  private static func sanitizeString(_ json: String, options: Options = .prettyPrint) -> String {
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
		  if expectedTypes.contains(.valueStringEnd) {
			  formatted.append(char)
			  break
		  }

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
		  if expectedTypes.contains(.valueStringEnd) {
			  formatted.append(char)
			  break
		  }
		  
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
		  if expectedTypes.contains(.valueStringEnd) {
			  formatted.append(char)
			  break
		  }

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
		  if expectedTypes.contains(.valueStringEnd) {
			  formatted.append(char)
			  break
		  }

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
            openedStructures.append(char)

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
			  openedStructures.removeLast()
              expectedTypes = [.comma, .objectEnd, .arrayEnd]
            }
          }
          else if !openedStructures.isEmpty, openedStructures.last == ExpectedType.objectStart.char(), expectedTypes.contains(.keyStart) {
            formatted.append(char)

            expectedTypes = [.keyEnd]
          }
        case ExpectedType.colon.char():
		  if expectedTypes.contains(.valueStringEnd) {
			  formatted.append(char)
			  break
		  }

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
		  if expectedTypes.contains(.valueStringEnd) {
			  formatted.append(char)
			  break
		  }

          if expectedTypes.contains(.comma) {
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
          
          if expectedTypes.contains(.keyEnd) || expectedTypes.contains(.valueStringEnd) {
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
  
  /// Processes a closing string
  /// - Parameters:
  ///   - formatted: The StringBuilder to append the formatted string
  private static func processCloseString(_ formatted: inout StringBuilder) {
    formatted.append(ExpectedType.valueStringEnd.char())
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
      if lastOpen == ExpectedType.valueStringStart.char() {
        processCloseString(&formatted)
      } else {
        let closingBracket: Character = lastOpen == ExpectedType.objectStart.char() ? ExpectedType.objectEnd.char() : ExpectedType.arrayEnd.char()
        processCloseBracket(closingBracket, &indentLevel, options, &formatted)
      }
      closedCount += 1
    }
    
    // After closing structures, we expect either the end of input, a comma, or more closing brackets
    expectedTypes = openedStructures.isEmpty ? [.comma] : [.comma, .objectEnd, .arrayEnd]
  }

  // MARK: - Byte-level Helper Functions
  
  /// Checks if a UTF-8 byte represents whitespace
  private static func isWhitespace(_ byte: UInt8) -> Bool {
    return byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D // space, tab, newline, carriage return
  }
  
  /// Checks if a UTF-8 byte represents a digit
  private static func isDigit(_ byte: UInt8) -> Bool {
    return byte >= 0x30 && byte <= 0x39 // '0' to '9'
  }
  
  /// Peeks ahead to check if bytes match a specific sequence
  private static func peekBytesMatch(_ bytes: [UInt8], from index: Int, match pattern: [UInt8]) -> Bool {
    guard index + pattern.count <= bytes.count else { return false }
    
    for i in 0..<pattern.count {
      let byte = bytes[index + i]
      let expectedByte = pattern[i]
      // Case-insensitive comparison for ASCII letters
      let normalizedByte = (byte >= 0x41 && byte <= 0x5A) ? byte + 0x20 : byte
      let normalizedExpected = (expectedByte >= 0x41 && expectedByte <= 0x5A) ? expectedByte + 0x20 : expectedByte
      if normalizedByte != normalizedExpected {
        return false
      }
    }
    return true
  }
  
  /// Removes any trailing commas from the output buffer
  private static func removeTrailingCommaBytes(_ buffer: inout ContiguousArray<UInt8>) {
    // Find last non-whitespace byte
    var lastNonWhitespaceIndex: Int?
    for i in stride(from: buffer.count - 1, through: 0, by: -1) {
      if !isWhitespace(buffer[i]) {
        lastNonWhitespaceIndex = i
        break
      }
    }
    
    if let index = lastNonWhitespaceIndex, buffer[index] == 0x2C { // ','
      buffer.remove(at: index)
      
      // Remove any trailing whitespace
      while !buffer.isEmpty && isWhitespace(buffer.last!) {
        buffer.removeLast()
      }
    }
  }
  
  /// Processes an opening bracket or brace (byte version)
  private static func processOpenBracketBytes(_ bracket: UInt8, _ indentLevel: inout Int, _ indentCache: IndentationCache, _ buffer: inout ContiguousArray<UInt8>) {
    indentLevel += 1
    buffer.append(bracket)
    buffer.append(contentsOf: indentCache.getIndentation(level: indentLevel))
  }
  
  /// Processes a closing bracket or brace (byte version)
  private static func processCloseBracketBytes(_ bracket: UInt8, _ indentLevel: inout Int, _ indentCache: IndentationCache, _ buffer: inout ContiguousArray<UInt8>) {
    indentLevel = max(0, indentLevel - 1)
    buffer.append(contentsOf: indentCache.getIndentation(level: indentLevel))
    buffer.append(bracket)
  }
  
  /// Processes a comma (byte version)
  private static func processCommaBytes(_ indentLevel: Int, _ indentCache: IndentationCache, _ buffer: inout ContiguousArray<UInt8>) {
    buffer.append(0x2C) // ','
    buffer.append(contentsOf: indentCache.getIndentation(level: indentLevel))
  }
  
  /// Closes open structures up to a specified limit (byte version)
  private static func closeOpenStructuresBytes(_ indentLevel: inout Int,
                                               _ openedStructures: inout [UInt8],
                                               _ expectedTypes: inout ExpectedTokens,
                                               _ indentCache: IndentationCache,
                                               _ buffer: inout ContiguousArray<UInt8>,
                                               limit: Int = Int.max) {
    // If indentLevel is 0 or there are no opened structures, we shouldn't close anything
    if indentLevel == 0 || openedStructures.isEmpty {
      return
    }
    
    var closedCount = 0
    while !openedStructures.isEmpty, indentLevel > 0, closedCount < limit {
      let lastOpen = openedStructures.removeLast()
      let closingBracket: UInt8 = lastOpen == 0x7B ? 0x7D : 0x5D // '{' -> '}', '[' -> ']'
      processCloseBracketBytes(closingBracket, &indentLevel, indentCache, &buffer)
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
