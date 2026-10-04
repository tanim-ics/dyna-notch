import SwiftUI

struct NotificationView: View {
    let notification: NotchNotification

    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            if let icon = notification.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.1))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "app.fill").foregroundStyle(.white.opacity(0.5)))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(notification.appName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)

                Text(notification.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
