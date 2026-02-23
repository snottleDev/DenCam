import Foundation
import UserNotifications

// MotionEvent represents a single completed recording clip.
// ViewController creates one each time a recording stops and collects them
// in a session log that gets passed to the morning summary notification.
struct MotionEvent {
    let start: Date   // when motion first triggered this recording
    let end: Date     // when the post-motion tail expired and recording stopped

    // Total duration of the clip, including the tail.
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

// NotificationManager schedules a single local "morning summary" notification
// that fires at 7:00 AM with a timestamp log of the previous night's activity.
//
// Each time a recording completes, ViewController calls scheduleMorningSummary()
// with the full session event list. This replaces any pending notification with
// updated content, so the 7 AM alert always shows the complete night's activity.
//
// Usage:
//   1. Call requestPermission() once at app start.
//   2. Call scheduleMorningSummary(events:totalBytes:) after each recording ends.
class NotificationManager {

    // MARK: - Singleton

    // One notification center, one manager.
    static let shared = NotificationManager()
    private init() {}

    // MARK: - Private Constants

    // Stable identifier used to cancel and replace the pending notification.
    // Without a consistent ID, each call would add a new notification instead of
    // replacing the previous one — the user would wake up to many alerts.
    private let summaryNotificationID = "com.dencam.morning_summary"

    // The hour (24-hour clock) at which the summary fires. 7 = 7:00 AM.
    // UNCalendarNotificationTrigger fires at the next occurrence of this time —
    // if it's currently 8 PM, the notification fires tomorrow at 7 AM.
    private let summaryHour = 7

    // MARK: - Public Methods

    /// Requests permission to display alerts and play a sound.
    ///
    /// iOS shows the system permission dialog exactly once. After that, this
    /// call is a no-op — the user's previous decision is remembered.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("[NotificationManager] Permission request error: \(error.localizedDescription)")
            } else {
                print("[NotificationManager] Notification permission granted: \(granted)")
            }
        }
    }

    /// Schedules (or replaces) the morning summary notification with the current session data.
    ///
    /// Call this after every recording completes so the notification content grows
    /// throughout the night. The previous pending notification is always cancelled
    /// first to avoid duplicates.
    ///
    /// - Parameters:
    ///   - events: All motion events recorded this session, in chronological order.
    ///   - totalBytes: Cumulative bytes written this session (from StorageManager.bytesRecorded).
    func scheduleMorningSummary(events: [MotionEvent], totalBytes: Int64) {
        guard !events.isEmpty else { return }

        // Cancel the previous version of this notification before scheduling the new one.
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [summaryNotificationID])

        let content = buildNotificationContent(events: events, totalBytes: totalBytes)

        // UNCalendarNotificationTrigger fires at the next 7:00:00 AM.
        // repeats: false — one shot, not a daily alarm.
        var triggerComponents = DateComponents()
        triggerComponents.hour = summaryHour
        triggerComponents.minute = 0
        triggerComponents.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: summaryNotificationID,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationManager] Failed to schedule summary: \(error.localizedDescription)")
            } else {
                print("[NotificationManager] Summary rescheduled — \(events.count) event(s) so far")
            }
        }
    }

    // MARK: - Private Helpers

    /// Assembles the notification title, subtitle, and body from the session data.
    private func buildNotificationContent(
        events: [MotionEvent],
        totalBytes: Int64
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default

        let count = events.count
        let totalDuration = events.reduce(0.0) { $0 + $1.duration }
        let formattedSize = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)

        // Title — always the same; the detail is in subtitle and body.
        content.title = "DenCam — Last night's activity"

        // Subtitle — quick stats visible without expanding the notification.
        content.subtitle = "\(count) motion event\(count == 1 ? "" : "s") · "
            + "\(formattedSize) · \(formattedDuration(totalDuration))"

        // Body — the full timestamp log.
        content.body = buildTimestampLog(events: events)

        return content
    }

    /// Formats the list of motion events as a readable timestamp log.
    ///
    /// Each line: "2:34 AM – 2:36 AM (2m)"
    /// Capped at 20 events to avoid unreasonably long notification text;
    /// a trailing line notes how many additional events were omitted.
    private func buildTimestampLog(events: [MotionEvent]) -> String {
        // Time formatter: "2:34 AM" style
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"

        // Duration formatter: "1h 3m" or "45s" — at most 2 units for compactness
        let durFmt = DateComponentsFormatter()
        durFmt.allowedUnits = [.hour, .minute, .second]
        durFmt.unitsStyle = .abbreviated
        durFmt.maximumUnitCount = 2

        let maxShown = 20
        let shown = Array(events.prefix(maxShown))

        var lines: [String] = shown.map { event in
            let start = timeFmt.string(from: event.start)
            let end = timeFmt.string(from: event.end)
            let dur = durFmt.string(from: event.duration) ?? "?"
            return "\(start) – \(end) (\(dur))"
        }

        if events.count > maxShown {
            lines.append("… and \(events.count - maxShown) more")
        }

        return lines.joined(separator: "\n")
    }

    /// Formats a total duration in seconds as a short human-readable string.
    /// e.g. 3720 → "1h 2m", 45 → "45s"
    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let fmt = DateComponentsFormatter()
        fmt.allowedUnits = [.hour, .minute, .second]
        fmt.unitsStyle = .abbreviated
        fmt.maximumUnitCount = 2
        return fmt.string(from: seconds) ?? "?"
    }
}
