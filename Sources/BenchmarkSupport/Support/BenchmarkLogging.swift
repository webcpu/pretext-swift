import Foundation

func benchmarkProfileLogURL(fileManager: FileManager = .default) -> URL {
    fileManager.temporaryDirectory.appendingPathComponent("pretext-profile.log")
}

func openBenchmarkProfileLogHandle(fileManager: FileManager = .default) throws -> FileHandle {
    let url = benchmarkProfileLogURL(fileManager: fileManager)

    if !fileManager.fileExists(atPath: url.path) {
        let created = fileManager.createFile(atPath: url.path, contents: nil)
        if !created {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }

    return try FileHandle(forWritingTo: url)
}
