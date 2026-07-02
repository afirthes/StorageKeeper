import Foundation
import UIKit

enum ItemImageStore {
    private static let directoryName = "ItemPhotos"

    static func loadImage(named filename: String?) -> UIImage? {
        guard let filename, let url = imageURL(for: filename) else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }

    static func savePhotoData(_ data: Data, replacing filename: String?) throws -> String {
        let finalFilename = filename ?? "\(UUID().uuidString).jpg"
        let url = try directoryURL().appendingPathComponent(finalFilename)

        if let image = UIImage(data: data),
           let jpegData = image.jpegData(compressionQuality: 0.82) {
            try jpegData.write(to: url, options: .atomic)
        } else {
            try data.write(to: url, options: .atomic)
        }

        return finalFilename
    }

    static func deletePhoto(named filename: String?) {
        guard let filename, let url = imageURL(for: filename) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    private static func imageURL(for filename: String) -> URL? {
        try? directoryURL().appendingPathComponent(filename)
    }

    private static func directoryURL() throws -> URL {
        let fileManager = FileManager.default
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent(directoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }
}
