import AppKit
import SwiftUI

struct ContactAvatar: View {
    let name: String?
    let photo: NSImage?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let photo {
                Image(nsImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.45)], startPoint: .top, endPoint: .bottom))
                if let initials {
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String? {
        guard let name, name.first?.isLetter == true else { return nil }
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }
}
