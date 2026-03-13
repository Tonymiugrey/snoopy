//
//  ErrorLevel.swift
//  snoopy
//
//  Created by miuGrey on 2025/6/22.
//


import Cocoa
import os.log

enum ErrorLevel: Int {
    case info, debug, warning, error
}

final class LogMessage {
    let date: Date
    let level: ErrorLevel
    let message: String
    var actionName: String?
    var actionBlock: BlockOperation?

    init(level: ErrorLevel, message: String) {
        self.level = level
        self.message = message
        self.date = Date()
    }
}

typealias LoggerCallback = (ErrorLevel) -> Void

final class Logger {
    static let sharedInstance = Logger()

    var callbacks = [LoggerCallback]()

    func addCallback(_ callback:@escaping LoggerCallback) {
        callbacks.append(callback)
    }

    func callBack(level: ErrorLevel) {
        DispatchQueue.main.async {
            for callback in self.callbacks {
                callback(level)
            }
        }
    }
}
var errorMessages = [LogMessage]()
/*
func appSupportPath() -> String {
    var appPath = ""

    // Grab an array of Application Support paths
    let appSupportPaths = NSSearchPathForDirectoriesInDomains(
        .applicationSupportDirectory,
        .userDomainMask,
        true)

    if appSupportPaths.isEmpty {
        errorLog("FATAL : app support does not exist!")
        return "/"
    }

    appPath = appSupportPaths[0]

    let appSupportDirectory = appPath as NSString

    return appSupportDirectory.appendingPathComponent("Aerial")
}*/

// This will clear the existing log if > 1MB
// This is called at startup


// swiftlint:disable:next identifier_name
func Log(level: ErrorLevel, message: String) {
    errorMessages.append(LogMessage(level: level, message: message))

    // We report errors to Console.app
    if level == .error {
        if #available(OSX 10.12, *) {
            // This is faster when available
            let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "Screensaver")
            os_log("AerialError: %{public}@", log: log, type: .error, message)
        } else {
            NSLog("AerialError: \(message)")
        }
    }

    // We may have set callbacks
    if level == .warning || level == .error || (level == .debug) {
        Logger.sharedInstance.callBack(level: level)
    }
        logToConsole(message)
}

func logToConsole(_ message: String) {
    if #available(OSX 10.12, *) {
        // This is faster when available
        let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "Screensaver")
        os_log("Snoopy: %{public}@", log: log, type: .default, message)
    } else {
        NSLog("Snoopy: \(message)")
    }

}

func debugLog(_ message: String) {
    #if DEBUG
    Log(level: .debug, message: message)
    #endif
}

func infoLog(_ message: String) {
    Log(level: .info, message: message)
}

func warnLog(_ message: String) {
    Log(level: .warning, message: message)
}

func errorLog(_ message: String) {
    Log(level: .error, message: "🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨 " + message)
}
