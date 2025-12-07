import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            content.frame(height: 340)
            Divider()
            footer
        }
        .frame(width: 480)
    }

    private var content: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(nsImage: AppMetadata.logo)
                .resizable()
                .frame(width: 80, height: 80)
            Text(AppMetadata.name)
                .font(.system(size: 22, weight: .bold))
            Text(AppMetadata.tagline)
                .foregroundStyle(.secondary)
            Text("Version \(AppMetadata.version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()

            // Author
            VStack(spacing: 6) {
                Text("Developed by").font(.caption).foregroundStyle(.tertiary)
                Text(AppMetadata.author).font(.callout)
                Text(AppMetadata.authorEmail).font(.caption).foregroundStyle(.secondary)
                Link(destination: URL(string: AppMetadata.authorLinkedin)!) {
                    Text("LinkedIn").font(.caption)
                }
            }

            // Links
            HStack(spacing: 20) {
                Link(destination: URL(string: AppMetadata.website)!) {
                    Label("Website", systemImage: "globe")
                }
                Link(destination: URL(string: AppMetadata.repository)!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var footer: some View {
        HStack {
            Text(AppMetadata.copyright)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

#Preview {
    AboutView()
}
