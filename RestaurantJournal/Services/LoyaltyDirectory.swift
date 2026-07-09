import Foundation

/// A known restaurant loyalty program the user could join.
struct LoyaltyProgram: Identifiable {
    let id: String
    let brand: String
    let programName: String
    /// Normalized name fragments used to match a restaurant to this program.
    let matchTerms: [String]
    let joinURLString: String

    var joinURL: URL? { URL(string: joinURLString) }
}

/// A curated map of common chains → their loyalty program. A lightweight "you're leaving points on
/// the table" nudge — not automated enrollment (no universal loyalty API exists). Easy to extend.
enum LoyaltyDirectory {
    static let programs: [LoyaltyProgram] = [
        .init(id: "starbucks", brand: "Starbucks", programName: "Starbucks Rewards", matchTerms: ["starbucks"], joinURLString: "https://www.starbucks.com/rewards"),
        .init(id: "chipotle", brand: "Chipotle", programName: "Chipotle Rewards", matchTerms: ["chipotle"], joinURLString: "https://www.chipotle.com/rewards"),
        .init(id: "panera", brand: "Panera Bread", programName: "MyPanera", matchTerms: ["panera"], joinURLString: "https://www.panerabread.com/en-us/mypanera.html"),
        .init(id: "dunkin", brand: "Dunkin'", programName: "Dunkin' Rewards", matchTerms: ["dunkin"], joinURLString: "https://www.dunkindonuts.com/en/dunkin-rewards"),
        .init(id: "mcdonalds", brand: "McDonald's", programName: "MyMcDonald's Rewards", matchTerms: ["mcdonald"], joinURLString: "https://www.mcdonalds.com/us/en-us/mymcdonalds.html"),
        .init(id: "chickfila", brand: "Chick-fil-A", programName: "Chick-fil-A One", matchTerms: ["chickfila"], joinURLString: "https://www.chick-fil-a.com/one"),
        .init(id: "tacobell", brand: "Taco Bell", programName: "Taco Bell Rewards", matchTerms: ["tacobell"], joinURLString: "https://www.tacobell.com/rewards"),
        .init(id: "wendys", brand: "Wendy's", programName: "Wendy's Rewards", matchTerms: ["wendys"], joinURLString: "https://www.wendys.com/rewards"),
        .init(id: "burgerking", brand: "Burger King", programName: "Royal Perks", matchTerms: ["burgerking"], joinURLString: "https://www.bk.com/rewards"),
        .init(id: "subway", brand: "Subway", programName: "Subway MVP Rewards", matchTerms: ["subway"], joinURLString: "https://www.subway.com/en-us/rewards"),
        .init(id: "dominos", brand: "Domino's", programName: "Piece of the Pie Rewards", matchTerms: ["dominos"], joinURLString: "https://www.dominos.com/en/pages/customer/#!/rewards/"),
        .init(id: "pandaexpress", brand: "Panda Express", programName: "Panda Rewards", matchTerms: ["pandaexpress"], joinURLString: "https://www.pandaexpress.com/rewards"),
        .init(id: "sweetgreen", brand: "Sweetgreen", programName: "Sweetgreen Rewards", matchTerms: ["sweetgreen"], joinURLString: "https://www.sweetgreen.com"),
        .init(id: "shakeshack", brand: "Shake Shack", programName: "Shack App rewards", matchTerms: ["shakeshack"], joinURLString: "https://www.shakeshack.com/app"),
        .init(id: "qdoba", brand: "Qdoba", programName: "Qdoba Rewards", matchTerms: ["qdoba"], joinURLString: "https://www.qdoba.com/rewards"),
        .init(id: "jerseymikes", brand: "Jersey Mike's", programName: "Shore Points", matchTerms: ["jerseymike"], joinURLString: "https://www.jerseymikes.com/mynikes"),
        .init(id: "wingstop", brand: "Wingstop", programName: "Wingstop Rewards", matchTerms: ["wingstop"], joinURLString: "https://www.wingstop.com"),
        .init(id: "popeyes", brand: "Popeyes", programName: "Popeyes Rewards", matchTerms: ["popeyes"], joinURLString: "https://www.popeyes.com/rewards"),
        .init(id: "raisingcanes", brand: "Raising Cane's", programName: "Caniac Club", matchTerms: ["raisingcane"], joinURLString: "https://www.raisingcanes.com/caniac-club"),
        .init(id: "peets", brand: "Peet's Coffee", programName: "Peetnik Rewards", matchTerms: ["peets"], joinURLString: "https://www.peets.com/peetnik-rewards"),
        .init(id: "dutchbros", brand: "Dutch Bros", programName: "Dutch Rewards", matchTerms: ["dutchbros"], joinURLString: "https://www.dutchbros.com/rewards"),
        .init(id: "krispykreme", brand: "Krispy Kreme", programName: "Krispy Kreme Rewards", matchTerms: ["krispykreme"], joinURLString: "https://www.krispykreme.com/rewards"),
        .init(id: "jamba", brand: "Jamba", programName: "Jamba Rewards", matchTerms: ["jamba"], joinURLString: "https://www.jamba.com/rewards"),
        .init(id: "deltaco", brand: "Del Taco", programName: "Del Yeah! Rewards", matchTerms: ["deltaco"], joinURLString: "https://www.deltaco.com/rewards"),
        .init(id: "firehouse", brand: "Firehouse Subs", programName: "Firehouse Rewards", matchTerms: ["firehouse"], joinURLString: "https://www.firehousesubs.com/rewards"),
        .init(id: "pizzahut", brand: "Pizza Hut", programName: "Hut Rewards", matchTerms: ["pizzahut"], joinURLString: "https://www.pizzahut.com/hutrewards"),
        .init(id: "papajohns", brand: "Papa Johns", programName: "Papa Rewards", matchTerms: ["papajohn"], joinURLString: "https://www.papajohns.com/papa-rewards/"),
        .init(id: "littlecaesars", brand: "Little Caesars", programName: "Little Caesars Rewards", matchTerms: ["littlecaesar"], joinURLString: "https://littlecaesars.com/en-us/create-account/"),
        .init(id: "whataburger", brand: "Whataburger", programName: "Whataburger Rewards", matchTerms: ["whataburger"], joinURLString: "https://whataburger.com/rewards"),
        .init(id: "culvers", brand: "Culver's", programName: "Culver's Delicious Rewards", matchTerms: ["culver"], joinURLString: "https://www.culvers.com/rewards"),
        .init(id: "dairyqueen", brand: "Dairy Queen", programName: "DQ Rewards", matchTerms: ["dairyqueen"], joinURLString: "https://www.dairyqueen.com/en-us/rewards/"),
        .init(id: "sonic", brand: "Sonic Drive-In", programName: "Sonic App Rewards", matchTerms: ["sonicdrive"], joinURLString: "https://www.sonicdrivein.com/rewards"),
        .init(id: "jackinthebox", brand: "Jack in the Box", programName: "Jack Pack Rewards", matchTerms: ["jackinthebox"], joinURLString: "https://www.jackinthebox.com/rewards"),
        .init(id: "chilis", brand: "Chili's", programName: "My Chili's Rewards", matchTerms: ["chilis"], joinURLString: "https://www.chilis.com/rewards"),
        .init(id: "applebees", brand: "Applebee's", programName: "Club Applebee's", matchTerms: ["applebee"], joinURLString: "https://www.applebees.com/en/club-applebees"),
        .init(id: "ihop", brand: "IHOP", programName: "International Bank of Pancakes", matchTerms: ["ihop"], joinURLString: "https://www.ihop.com/en/rewards"),
        .init(id: "dennys", brand: "Denny's", programName: "Denny's Rewards", matchTerms: ["dennys"], joinURLString: "https://www.dennys.com/rewards"),
        .init(id: "buffalowildwings", brand: "Buffalo Wild Wings", programName: "Blazin' Rewards", matchTerms: ["buffalowildwings"], joinURLString: "https://www.buffalowildwings.com/rewards/"),
        .init(id: "jimmyjohns", brand: "Jimmy John's", programName: "JJ Rewards", matchTerms: ["jimmyjohn"], joinURLString: "https://www.jimmyjohns.com/rewards"),
        .init(id: "moes", brand: "Moe's Southwest Grill", programName: "Moe Rewards", matchTerms: ["moessouthwest"], joinURLString: "https://www.moes.com/rewards"),
        .init(id: "noodles", brand: "Noodles & Company", programName: "Noodles Rewards", matchTerms: ["noodlescompany", "noodlesandcompany"], joinURLString: "https://www.noodles.com/rewards"),
        .init(id: "zaxbys", brand: "Zaxby's", programName: "Zax Rewardz", matchTerms: ["zaxby"], joinURLString: "https://www.zaxbys.com/rewards"),
        .init(id: "bojangles", brand: "Bojangles", programName: "Bo Rewards", matchTerms: ["bojangles"], joinURLString: "https://www.bojangles.com/rewards"),
    ]

    static func program(for restaurantName: String?) -> LoyaltyProgram? {
        guard let restaurantName else { return nil }
        let normalized = normalize(restaurantName)
        guard !normalized.isEmpty else { return nil }
        return programs.first { program in
            program.matchTerms.contains { normalized.contains($0) }
        }
    }

    private static func normalize(_ string: String) -> String {
        string.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
