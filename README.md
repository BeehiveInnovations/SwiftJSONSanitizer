# SwiftJSONSanitizer

SwiftJSONSanitizer is a Swift library that sanitizes and formats potentially malformed JSON strings. It's designed to handle common JSON formatting issues, such as missing closing brackets or braces, making it a robust solution for cleaning up and prettifying JSON data.

Regrettably, even code deployed in production environments can occasionally generate malformed JSON. Swift's built-in JSONDecoder lacks the ability to process such erroneous JSON, including issues as minor as an extra brace or a missing bracket. To address this, `SwiftJSONSanitizer` serves as an effective intermediary. It sanitizes JSON text by correcting these errors before the data is processed by JSONDecoder, providing a reliable failover mechanism.

It's recommended to first attempt decoding with the standard JSONDecoder, and if that fails, sanitize a minified version of the string using this library before trying again. This approach ensures that you're only using the sanitizer when necessary, maintaining optimal performance for well-formed JSON.

## Features

- Sanitizes malformed JSON by adding missing closing brackets and braces
- Formats JSON with customizable indentation and line breaks
- Supports both pretty-printing and minification of JSON
- Handles nested structures and complex JSON hierarchies
- Efficient string building for improved performance
- Seamless integration with Swift's JSONDecoder for robust JSON parsing

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/SwiftJSONSanitizer.git", from: "1.0.0")
]
```

## Usage

### Basic Usage

```swift
import SwiftJSONSanitizer

let malformedJSON = """
{"name": "John", "age": 30, "city": "New York"
"""

let sanitizedJSON = SwiftJSONSanitizer.sanitize(malformedJSON)
print(sanitizedJSON)
```

Output:
```json
{
  "name": "John",
  "age": 30,
  "city": "New York"
}
```

### Minification

```swift
let prettyJSON = """
{
  "users": [
    {
      "name": "Alice",
      "age": 28
    },
    {
      "name": "Bob",
      "age": 32
    }
  ]
}
"""

let minifiedJSON = SwiftJSONSanitizer.sanitize(prettyJSON, options: .minify)
print(minifiedJSON)
```

Output:
```json
{"users":[{"name":"Alice","age":28},{"name":"Bob","age":32}]}
```

### Custom Formatting

```swift
let customOptions = SwiftJSONSanitizer.Options(indent: "    ", newLine: "\n", separator: " ")
let customFormattedJSON = SwiftJSONSanitizer.sanitize(malformedJSON, options: customOptions)
print(customFormattedJSON)
```

Output:
```json
{
    "name": "John",
    "age": 30,
    "city": "New York"
}
```

### Integration with JSONDecoder

Here's an example of how to use SwiftJSONSanitizer in conjunction with JSONDecoder as a failover:

```swift
import Foundation
import SwiftJSONSanitizer

struct User: Codable {
    let name: String
    let age: Int
    let city: String
}

func decodeUser(from jsonString: String) throws -> User? {
    let decoder = JSONDecoder()
    
    do {
        // First, try to decode the original JSON string
        let data = jsonString.data(using: .utf8)!
        return try decoder.decode(User.self, from: data)
    } catch {
        // If decoding fails, sanitize the JSON and try again
        let sanitizedJSON = SwiftJSONSanitizer.sanitize(jsonString, options: .minify)
        let sanitizedData = sanitizedJSON.data(using: .utf8)!
        return try? decoder.decode(User.self, from: sanitizedData)
    }
}

// Usage
let malformedJSON = """
{"name": "John", "age": 30, "city": "New York"
"""

do {
    let user = try decodeUser(from: malformedJSON)
    print("Decoded user: \(user)")
} catch {
    print("Failed to decode user: \(error)")
}
```

This approach first attempts to decode the original JSON string. If that fails, it sanitizes the JSON using SwiftJSONSanitizer and attempts to decode again, providing a more robust JSON parsing solution.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
