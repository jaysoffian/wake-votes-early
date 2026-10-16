import SwiftUI

struct SiteRow: View {
    let rank: Int
    let plan: SitePlan

    @State private var webLink: WebLink?
    @Environment(\.openURL) private var openURL

    private var site: VotingSite { plan.site }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(rank)")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(site.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)   // wrap as many lines as needed
                Text(site.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                legs
                statusLine
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            // Trailing column: directions capsule, then the county's site-details PDF.
            VStack(alignment: .trailing, spacing: 8) {
                directionsBadge
                if let details = site.detailsURL {
                    Button {
                        #if os(iOS)
                        webLink = WebLink(url: details)
                        #else
                        openURL(details)
                        #endif
                    } label: {
                        Image(systemName: "doc.text")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28, minHeight: 24)
                    }
                    .buttonStyle(.plain)   // plain, so the row itself isn't the tap target
                    .help("County site details (parking, entrance, accessibility)")
                    .accessibilityLabel("Site details for \(site.name)")
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(plan.isViable ? 1 : 0.55)
        #if os(iOS)
        .sheet(item: $webLink) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
        #endif
    }

    /// The total-time capsule doubles as the "open in Maps" button.
    private var directionsBadge: some View {
        let color = WaitColor.color(forTotal: plan.total)
        return Button {
            Directions.open(site)
        } label: {
            HStack(spacing: 5) {
                Text(plan.total.map(Format.minutes) ?? (plan.waitMinutes == nil ? "no data" : "–"))
                    .font(.callout.weight(.bold).monospacedDigit())
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(site.coordinate == nil)
        .help("Open driving directions in Maps")
        .accessibilityLabel("Directions to \(site.name)")
    }

    /// The three chips fit on one line on wide screens and stack on narrow phones.
    private var legs: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { legChips }
            VStack(alignment: .leading, spacing: 3) { legChips }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var legChips: some View {
        leg(icon: "car.fill", text: Format.minutes(plan.trip?.outbound), tint: .secondary)
        leg(icon: "person.3.fill", text: site.waitDisplay, tint: WaitColor.color(for: site.waitMinutes))
        leg(icon: "car.fill", text: plan.trip.map { Format.inbound($0) } ?? "–", tint: .secondary)
    }

    private func leg(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(text)
                .monospacedDigit()
        }
    }

    /// One sentence: anything exceptional about this site, then how stale its wait estimate is.
    /// Hours are county-wide, so the normal open/closed state lives in the footer instead.
    private var statusLine: Text {
        var text = Text("")
        switch plan.status {
        case .closesBeforeArrival:
            if let hours = plan.hours {
                text = Text("Closes at \(Format.clock(hours.close)), before you'd arrive. ").foregroundStyle(.red)
            }
        case .noRoute:
            text = Text("Driving time unavailable. ").foregroundStyle(.orange)
        case .open, .opensLater, .closedForDay, .noVotingToday:
            break
        }
        if let updated = site.waitUpdatedAt {
            // Text(_, style: .relative) re-renders itself as time passes.
            text = text + Text("Wait updated ") + Text(updated, style: .relative) + Text(" ago.")
        }
        return text
    }
}
