import SwiftUI
import SwiftData

/// "You dine here a lot — you could be earning rewards." Lists the places you've visited that have a
/// known loyalty program, ranked by how often you go, with a link to join.
struct RewardsView: View {
    @Query private var restaurants: [Restaurant]

    private struct Row: Identifiable {
        let id: String            // the loyalty program's id — one row per program, not per location
        let representative: Restaurant
        let program: LoyaltyProgram
        let visitCount: Int
        let locationCount: Int
    }

    /// One row per loyalty program, summing visits across every location of that brand (you join a
    /// program once, not per store).
    private var rows: [Row] {
        var grouped: [String: (program: LoyaltyProgram, representative: Restaurant, visits: Int, locations: Int)] = [:]
        for restaurant in restaurants {
            let count = restaurant.visits.filter { $0.deletedAt == nil }.count
            guard count > 0, let program = LoyaltyDirectory.program(for: restaurant.name) else { continue }
            if let existing = grouped[program.id] {
                grouped[program.id] = (program, existing.representative, existing.visits + count, existing.locations + 1)
            } else {
                grouped[program.id] = (program, restaurant, count, 1)
            }
        }
        return grouped.values
            .map { Row(id: $0.program.id, representative: $0.representative, program: $0.program, visitCount: $0.visits, locationCount: $0.locations) }
            .sorted { $0.visitCount > $1.visitCount }
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No rewards yet",
                    systemImage: "gift",
                    description: Text("As you visit places that have loyalty programs, they'll show up here so you never leave points on the table.")
                )
            } else {
                List {
                    Section {
                        ForEach(rows) { row in
                            rowView(row)
                        }
                    } footer: {
                        Text("These are third-party loyalty programs run by each restaurant. Tapping “Join” opens their signup.")
                    }
                }
            }
        }
        .navigationTitle("Rewards")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 12) {
            RestaurantLogoView(
                host: row.representative.websiteHost,
                name: row.representative.name,
                fallbackSystemImage: "gift.fill",
                size: 40
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(row.program.brand).font(.headline)
                Text(row.program.programName).font(.caption).foregroundStyle(.secondary)
                Text(visitText(for: row))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if let url = row.program.joinURL {
                Link(destination: url) {
                    Text("Join")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private func visitText(for row: Row) -> String {
        let visits = "You've been \(row.visitCount) time\(row.visitCount == 1 ? "" : "s")"
        return row.locationCount > 1 ? "\(visits) · \(row.locationCount) locations" : visits
    }
}

/// Inline nudge shown on a visit's detail when its restaurant has a known loyalty program.
struct LoyaltyNudgeCard: View {
    let program: LoyaltyProgram
    let visitCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(program.brand) has rewards", systemImage: "gift.fill")
                .font(.headline)
            Text(visitCount > 1
                 ? "You've been here \(visitCount) times — you could be earning \(program.programName)."
                 : "Earn points here with \(program.programName).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let url = program.joinURL {
                Link(destination: url) {
                    Label("Join \(program.programName)", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 4)
    }
}
