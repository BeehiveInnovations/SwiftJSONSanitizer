//
//  StringBuilder.swift
//  SwiftJSONSanitizer
//
//  Created by Fahad Gilani on 13/10/2024.
//

/// A more efficient string builder for constructing large strings
struct StringBuilder {
  private var buffer: [Character]
  private var stringCache: String?
  
  init(capacity: Int = 256) {
    self.buffer = []
    self.buffer.reserveCapacity(capacity)
  }
  
  mutating func append(_ character: Character) {
    buffer.append(character)
    stringCache = nil
  }
  
  mutating func append(_ string: String) {
    buffer.append(contentsOf: string)
    stringCache = nil
  }
  
  mutating func remove(at index: Int) {
    buffer.remove(at: index)
    stringCache = nil
  }
  
  mutating func removeLast() {
    buffer.removeLast()
    stringCache = nil
  }
  
  var last: Character? {
    buffer.last
  }
  
  func lastIndex(where predicate: (Character) -> Bool) -> Int? {
    buffer.lastIndex(where: predicate)
  }
  
  subscript(index: Int) -> Character {
    buffer[index]
  }
  
  mutating func toString() -> String {
    if let cached = stringCache {
      return cached
    }
    let result = String(buffer)
    stringCache = result
    return result
  }
}
