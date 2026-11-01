import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ConverterModel: ObservableObject {
    @Published var isoURL: URL?
    @Published var outputURL: URL?
    @Published var status = "Choose a backup ISO to begin."
    @Published var isWorking = false
    @Published var progress = 0.0
    @Published var uploadEnabled = false
    @Published var host = ""
    @Published var port = "21"
    @Published var username = ""
    @Published var password = ""
    @Published var remotePath = "/Content/0000000000000000"
    @Published var log = ""
    @Published var showingISO = false
    @Published var showingFolder = false

    func convert() {
        guard let isoURL, let outputURL else { status = "Select an ISO and output folder."; return }
        isWorking = true
        progress = 0
        status = "Converting your backup…"
        log = ""
        let model = self
        Task.detached {
            do {
                let helper = Self.helperURL()
                guard FileManager.default.isExecutableFile(atPath: helper.path) else {
                    throw ConversionError.message("Converter helper not found. Build the release workflow or install iso2god at \(helper.path).")
                }
                let process = Process()
                process.executableURL = helper
                process.arguments = [isoURL.path, outputURL.path]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(decoding: data, as: UTF8.self)
                guard process.terminationStatus == 0 else { throw ConversionError.message(output.isEmpty ? "Converter exited with code \(process.terminationStatus)." : output) }
                await MainActor.run { model.status = "Conversion complete."; model.progress = 1; model.log = output }
                let uploadSettings = await MainActor.run { (model.uploadEnabled, model.host, model.port, model.username, model.password, model.remotePath) }
                if uploadSettings.0 {
                    try await Self.upload(folder: outputURL, host: uploadSettings.1, port: uploadSettings.2, username: uploadSettings.3, password: uploadSettings.4, remotePath: uploadSettings.5)
                    await MainActor.run { model.status = "Conversion and FTP upload complete." }
                }
            } catch {
                await MainActor.run { model.status = error.localizedDescription; model.log = error.localizedDescription }
            }
            await MainActor.run { model.isWorking = false }
        }
    }

    nonisolated private static func helperURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["ISO2GOD_PATH"] { return URL(fileURLWithPath: override) }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("iso2god"), FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/iso2god")
    }

    private static func upload(folder: URL, host: String, port: String, username: String, password: String, remotePath: String) async throws {
        guard !host.isEmpty, let portNumber = Int(port), (1...65535).contains(portNumber), remotePath.hasPrefix("/") else {
            throw ConversionError.message("Check the FTP host, port, and absolute destination path.")
        }
        guard URLComponents(string: "ftp://\(host)")?.host != nil else { throw ConversionError.message("Enter a valid FTP host name or IP address.") }
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        let files = enumerator?.allObjects.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true } ?? []
        guard !files.isEmpty else { throw ConversionError.message("No output files were found in the selected folder.") }
        for file in files {
            let relativePath = String(file.path.dropFirst(folder.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var components = URLComponents()
            components.scheme = "ftp"
            components.host = host
            components.port = portNumber
            components.path = "/" + remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + relativePath
            guard let destination = components.url?.absoluteString else { throw ConversionError.message("Could not form the FTP destination URL.") }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = ["--fail", "--silent", "--show-error", "--ftp-create-dirs", "--upload-file", file.path, destination]
            let credentialsPipe = Pipe()
            process.standardInput = credentialsPipe
            process.arguments?.insert("-", at: 1)
            process.arguments?.insert("--config", at: 1)
            let errorPipe = Pipe(); process.standardError = errorPipe
            process.standardOutput = Pipe()
            try process.run()
            let configEscape: (String) -> String = { $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "") }
            credentialsPipe.fileHandleForWriting.write(Data("user = \"\(configEscape(username)):\(configEscape(password))\"\n".utf8))
            try? credentialsPipe.fileHandleForWriting.close()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw ConversionError.message(String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)) }
        }
    }
}

enum ConversionError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

struct ContentView: View {
    @StateObject private var model = ConverterModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "opticaldisc.fill").font(.system(size: 34)).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text("GOD Toolkit").font(.largeTitle.bold())
                    Text("Convert your Xbox 360 backup for an RGH console").foregroundStyle(.secondary)
                }
            }
            GroupBox("1 · Source backup") {
                HStack {
                    Label(model.isoURL?.lastPathComponent ?? "Select an Xbox 360 ISO you own", systemImage: "externaldrive")
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose ISO…") { model.showingISO = true }
                }.padding(6)
            }
            GroupBox("2 · GOD output folder") {
                HStack {
                    Label(model.outputURL?.path ?? "Choose where the converted package will be saved", systemImage: "folder")
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose Folder…") { model.showingFolder = true }
                }.padding(6)
            }
            GroupBox {
                DisclosureGroup(isExpanded: $model.uploadEnabled) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow { Text("Console host"); TextField("192.168.1.50", text: $model.host); Text("Port"); TextField("21", text: $model.port).frame(width: 64) }
                        GridRow { Text("Username"); TextField("FTP username", text: $model.username); Text("Password"); SecureField("FTP password", text: $model.password) }
                        GridRow { Text("Destination"); TextField("/Content/0000000000000000", text: $model.remotePath).gridCellColumns(3) }
                    }.padding(.top, 12)
                    Text("FTP is unencrypted. Use a trusted local network. Credentials are kept in memory for this session only.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                } label: {
                    Label("Optional FTP upload", systemImage: "network")
                }.padding(6)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { ProgressView(value: model.progress); Text(model.status).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                if !model.log.isEmpty { Text(model.log).font(.system(.caption, design: .monospaced)).lineLimit(3).foregroundStyle(.secondary) }
            }
            HStack {
                Text("For personal backups only. No game files or DRM bypass are included.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.convert() } label: { Label("Convert to GOD", systemImage: "arrow.trianglehead.2.clockwise") }
                    .buttonStyle(.borderedProminent).disabled(model.isWorking || model.isoURL == nil || model.outputURL == nil)
            }
        }
        .padding(28)
        .fileImporter(isPresented: $model.showingISO, allowedContentTypes: [.isoDiskImage, .data], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result { model.isoURL = urls.first }
        }
        .fileImporter(isPresented: $model.showingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result { model.outputURL = urls.first }
        }
        .onChange(of: model.isoURL) { url in if let url { model.status = "Ready to convert \(url.lastPathComponent)." } }
    }
}

extension UTType {
    static let isoDiskImage = UTType(filenameExtension: "iso") ?? .data
}
