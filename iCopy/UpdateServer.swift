//
//  UpdateView.swift
//  iCopy
//
//  Created by JBlueBird on 8/8/25.
//
import SwiftUI

struct UpdateView: View {
    @Environment(\.dismiss) var dismiss
    
    let currentAppVersion = "1.4"
    
    @State private var statusMessage = "Ready to check for updates."
    @State private var isChecking = false
    @State private var isDownloading = false
    @State private var updateAvailable = false
    @State private var latestVersion: String?
    @State private var errorMessage: String?
    @State private var showUpdateAlert = false
    @State private var showUpdateDoneAlert = false

    var body: some View {
        VStack(spacing: 20) {
            Text("iCopy Update")
                .font(.title2)
                .bold()
            
            Divider()
            
            Text(statusMessage)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if isChecking || isDownloading {
                ProgressView()
            }
            
            if updateAvailable {
                Button("Download and Install Update \(latestVersion ?? "")") {
                    downloadAndInstallUpdate()
                }
                .disabled(isDownloading)
            }

            if let error = errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            }
            
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(30)
        .onAppear {
            checkForUpdate()
        }
        .alert("Update Available", isPresented: $showUpdateAlert) {
            Button("Download and Install") {
                downloadAndInstallUpdate()
            }
        } message: {
            Text("iCopy needs to update to (\(latestVersion ?? "?")) to work properly.")
        }.alert("Update Done!", isPresented: $showUpdateDoneAlert) {
            Button("Ok, got it.") {dismiss()}
        } message: {
            Text("You will find the new version of iCopy in your downloads folder. Please replace this version with the new one.")
        }
        Spacer()
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
                    showUpdateAlert = true
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
                    
                    showUpdateDoneAlert = true

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
