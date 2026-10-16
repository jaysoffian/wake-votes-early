import SwiftUI

/// One line describing what the app is doing or what it knows: today's county-wide hours, when the
/// wait times were fetched, and drive-time progress. `compact` is the terse phone form.
struct StatusLine: View {
    var model: PlannerModel
    var compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            if model.isComputingTrips {
                ProgressView().controlSize(.mini)
                Text(computingText).monospacedDigit()
            } else if model.isRefreshing {
                ProgressView().controlSize(.mini)
                Text("Fetching wait times…")
            } else if let error = model.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error)
            } else if let last = model.lastRefresh {
                Text(compact
                     ? "\(hoursText) · Waits as of \(Format.clock(last)) · Apple Maps\(model.avoidTolls ? ", no tolls" : "")"
                     : "\(hoursText) Wait times from Wake County BOE, refreshed at \(Format.clock(last)). Drive times from Apple Maps\(model.avoidTolls ? ", avoiding tolls" : "").")
            }
            Spacer(minLength: 0)
        }
        .font(compact ? .caption2 : .caption)
        .foregroundStyle(.secondary)
        .lineLimit(model.errorMessage == nil && compact ? 2 : 3)
    }

    private var computingText: String {
        let progress = model.tripProgress.map { compact ? " \($0.done)/\($0.total)" : " \($0.done) of \($0.total) requests" } ?? ""
        let pause = model.throttleWait > 1
            ? (compact ? " · pausing \(Int(model.throttleWait.rounded(.up)))s for rate limit"
                       : ". Pausing \(Int(model.throttleWait.rounded(.up)))s for Apple Maps' rate limit.")
            : ""
        return "Computing drive times…\(progress)\(pause)"
    }

    /// County-wide hours for today; every site keeps the same schedule.
    private var hoursText: String {
        let now = model.now
        guard let hours = PlannerModel.schedule.hours(on: now) else {
            return compact ? "No early voting today" + nextOpening(after: now)
                           : "No early voting today." + nextOpening(after: now)
        }
        if now >= hours.close {
            return compact ? "Closed" + nextOpening(after: now) : "Sites closed for the day." + nextOpening(after: now)
        }
        if now < hours.open {
            return compact ? "Opens \(Format.clock(hours.open))"
                           : "Sites open at \(Format.clock(hours.open)) today, until \(Format.clock(hours.close))."
        }
        return compact ? "Open until \(Format.clock(hours.close))" : "Sites open until \(Format.clock(hours.close))."
    }

    private func nextOpening(after date: Date) -> String {
        guard let next = PlannerModel.schedule.nextOpening(after: date) else { return "" }
        let when = next.open.formatted(.dateTime.weekday(compact ? .abbreviated : .wide).hour().minute())
        return compact ? ", next \(when)" : " Next: \(when)."
    }
}
