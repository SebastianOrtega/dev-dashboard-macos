import Foundation

enum ShellError: LocalizedError {
    case launchFailed(String)
    case nonZeroExit(code: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        case .nonZeroExit(let code, let output):
            if output.isEmpty {
                return "Command failed with exit code \(code)."
            }
            return output
        }
    }
}

enum Shell {
    static func run(
        _ executable: String,
        arguments: [String],
        allowNonZeroExit: Bool = false
    ) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        let errorOutput = String(decoding: errorData, as: UTF8.self)

        if process.terminationStatus != 0 && !allowNonZeroExit {
            throw ShellError.nonZeroExit(
                code: process.terminationStatus,
                output: errorOutput.isEmpty ? output : errorOutput
            )
        }

        return output
    }
}
