//
//  AlbumArtworkView.swift
//  iCopy
//
//  Created by JBlueBird on 8/8/25.
//
import SwiftUI

// MARK: - Album Artwork View

struct AlbumArtworkView: View {
    var artwork: NSImage?
    
    var body: some View {
        if let img = artwork {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .clipped()
                .shadow(radius: 3)
            
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: "ipod")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                )
        }
    }
}

// MARK: - Track Row

struct TrackRow: View {
    let track: Track
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .gray)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            
            
            VStack(alignment: .leading) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(track.url.lastPathComponent)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        //.hoverEffect(.highlight)
    }
}
