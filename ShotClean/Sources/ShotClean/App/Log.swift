import OSLog

/// Loggers for the app. Never log OCR text or other screenshot content as `.public`.
enum Log {
  static let subsystem = "com.hofang42.ShotClean"

  static let app = Logger(subsystem: subsystem, category: "app")
  static let library = Logger(subsystem: subsystem, category: "library")
  static let analysis = Logger(subsystem: subsystem, category: "analysis")
  static let cache = Logger(subsystem: subsystem, category: "cache")
}
