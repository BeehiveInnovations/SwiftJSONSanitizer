//
//  StringBuilder.swift
//  SwiftJSONSanitizer
//
//  Created by Fahad Gilani on 13/10/2024.
//

/// A more efficient string builder for constructing large strings
struct StringBuilder {
  private var buffer: String
  
  init(capacity: Int = 256) {
    self.buffer = ""
    self.buffer.reserveCapacity(capacity)
  }
  
  mutating func append(_ character: Character) {
    buffer.append(character)
  }
  
  mutating func append(_ string: String) {
    buffer.append(string)
  }
  
  mutating func remove(at index: Int) {
    let idx = buffer.index(buffer.startIndex, offsetBy: index)
    buffer.remove(at: idx)
  }
  
  mutating func removeLast() {
    buffer.removeLast()
  }
  
  var last: Character? {
    buffer.last
  }
  
  func lastIndex(where predicate: (Character) -> Bool) -> Int? {
    if let idx = buffer.lastIndex(where: predicate) {
      return buffer.distance(from: buffer.startIndex, to: idx)
    }
    return nil
  }
  
  subscript(index: Int) -> Character {
    let idx = buffer.index(buffer.startIndex, offsetBy: index)
    return buffer[idx]
  }
  
  func toString() -> String {
    return buffer
  }
}
