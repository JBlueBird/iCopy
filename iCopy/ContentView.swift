import SwiftUI
import AVFoundation
import AppKit
import Speech
import Foundation
import PDFKit


// MARK: - ViewModel

class iCopyViewModel: ObservableObject {
    
    func transcribeVoiceMemo(_ memo: VoiceMemo) {
        let recognizer = SFSpeechRecognizer()
        guard let recognizer = recognizer, recognizer.isAvailable else {
            print("Speech recognizer not available")
            return
        }

        transcribingMemoID = memo.id
        let request = SFSpeechURLRecognitionRequest(url: memo.url)

        recognizer.recognitionTask(with: request) { result, error in
            DispatchQueue.main.async {
                self.transcribingMemoID = nil
            }

            if let result = result, result.isFinal {
                DispatchQueue.main.async {
                    self.transcripts[memo.id] = result.bestTranscription.formattedString
                }
            } else if let error = error {
                print("Transcription error:", error)
            }
        }
    }
    
    @Published var transcribingMemoID: UUID?
    @Published var transcripts: [UUID: String] = [:]
    // MARK: - Photos
    @Published var photos: [PhotoItem] = []
    @Published var selectedPhotoItems: Set<UUID> = []
    
    // MARK: - Voice Memos
    @Published var voiceMemos: [VoiceMemo] = []
    @Published var selectedVoiceMemos: Set<UUID> = []
    var filteredPhotos: [PhotoItem] {
        guard !searchText.isEmpty else { return photos }
        let lowerSearch = searchText.lowercased()
        return photos.filter { $0.filename.lowercased().contains(lowerSearch) }
    }

    func copySelectedPhotos() {
        let selected = photos.filter { selectedPhotoItems.contains($0.id) }
        copyMediaFiles(selected.map { $0.url }, label: "photo(s)")
    }

    

    var filteredVoiceMemos: [VoiceMemo] {
        guard !searchText.isEmpty else { return voiceMemos }
        let lowerSearch = searchText.lowercased()
        return voiceMemos.filter { $0.title.lowercased().contains(lowerSearch) }
    }

    func copySelectedVoiceMemos() {
        let selected = voiceMemos.filter { selectedVoiceMemos.contains($0.id) }
        copyMediaFiles(selected.map { $0.url }, label: "voice memo(s)")
    }
    
    // MARK: - Photos

    func autoDetectPhotos() {
        DispatchQueue.global(qos: .userInitiated).async {
            let volumes = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
            self.debug("Volumes found: \(volumes)")

            for volumeName in volumes {
                let candidate = URL(fileURLWithPath: "/Volumes/\(volumeName)/Photos")
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                    DispatchQueue.main.async {
                        self.statusMessage = "Photos folder found: \(volumeName)"
                    }
                    self.debug("Detected Photos folder at \(candidate.path)")
                    self.loadPhotos(from: candidate)
                    return
                }
            }
            DispatchQueue.main.async {
                self.statusMessage = "No Photos folder found. Select manually."
                self.photos = []
            }
            self.debug("No Photos folder found.")
        }
    }

    func loadPhotos(from folder: URL) {
        print("🔍 Scanning for photos...")
        DispatchQueue.global(qos: .userInitiated).async {
            var foundPhotos: [PhotoItem] = []
            let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsPackageDescendants])!

            for case let file as URL in enumerator {
                let ext = file.pathExtension.lowercased()
                if ["jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp"].contains(ext) {
                    let thumbnail = NSImage(contentsOf: file)
                    foundPhotos.append(PhotoItem(url: file, filename: file.lastPathComponent, thumbnail: thumbnail))
                }
            }

            DispatchQueue.main.async {
                self.photos = foundPhotos
                self.statusMessage = foundPhotos.isEmpty ? "No photos found." : "Loaded \(foundPhotos.count) photos."
                self.debug("Loaded \(foundPhotos.count) photos.")
            }
        }
    }

    // MARK: - Voice Memos

    func autoDetectVoiceMemos() {
        DispatchQueue.global(qos: .userInitiated).async {
            let volumes = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
            self.debug("Volumes found: \(volumes)")

            for volumeName in volumes {
                let candidate = URL(fileURLWithPath: "/Volumes/\(volumeName)/Recordings")
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                    DispatchQueue.main.async {
                        self.statusMessage = "Voice Memos folder found: \(volumeName)"
                    }
                    self.debug("Detected Voice Memos folder at \(candidate.path)")
                    self.loadVoiceMemos(from: candidate)
                    return
                }
            }
            DispatchQueue.main.async {
                self.statusMessage = "No Voice Memos folder found. Select manually."
                self.voiceMemos = []
            }
            self.debug("No Voice Memos folder found.")
        }
    }

    func loadVoiceMemos(from folder: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            var foundMemos: [VoiceMemo] = []
            let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey], options: [.skipsPackageDescendants])!

            for case let file as URL in enumerator {
                let ext = file.pathExtension.lowercased()
                if ["m4a", "wav", "aac", "caf"].contains(ext) {
                    let asset = AVAsset(url: file)
                    let duration = CMTimeGetSeconds(asset.duration)
                    let title = file.deletingPathExtension().lastPathComponent
                    let dateRecorded = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                    foundMemos.append(VoiceMemo(url: file, title: title, duration: duration, dateRecorded: dateRecorded))
                }
            }

            DispatchQueue.main.async {
                self.voiceMemos = foundMemos
                self.statusMessage = foundMemos.isEmpty ? "No voice memos found." : "Loaded \(foundMemos.count) voice memos."
                self.debug("Loaded \(foundMemos.count) voice memos.")
            }
        }
    }


    // MARK: - General File Copy Helper
    private func copyMediaFiles(_ files: [URL], label: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "Choose a destination folder"

        if panel.runModal() == .OK, let destination = panel.url {
            DispatchQueue.global(qos: .utility).async {
                for url in files {
                    let destURL = destination.appendingPathComponent(url.lastPathComponent)
                    do {
                        if FileManager.default.fileExists(atPath: destURL.path) {
                            try FileManager.default.removeItem(at: destURL)
                        }
                        try FileManager.default.copyItem(at: url, to: destURL)
                        self.debug("Copied: \(url.lastPathComponent)")
                    } catch {
                        self.debug("Failed to copy \(url.lastPathComponent): \(error)")
                    }
                }
                DispatchQueue.main.async {
                    self.statusMessage = "Copied \(files.count) \(label)."
                }
            }
        }
    }
    // MARK: - Playback
    @Published var currentTrack: Track?
    @Published var player: AVAudioPlayer?

    func play(track: Track) {
        do {
            player = try AVAudioPlayer(contentsOf: track.url)
            player?.play()
            currentTrack = track
        } catch {
            debug("Playback error: \(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        player?.stop()
        currentTrack = nil
    }

    @Published var tracks: [Track] = []
    @Published var groupedTracks: [String: [String: [Track]]] = [:]
    @Published var selectedTracks: Set<Track.ID> = []
    @Published var statusMessage = "Looking for an iPod..."
    @Published var debugEnabled = false
    @Published var debugLog: [String] = []
    @Published var searchText: String = ""
    @Published var selectedCategory: MediaCategory = .music

    private var sourceFolder: URL?
    
    // Support music extensions only for now
    private let supportedExtensions = ["mp3", "m4a", "aac", "wav"]

    // Filtered tracks based on searchText
    var filteredTracks: [Track] {
        guard !searchText.isEmpty else { return tracks }
        let lowerSearch = searchText.lowercased()
        return tracks.filter {
            $0.title.lowercased().contains(lowerSearch) ||
            $0.artist.lowercased().contains(lowerSearch) ||
            $0.album.lowercased().contains(lowerSearch)
        }
    }

    // Group filtered tracks by artist -> album
    var filteredGroupedTracks: [String: [String: [Track]]] {
        var result: [String: [String: [Track]]] = [:]
        for track in filteredTracks {
            result[track.artist, default: [:]][track.album, default: []].append(track)
        }
        return result
    }

    var sortedArtistsFiltered: [String] {
        filteredGroupedTracks.keys.sorted()
    }

    func sortedAlbumsFiltered(for artist: String) -> [String] {
        filteredGroupedTracks[artist]?.keys.sorted() ?? []
    }

    // MARK: - iPod Detection and Loading

    func autoDetectiPod() {
        DispatchQueue.global(qos: .userInitiated).async {
            let volumes = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
            self.debug("Volumes found: \(volumes)")

            for volumeName in volumes {
                let candidate = URL(fileURLWithPath: "/Volumes/\(volumeName)/iPod_Control/Music")
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                    DispatchQueue.main.async {
                        self.sourceFolder = candidate
                        self.statusMessage = "iPod found: \(volumeName)"
                    }
                    self.debug("Detected iPod at \(candidate.path)")
                    self.loadTracks(from: candidate)
                    return
                }
            }
            DispatchQueue.main.async {
                self.statusMessage = "No iPod found. You can select a folder manually."
            }
            self.debug("No iPod found.")
        }
    }

    func selectMediaFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Select your \(selectedCategory.rawValue) Folder"
        if panel.runModal() == .OK, let url = panel.url {
            sourceFolder = url
            statusMessage = "Folder selected: \(url.lastPathComponent)"
            switch selectedCategory {
            case .music:
                loadTracks(from: url)
            case .photos:
                loadPhotos(from: url)
            case .voiceMemos:
                loadVoiceMemos(from: url)
            }
            debug("Manually selected folder: \(url.path)")
        }
    }

    func loadTracks(from folder: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            var foundTracks: [Track] = []
            let keys: [URLResourceKey] = [.isRegularFileKey]
            let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants])!

            for case let file as URL in enumerator {
                if self.supportedExtensions.contains(file.pathExtension.lowercased()) {
                    self.debug("Found audio file: \(file.lastPathComponent)")
                    let asset = AVAsset(url: file)
                    let meta = asset.commonMetadata

                    let title = meta.first(where: { $0.commonKey?.rawValue == "title" })?.stringValue
                        ?? file.deletingPathExtension().lastPathComponent
                    let artist = meta.first(where: { $0.commonKey?.rawValue == "artist" })?.stringValue ?? "Unknown Artist"
                    let album = meta.first(where: { $0.commonKey?.rawValue == "albumName" })?.stringValue ?? "Unknown Album"

                    let artworkData = meta.first(where: { $0.commonKey?.rawValue == "artwork" })?.dataValue
                    var artwork: NSImage? = nil
                    if let data = artworkData {
                        artwork = NSImage(data: data)
                    }

                    foundTracks.append(Track(url: file, title: title, artist: artist, album: album, artwork: artwork))
                }
            }

            DispatchQueue.main.async {
                self.tracks = foundTracks
                self.statusMessage = foundTracks.isEmpty ? "No tracks found." : "Loaded \(foundTracks.count) tracks."
                self.buildGroupedTracks()
                self.debug("Loaded \(foundTracks.count) total track(s).")
            }
        }
    }

    func buildGroupedTracks() {
        var result: [String: [String: [Track]]] = [:]
        for track in tracks {
            result[track.artist, default: [:]][track.album, default: []].append(track)
        }
        groupedTracks = result
    }

    // MARK: - Copying Tracks

    func copySelectedTracks() {
        let selected = tracks.filter { selectedTracks.contains($0.id) }
        copyTracks(selected)
    }

    func copyAllTracks() {
        copyTracks(tracks)
    }

    private func copyTracks(_ tracksToCopy: [Track]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "Choose a destination folder"

        if panel.runModal() == .OK, let destination = panel.url {
            DispatchQueue.global(qos: .utility).async {
                for track in tracksToCopy {
                    let cleanArtist = track.artist.replacingOccurrences(of: "/", with: "-")
                    let cleanTitle = track.title.replacingOccurrences(of: "/", with: "-")
                    let fileName = "\(cleanArtist) - \(cleanTitle).\(track.url.pathExtension)"
                    let destURL = destination.appendingPathComponent(fileName)

                    do {
                        if FileManager.default.fileExists(atPath: destURL.path) {
                            try FileManager.default.removeItem(at: destURL)
                        }
                        try FileManager.default.copyItem(at: track.url, to: destURL)
                        self.debug("Copied: \(fileName)")
                    } catch {
                        self.debug("Failed to copy \(fileName): \(error)")
                    }
                }
                DispatchQueue.main.async {
                    self.statusMessage = "Copied \(tracksToCopy.count) track(s)."
                }
            }
        }
    }

    // MARK: - Debug Logging
    
    private func debug(_ message: String) {
        DispatchQueue.main.async {
            print("[DEBUG] \(message)")
            self.debugLog.append("[\(Self.timestamp())] \(message)")
            if self.debugLog.count > 500 {
                self.debugLog.removeFirst()
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: Date())
    }
}
// MARK: - Data Model

struct Track: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let title: String
    let artist: String
    let album: String
    let artwork: NSImage?
}

// MARK: - Media Category Enum

enum MediaCategory: String, CaseIterable, Identifiable {
    case music = "Music"
    case photos = "Photos"
    case voiceMemos = "Voice Memos"
    
    var id: String { rawValue }
}

// MARK: - Main App

@main
struct iCopyApp: App {
    @StateObject private var vm = iCopyViewModel()
    @State private var showingUpdateSheet = false
    @State var showhelp = false
    
    // App-level updater state
    private let currentAppVersion = "1.5"
    @State private var isCheckingUpdate = false
    @State private var latestVersion: String?
    @State private var showAutoUpdateAlert = false
    @State private var updateError: String?
    
    var body: some Scene {
        WindowGroup {
            NavigationView {
                // Sidebar
                Group {
                    if #available(macOS 13.0, *) {
                        List(selection: $vm.selectedCategory) {
                            ForEach(MediaCategory.allCases) { category in
                                Text(category.rawValue)
                                    .tag(category)
                            }
                        }
                    } else {
                        List {
                            ForEach(MediaCategory.allCases) { category in
                                Button(action: { 
                                    vm.selectedCategory = category
                                    // Trigger auto-detect on category switch for older macOS
                                    switch category {
                                    case .music: vm.autoDetectiPod()
                                    case .photos: vm.autoDetectPhotos()
                                    case .voiceMemos: vm.autoDetectVoiceMemos()
                                    }
                                }) {
                                    HStack {
                                        Text(category.rawValue)
                                        Spacer()
                                        if vm.selectedCategory == category {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 150)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Update iCopy") {
                            showingUpdateSheet = true
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button("Scan for iPods") {
                            scanCurrentCategory()
                        }
                    }
                }

                // Detail
                VStack {
                    switch vm.selectedCategory {
                    case .music:
                        MusicView(vm: vm)
                    case .photos:
                        PhotoGridView(vm: vm)
                    case .voiceMemos:
                        VoiceMemoListView(vm: vm)
                    }
                }
                .frame(minWidth: 600, minHeight: 500)
                .navigationTitle(vm.selectedCategory.rawValue)
                .onAppear {
                    if vm.selectedCategory == .music {
                        vm.autoDetectiPod()
                    }
                }
            }
            .sheet(isPresented: $showingUpdateSheet) {
                UpdateView()
            }
            .onAppear {
                // Kick off detection for initial category
                switch vm.selectedCategory {
                case .music: vm.autoDetectiPod()
                case .photos: vm.autoDetectPhotos()
                case .voiceMemos: vm.autoDetectVoiceMemos()
                }
                // Auto-check for updates at launch
                checkForUpdate()
            }
        }
    }
    
    private func scanCurrentCategory() {
        switch vm.selectedCategory {
        case .music:
            vm.autoDetectiPod()
        case .photos:
            vm.autoDetectPhotos()
        case .voiceMemos:
            vm.autoDetectVoiceMemos()
        }
    }
    
    // MARK: - Auto Update (App-level)

    private func checkForUpdate() {
        isCheckingUpdate = true
        updateError = nil
        
        guard let url = URL(string: "https://jbluebird.github.io/iCopy/version.txt") else {
            isCheckingUpdate = false
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                self.isCheckingUpdate = false
                guard error == nil, let data = data,
                      let content = String(data: data, encoding: .utf8),
                      let firstLine = content.split(separator: "\n").first else {
                    return
                }
                let versionString = firstLine.split(separator: " ").first.map(String.init) ?? ""
                self.latestVersion = versionString
                if versionString.compare(self.currentAppVersion, options: .numeric) == .orderedDescending {
                    self.showAutoUpdateAlert = true
                }
            }
        }.resume()
    }
    
    private func downloadAndInstallUpdate() {
        guard let downloadURL = URL(string: "https://jbluebird.github.io/h/iCopy2.zip") else { return }
        
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let destinationZipURL = desktop.appendingPathComponent("iCopy2.zip")
        
        URLSession.shared.downloadTask(with: downloadURL) { tempLocalUrl, _, error in
            DispatchQueue.main.async {
                guard let tempLocalUrl = tempLocalUrl, error == nil else { return }
                do {
                    if FileManager.default.fileExists(atPath: destinationZipURL.path) {
                        try FileManager.default.removeItem(at: destinationZipURL)
                    }
                    try FileManager.default.moveItem(at: tempLocalUrl, to: destinationZipURL)
                    
                    try runShellCommand("/usr/bin/ditto", args: ["-xk", destinationZipURL.path, desktop.path])
                    
                    let appPath = desktop.appendingPathComponent("iCopy.app/Contents/MacOS/iCopy").path
                    try runShellCommand("/bin/chmod", args: ["+x", appPath])
                } catch {
                    // swallow errors for now
                }
            }
        }.resume()
    }
    
    private func runShellCommand(_ launchPath: String, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "ShellCommandError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Shell command failed with exit code \(process.terminationStatus)"])
        }
    }
    
    func iconName(for category: MediaCategory) -> String {
        switch category {
        case .music: return "music.note.list"
        case .photos: return "photo"
        case .voiceMemos: return "mic"
        }
    }
}

// MARK: - Music View

private enum MusicViewAlertKind: Identifiable {
    case updateAvailable
    case updateDone

    var id: Int {
        switch self {
        case .updateAvailable: return 1
        case .updateDone: return 2
        }
    }
}

struct MusicView: View {
    let currentAppVersion = "1.5"

    @ObservedObject var vm: iCopyViewModel
    @State private var statusMessage = "Ready to check for updates."
    @State private var isChecking = false
    @State private var isDownloading = false
    @State private var updateAvailable = false
    @State private var latestVersion: String?
    @State private var errorMessage: String?
    // Big Sur-safe: single alert driver
    @State private var activeAlert: MusicViewAlertKind?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Copy Selected") {
                    vm.copySelectedTracks()
                }
                .buttonStyle(.bordered)
                .disabled(vm.filteredTracks.isEmpty || vm.selectedTracks.isEmpty)
                
                Button("Copy All") {
                    vm.copyAllTracks()
                }
                .buttonStyle(.bordered)
                .disabled(vm.filteredTracks.isEmpty)
                Button("Import Folder") {
                    vm.selectMediaFolder()
                }
                .buttonStyle(.bordered)
                
                Button("Scan for iPods") {
                    vm.autoDetectiPod()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                TextField("Search \(vm.selectedCategory.rawValue)", text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .onAppear {
                checkForUpdate()
            }
            // Single .alert modifier for Big Sur using Identifiable item
            .alert(item: Binding(get: {
                activeAlert
            }, set: { _ in
                activeAlert = nil
            })) { item in
                switch item {
                case .updateAvailable:
                    return Alert(
                        title: Text("Update Available"),
                        message: Text("iCopy needs to update to (\(latestVersion ?? "?")) to work properly."),
                        primaryButton: .default(Text("Download and Install"), action: {
                            downloadAndInstallUpdate()
                        }),
                        secondaryButton: .cancel()
                    )
                case .updateDone:
                    return Alert(
                        title: Text("Update Done!"),
                        message: Text("You will find the new version of iCopy in your downloads folder. Please replace this version with the new one."),
                        dismissButton: .default(Text("Ok, got it."))
                    )
                }
            }
            
            MiniPlayerView(vm: vm)

            Divider()
            if vm.filteredTracks.isEmpty {
                DiscoveryLogView(status: vm.statusMessage, logs: vm.debugLog)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(vm.sortedArtistsFiltered, id: \.self) { artist in
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(vm.sortedAlbumsFiltered(for: artist), id: \.self) { album in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 12) {
                                            AlbumArtworkView(artwork: vm.filteredGroupedTracks[artist]![album]!.first?.artwork)
                                                .frame(width: 80, height: 80)
                                                .cornerRadius(8)
                                            VStack {
                                                HStack{Text(album)
                                                        .bold()
                                                        .font(.title3)
                                                    .foregroundColor(.secondary);Spacer()}
                                                HStack{Text("by \(artist)");Spacer()}
                                            }
                                            
                                            Spacer()
                                        }
                                        .padding(.leading)
                                        Spacer()
                                        
                                        VStack {
                                            ForEach(vm.filteredGroupedTracks[artist]![album]!) { track in
                                                HStack {
                                                    TrackRow(track: track, isSelected: vm.selectedTracks.contains(track.id)) {
                                                        if vm.selectedTracks.contains(track.id) {
                                                            vm.selectedTracks.remove(track.id)
                                                        } else {
                                                            vm.selectedTracks.insert(track.id)
                                                        }
                                                    }
                                                    Button(action: { vm.play(track: track) }) {
                                                        Image(systemName: "play.circle").font(.title)
                                                    }.padding()
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }
                                        .padding(.leading, 100)
                                    }
                                }
                            }
                            Divider()
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.vertical)
                    
                }
            }
        }
    }
    func checkForUpdate() {
        isChecking = true
        errorMessage = nil
        updateAvailable = false
        statusMessage = "Checking for updates..."
        
        guard let url = URL(string: "https://jbluebird.github.io/iCopy/version.txt") else {
            errorMessage = "Invalid version URL."
            statusMessage = "Ready to check for updates."
            isChecking = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                isChecking = false
                
                guard error == nil, let data = data,
                      let content = String(data: data, encoding: .utf8),
                      let firstLine = content.split(separator: "\n").first else {
                    errorMessage = "Failed to load version info."
                    statusMessage = "Ready to check for updates."
                    return
                }
                
                let versionString = firstLine.split(separator: " ").first.map(String.init) ?? ""
                latestVersion = versionString
                
                if versionString.compare(currentAppVersion, options: .numeric) == .orderedDescending {
                    updateAvailable = true
                    statusMessage = "Update available: \(versionString)"
                    activeAlert = .updateAvailable
                } else {
                    updateAvailable = false
                    statusMessage = "No updates available. You're up to date!"
                }
            }
        }.resume()
    }
    
    func downloadAndInstallUpdate() {
        guard let downloadURL = URL(string: "https://jbluebird.github.io/h/iCopy2.zip") else {
            errorMessage = "Invalid download URL."
            return
        }
        
        isDownloading = true
        errorMessage = nil
        statusMessage = "Downloading update..."
        
        let downloadsFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destinationZipURL = downloadsFolder.appendingPathComponent("iCopy2.zip")
        
        URLSession.shared.downloadTask(with: downloadURL) { tempLocalUrl, _, error in
            DispatchQueue.main.async {
                isDownloading = false
                
                guard let tempLocalUrl = tempLocalUrl, error == nil else {
                    errorMessage = "Download error: \(error?.localizedDescription ?? "Unknown error")"
                    statusMessage = "Ready to check for updates."
                    return
                }
                
                do {
                    if FileManager.default.fileExists(atPath: destinationZipURL.path) {
                        try FileManager.default.removeItem(at: destinationZipURL)
                    }
                    try FileManager.default.moveItem(at: tempLocalUrl, to: destinationZipURL)
                    
                    try runShellCommand("/usr/bin/ditto", args: ["-xk", destinationZipURL.path, downloadsFolder.path])
                    
                    let appPath = downloadsFolder.appendingPathComponent("iCopy.app/Contents/MacOS/iCopy").path
                    try runShellCommand("/bin/chmod", args: ["+x", appPath])
                    
                    statusMessage = "Update installed! Check your Downloads folder for the new iCopy."
                    activeAlert = .updateDone

                } catch {
                    errorMessage = "Update failed: \(error.localizedDescription)"
                    statusMessage = "Ready to check for updates."
                }
            }
        }.resume()
    }
    
    func runShellCommand(_ launchPath: String, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "ShellCommandError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Shell command failed with exit code \(process.terminationStatus)"])
        }
    }
}

// MARK: - PhotoItem

struct PhotoItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let filename: String
    let thumbnail: NSImage?
}

// MARK: - VoiceMemo

struct VoiceMemo: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let title: String
    let duration: TimeInterval
    let dateRecorded: Date?
}

// MARK: - PhotoGridView

import SwiftUI

// MARK: - PhotoGridView with Timeline

struct PhotoGridView: View {
    @ObservedObject var vm: iCopyViewModel
    let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]
    
    var groupedPhotosByMonth: [(String, [PhotoItem])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        
        let grouped = Dictionary(grouping: vm.filteredPhotos) { photo -> String in
            let date = (try? photo.url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            return formatter.string(from: date)
        }
        
        return grouped
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                let d1 = formatter.date(from: lhs.0) ?? Date()
                let d2 = formatter.date(from: rhs.0) ?? Date()
                return d1 > d2
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button("Copy Selected") {
                    vm.copySelectedPhotos()
                }
                .buttonStyle(.bordered)
                .disabled(vm.selectedPhotoItems.isEmpty)

                Button("Import Folder") {
                    vm.selectMediaFolder()
                }
                .buttonStyle(.bordered)
                
                Button("Scan for iPods") {
                    vm.autoDetectPhotos()
                }
                .buttonStyle(.bordered)

                Spacer()

                TextField("Search Photos", text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .onAppear {
                vm.autoDetectPhotos()
            }

            Divider()

            if vm.filteredPhotos.isEmpty {
                VStack(spacing: 8) {
                    Text(vm.statusMessage)
                        .foregroundColor(.secondary)
                    if !vm.debugLog.isEmpty {
                        Divider()
                        ScrollView {
                            Text(vm.debugLog.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(groupedPhotosByMonth, id: \.0) { (month, items) in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(month)
                                    .font(.title3)
                                    .bold()
                                    .padding(.horizontal)

                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(items) { photo in
                                        ZStack(alignment: .topTrailing) {
                                            VStack(spacing: 4) {
                                                if let img = photo.thumbnail {
                                                    Image(nsImage: img)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 100, height: 100)
                                                        .clipped()
                                                        .cornerRadius(8)
                                                } else {
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color.gray.opacity(0.2))
                                                        .frame(width: 100, height: 100)
                                                        .overlay(
                                                            Image(systemName: "photo")
                                                                .font(.system(size: 28))
                                                                .foregroundColor(.gray)
                                                        )
                                                }

                                                Text(photo.filename)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                            }
                                            .onTapGesture {
                                                if vm.selectedPhotoItems.contains(photo.id) {
                                                    vm.selectedPhotoItems.remove(photo.id)
                                                } else {
                                                    vm.selectedPhotoItems.insert(photo.id)
                                                }
                                            }

                                            Image(systemName: vm.selectedPhotoItems.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(vm.selectedPhotoItems.contains(photo.id) ? .accentColor : .gray)
                                                .padding(4)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
    }
}


// MARK: - Thumbnail Helper

func generateThumbnail(from url: URL, maxSize: CGFloat = 100) -> NSImage? {
    guard let image = NSImage(contentsOf: url) else { return nil }

    let targetSize = NSSize(width: maxSize, height: maxSize)
    let thumbnail = NSImage(size: targetSize)
    
    thumbnail.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .low
    image.draw(in: NSRect(origin: .zero, size: targetSize),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy,
               fraction: 1.0)
    thumbnail.unlockFocus()
    
    return thumbnail
}
// MARK: - VoiceMemoListView

struct VoiceMemoListView: View {
    @ObservedObject var vm: iCopyViewModel

    @State private var transcriptionText: String = ""
    @State private var isTranscribing: Bool = false
    @State private var transcriptionError: String?

    // We'll keep a reference to the current recognition task to cancel if needed
    @State private var recognitionTask: SFSpeechRecognitionTask?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button("Copy Selected") {
                    vm.copySelectedVoiceMemos()
                }
                .buttonStyle(.bordered)
                .disabled(vm.selectedVoiceMemos.isEmpty)

                Button("Import Folder") {
                    vm.selectMediaFolder()
                }
                .buttonStyle(.bordered)
                
                Button("Scan for iPods") {
                    vm.autoDetectVoiceMemos()
                }
                .buttonStyle(.bordered)

                Spacer()

                TextField("Search Voice Memos", text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .onAppear {
                vm.autoDetectVoiceMemos()
            }
            
            Divider()

            if vm.filteredVoiceMemos.isEmpty {
                VStack(spacing: 8) {
                    Text(vm.statusMessage)
                        .foregroundColor(.secondary)
                    if !vm.debugLog.isEmpty {
                        Divider()
                        ScrollView {
                            Text(vm.debugLog.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
            } else {
                List(selection: $vm.selectedVoiceMemos) {
                    ForEach(vm.filteredVoiceMemos) { memo in
                        HStack {
                            Text(memo.title)
                                .font(.headline)
                            if let date = memo.dateRecorded {
                                if #available(macOS 12.0, *) {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                } else {
                                    // Fallback on earlier versions
                                }
                            }
                            Spacer()
                            Text(formatDuration(memo.duration))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSelection(memo)
                        }
                        .contextMenu {
                            Button("Transcribe") {
                                transcribeVoiceMemo(memo)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if isTranscribing {
                    HStack {
                        ProgressView()
                        Text("Transcribing...")
                    }
                } else if let error = transcriptionError {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                } else if !transcriptionText.isEmpty {
                    Text("Transcription:")
                        .font(.headline)
                    ScrollView {
                        Text(transcriptionText)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .frame(maxHeight: 150)
                } else {
                }
            }
            .padding()
        }
    }

    private func toggleSelection(_ memo: VoiceMemo) {
        if vm.selectedVoiceMemos.contains(memo.id) {
            vm.selectedVoiceMemos.remove(memo.id)
        } else {
            vm.selectedVoiceMemos.insert(memo.id)
        }
    }

    private func formatDuration(_ time: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .short
        return formatter.string(from: time) ?? ""
    }

    private func transcribeVoiceMemo(_ memo: VoiceMemo) {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        transcriptionText = ""
        transcriptionError = nil
        isTranscribing = true

        // Check file exists
        guard FileManager.default.fileExists(atPath: memo.url.path) else {
            transcriptionError = "Voice memo file not found."
            isTranscribing = false
            return
        }

        // Request authorization
        SFSpeechRecognizer.requestAuthorization { authStatus in
            switch authStatus {
            case .authorized:
                // Create the recognizer and check availability
                guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
                    DispatchQueue.main.async {
                        self.transcriptionError = "Speech recognizer not available."
                        self.isTranscribing = false
                    }
                    return
                }

                let request = SFSpeechURLRecognitionRequest(url: memo.url)
                request.shouldReportPartialResults = false

                self.recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.transcriptionError = "Transcription error: \(error.localizedDescription)"
                            self.isTranscribing = false
                        }
                        return
                    }

                    if let result = result, result.isFinal {
                        DispatchQueue.main.async {
                            self.transcriptionText = result.bestTranscription.formattedString
                            self.isTranscribing = false
                        }
                    }
                }

            case .denied, .restricted, .notDetermined:
                DispatchQueue.main.async {
                    self.transcriptionError = "Speech recognition permission denied."
                    self.isTranscribing = false
                }
            @unknown default:
                DispatchQueue.main.async {
                    self.transcriptionError = "Unknown speech recognition authorization status."
                    self.isTranscribing = false
                }
            }
        }
    }
}

struct MiniPlayerView: View {
    @ObservedObject var vm: iCopyViewModel
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 1
    @State private var timer: Timer? = nil
    @State private var isDragging = false
    @State private var volume: Float = 1.0
    @State private var loopEnabled = false

    var body: some View {
        if let track = vm.currentTrack, let player = vm.player {
            VStack(spacing: 10) {
                // Track Info
                HStack(spacing: 12) {
                    if let img = track.artwork {
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .cornerRadius(4)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 40)
                            .overlay(Image(systemName: "music.note").foregroundColor(.gray))
                    }

                    VStack(alignment: .leading) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Loop toggle
                    Button(action: { loopEnabled.toggle() }) {
                        Image(systemName: loopEnabled ? "repeat.circle.fill" : "repeat.circle")
                            .foregroundColor(loopEnabled ? .accentColor : .gray)
                    }
                    .buttonStyle(.plain)

                    // Stop
                    Button(action: {
                        stopPlayback()
                    }) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.plain)
                }

                // Progress & Controls
                VStack(spacing: 6) {
                    // Progress bar with labels
                    HStack {
                        Text(formatTime(currentTime))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Slider(value: $currentTime, in: 0...duration, onEditingChanged: sliderChanged)

                        Text("-\(formatTime(duration - currentTime))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Playback controls
                    HStack(spacing: 20) {
                        Button(action: skipBackward) {
                            Image(systemName: "gobackward.10")
                        }

                        Button(action: togglePlayPause) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 30))
                        }

                        Button(action: skipForward) {
                            Image(systemName: "goforward.10")
                        }

                        // Volume
                        Slider(value: Binding(get: {
                            volume
                        }, set: { newVal in
                            volume = newVal
                            player.volume = newVal
                        }), in: 0...1)
                            .frame(width: 100)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .onAppear {
                volume = player.volume
                duration = player.duration
                currentTime = player.currentTime
                startTimer()
            }
            .onDisappear {
                stopTimer()
            }
        }
    }

    // MARK: - Actions

    func togglePlayPause() {
        guard let player = vm.player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func skipForward() {
        vm.player?.currentTime += 10
        currentTime = vm.player?.currentTime ?? 0
    }

    func skipBackward() {
        vm.player?.currentTime -= 10
        currentTime = vm.player?.currentTime ?? 0
    }

    func stopPlayback() {
        vm.stopPlayback()
        isPlaying = false
        stopTimer()
    }

    func sliderChanged(editing: Bool) {
        isDragging = editing
        if !editing {
            vm.player?.currentTime = currentTime
        }
    }

    func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard let player = vm.player else { return }
            if !isDragging {
                currentTime = player.currentTime
            }
            if player.currentTime >= player.duration {
                if loopEnabled {
                    player.currentTime = 0
                    player.play()
                } else {
                    stopPlayback()
                }
            }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Discovery Log View

struct DiscoveryLogView: View {
    let status: String
    let logs: [String]
    
    var body: some View {
        VStack(spacing: 8) {
            Text(status)
                .foregroundColor(.secondary)
            Divider()
            ScrollView {
                Text(logs.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}
