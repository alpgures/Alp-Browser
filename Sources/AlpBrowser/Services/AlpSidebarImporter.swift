//
//  AlpSidebarImporter.swift
//  Alp Browser
//
//  Clean-room importer for user-owned sidebar data from local Arc installations.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation

public struct ImportedData: Sendable {
    public var spaces: [AlpSpace]
    public var favorites: [TabItem]
    public var archivedTabs: [ArchivedTab]
    public var totalImportedTabs: Int
    public var totalImportedFolders: Int
    /// Items left out because they were unusable (unsupported or oversized URL, nesting too deep, over the size cap, duplicates).
    public var skippedItems: Int

    public init(
        spaces: [AlpSpace],
        favorites: [TabItem],
        archivedTabs: [ArchivedTab] = [],
        totalImportedTabs: Int,
        totalImportedFolders: Int,
        skippedItems: Int = 0
    ) {
        self.spaces = spaces
        self.favorites = favorites
        self.archivedTabs = archivedTabs
        self.totalImportedTabs = totalImportedTabs
        self.totalImportedFolders = totalImportedFolders
        self.skippedItems = skippedItems
    }
}

/// Why an import of the user's own Arc data could not be done. Messages are shown to the user as they are.
public enum ArcImportError: LocalizedError {
    case notFound
    case unreadable
    case tooLarge
    case malformed
    case noSpaces

    public var errorDescription: String? {
        switch self {
        case .notFound: return "Arc's sidebar data was not found on this Mac, so there was nothing to import."
        case .unreadable: return "Arc's sidebar data could not be read. Check that Alp Browser is allowed to access that folder. Nothing was changed."
        case .tooLarge: return "Arc's sidebar data file is unexpectedly large, so it was not imported. Nothing was changed."
        case .malformed: return "Arc's sidebar data is not in a format Alp Browser understands. Nothing was changed."
        case .noSpaces: return "No spaces were found in Arc's sidebar data. Nothing was changed."
        }
    }
}

public enum AlpSidebarImporter {
    public static var defaultArcSidebarURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Arc/StorableSidebar.json")
    }

    public static var defaultArcArchiveItemsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Arc/StorableArchiveItems.json")
    }

    public static var isArcInstalledDataAvailable: Bool {
        FileManager.default.fileExists(atPath: defaultArcSidebarURL.path)
    }

    /// Most tabs (or archived entries) one import will take; the rest are counted as skipped.
    static let maxImportedItems = 10_000
    /// Largest sidebar file read (bytes).
    static let maxFileBytes = 256 * 1024 * 1024
    private static let maxNestingDepth = 40

    /// Only web-style addresses are brought over. Arc's own internal pages, `javascript:` and `data:` links are dropped,
    /// and absurdly long values are refused.
    static func cleanedURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf16.count <= 8192 else { return nil }
        let lower = trimmed.lowercased()
        let allowed = ["http://", "https://", "file://", "about:"]
        return allowed.contains(where: { lower.hasPrefix($0) }) ? trimmed : nil
    }

    private static func cleanedTitle(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(300))
    }

    public static func importArchivedTabs(at fileURL: URL = defaultArcArchiveItemsURL) -> [ArchivedTab] {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              data.count <= maxFileBytes,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [Any] else {
            return []
        }

        var results: [ArchivedTab] = []
        var seenURLs = Set<String>()
        // Arc stores an id followed by its entry; any element that is not an entry dictionary is skipped.
        for item in items {
            guard results.count < maxImportedItems,
                  let dict = item as? [String: Any],
                  let sidebarItem = dict["sidebarItem"] as? [String: Any] else { continue }
            let tabData = (sidebarItem["data"] as? [String: Any])?["tab"] as? [String: Any] ?? [:]
            guard let rawURL = tabData["savedURL"] as? String,
                  let urlString = cleanedURL(rawURL),
                  seenURLs.insert(urlString).inserted else { continue }
            let title = cleanedTitle(tabData["savedTitle"] as? String) ?? cleanedTitle(sidebarItem["title"] as? String) ?? urlString

            let reason = (dict["reason"] as? String) ?? "manual"
            var archivedDate = Date()
            if let ts = dict["archivedAt"] as? Double, ts.isFinite {
                archivedDate = Date(timeIntervalSinceReferenceDate: ts)
            }

            let id = (UUID(uuidString: (sidebarItem["id"] as? String) ?? "")) ?? UUID()
            results.append(ArchivedTab(
                id: id,
                title: title,
                urlString: urlString,
                spaceTitle: "Archive",
                archivedAt: archivedDate,
                reason: reason
            ))
        }

        return results
    }

    /// Counters and lookup tables shared by one import run.
    private final class ImportContext {
        let items: [String: [String: Any]]
        /// Children by parent id, in file order (used when a container has no explicit child list).
        let childrenByParent: [String: [String]]
        var tabCount = 0
        var folderCount = 0
        var skipped = 0

        init(items: [String: [String: Any]], childrenByParent: [String: [String]]) {
            self.items = items
            self.childrenByParent = childrenByParent
        }

        /// Reserves room for one more tab; false (and counts a skip) once the cap is reached.
        func admitTab() -> Bool {
            guard tabCount < AlpSidebarImporter.maxImportedItems else { skipped += 1; return false }
            tabCount += 1
            return true
        }
    }

    public static func importFromArc(at fileURL: URL = defaultArcSidebarURL) throws -> ImportedData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw ArcImportError.notFound }
        if let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber,
           size.intValue > maxFileBytes {
            throw ArcImportError.tooLarge
        }
        guard let fileData = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { throw ArcImportError.unreadable }
        guard let jsonObject = (try? JSONSerialization.jsonObject(with: fileData)) as? [String: Any],
              let sidebarDict = jsonObject["sidebar"] as? [String: Any],
              let containerList = sidebarDict["containers"] as? [Any] else {
            throw ArcImportError.malformed
        }

        // Locate main container housing spaces and items
        guard let primaryContainer = containerList
            .compactMap({ $0 as? [String: Any] })
            .first(where: { $0["spaces"] != nil && $0["items"] != nil }) else {
            throw ArcImportError.malformed
        }

        // Build item lookup table (first entry wins for a repeated id) and a parent index in file order.
        let rawItems = (primaryContainer["items"] as? [Any]) ?? []
        var itemDictionary: [String: [String: Any]] = [:]
        var childrenByParent: [String: [String]] = [:]
        for raw in rawItems {
            guard let dict = raw as? [String: Any], let id = dict["id"] as? String, itemDictionary[id] == nil else { continue }
            itemDictionary[id] = dict
            if let parent = dict["parentID"] as? String { childrenByParent[parent, default: []].append(id) }
        }
        let context = ImportContext(items: itemDictionary, childrenByParent: childrenByParent)

        // Parse global favorites (top apps)
        var importedFavorites: [TabItem] = []
        var favoriteURLs = Set<String>()
        if let topAppsList = primaryContainer["topAppsContainerIDs"] as? [Any] {
            for entry in topAppsList {
                if let containerID = entry as? String,
                   let containerDict = itemDictionary[containerID] {
                    let childIDs = extractChildIDs(for: containerDict, containerID: containerID, context: context)
                    for childID in childIDs {
                        guard let dict = itemDictionary[childID],
                              var tab = parseTabItem(from: dict, isPinned: true, isFavorite: true, context: context) else { continue }
                        if !favoriteURLs.insert(tab.urlString).inserted {
                            // The same site twice in the favorites row: keep the first.
                            context.tabCount -= 1
                            context.skipped += 1
                            continue
                        }
                        tab.isHibernated = true
                        importedFavorites.append(tab)
                    }
                }
            }
        }

        var importedSpaces: [AlpSpace] = []
        var seenSpaceIDs = Set<String>()

        let rawSpacesList = (primaryContainer["spaces"] as? [Any]) ?? []
        let fallbackThemes: [SpaceTheme] = [.userPersonalSky, .userLeisurePlum, .auroraMesh, .warmSunset]

        for (index, rawSpace) in rawSpacesList.enumerated() {
            guard let spaceDict = rawSpace as? [String: Any],
                  let spaceID = spaceDict["id"] as? String,
                  seenSpaceIDs.insert(spaceID).inserted else {
                continue
            }

            let spaceTitle = cleanedTitle(spaceDict["title"] as? String) ?? "Space \(index + 1)"

            let customInfo = spaceDict["customInfo"] as? [String: Any]
            let emoji = extractEmoji(from: customInfo) ?? (index == 0 ? "🧌" : "👹")
            let theme = extractTheme(from: customInfo) ?? fallbackThemes[index % fallbackThemes.count]

            let containerIDs = (spaceDict["containerIDs"] as? [Any])?.compactMap { $0 as? String } ?? []
            let pinnedID = nextContainerID(after: "pinned", in: containerIDs)
            let unpinnedID = nextContainerID(after: "unpinned", in: containerIDs)

            var pinnedNodes: [SidebarNode] = []
            if let pid = pinnedID, let pContainer = itemDictionary[pid] {
                let childIDs = extractChildIDs(for: pContainer, containerID: pid, context: context)
                for cid in childIDs {
                    if let node = parseSidebarNode(
                        itemID: cid,
                        isPinned: true,
                        context: context,
                        visited: Set(),
                        depth: 0
                    ) {
                        pinnedNodes.append(node)
                    }
                }
            }

            var todayTabs: [TabItem] = []
            var todayURLs = Set<String>()
            if let uid = unpinnedID, let uContainer = itemDictionary[uid] {
                let childIDs = extractChildIDs(for: uContainer, containerID: uid, context: context)
                for cid in childIDs {
                    guard let dict = itemDictionary[cid],
                          var tab = parseTabItem(from: dict, isPinned: false, isFavorite: false, context: context) else { continue }
                    if !todayURLs.insert(tab.urlString).inserted {
                        // Same page open twice in one space's Today list: keep the first.
                        context.tabCount -= 1
                        context.skipped += 1
                        continue
                    }
                    tab.isHibernated = true
                    todayTabs.append(tab)
                }
            }

            let initialActiveTabID = todayTabs.first?.id
                ?? pinnedNodes.flatMap({ $0.allTabs }).first?.id
                ?? importedFavorites.first?.id

            let space = AlpSpace(
                originalArcID: spaceID,
                title: spaceTitle,
                iconEmoji: emoji,
                profileName: "Default",
                theme: theme,
                pinnedNodes: pinnedNodes,
                todayTabs: todayTabs,
                activeTabID: initialActiveTabID
            )
            importedSpaces.append(space)
        }

        // Without a single usable space there is nothing to show; the caller keeps what it has.
        guard !importedSpaces.isEmpty else { throw ArcImportError.noSpaces }

        let archivedTabs = importArchivedTabs()

        return ImportedData(
            spaces: importedSpaces,
            favorites: importedFavorites,
            archivedTabs: archivedTabs,
            totalImportedTabs: context.tabCount,
            totalImportedFolders: context.folderCount,
            skippedItems: context.skipped
        )
    }

    // MARK: - Internal Parsing Helpers

    private static func nextContainerID(after marker: String, in list: [String]) -> String? {
        guard let idx = list.firstIndex(of: marker), idx + 1 < list.count else {
            return nil
        }
        return list[idx + 1]
    }

    private static func extractChildIDs(
        for dict: [String: Any],
        containerID: String,
        context: ImportContext
    ) -> [String] {
        if let children = (dict["childrenIds"] as? [Any])?.compactMap({ $0 as? String }), !children.isEmpty {
            return children
        }
        return context.childrenByParent[containerID] ?? []
    }

    private static func parseSidebarNode(
        itemID: String,
        isPinned: Bool,
        context: ImportContext,
        visited: Set<String>,
        depth: Int
    ) -> SidebarNode? {
        guard !visited.contains(itemID), let dict = context.items[itemID] else {
            return nil
        }
        guard depth < maxNestingDepth else {
            context.skipped += 1
            return nil
        }
        var currentVisited = visited
        currentVisited.insert(itemID)

        let dataDict = dict["data"] as? [String: Any]
        if dataDict?["list"] != nil {
            let folderTitle = cleanedTitle(dict["title"] as? String) ?? "Folder"
            let childIDs = extractChildIDs(for: dict, containerID: itemID, context: context)
            var children: [SidebarNode] = []
            for cid in childIDs {
                if let child = parseSidebarNode(
                    itemID: cid,
                    isPinned: isPinned,
                    context: context,
                    visited: currentVisited,
                    depth: depth + 1
                ) {
                    children.append(child)
                }
            }
            context.folderCount += 1
            let folder = FolderItem(
                title: folderTitle,
                isExpanded: false,
                children: children
            )
            return .folder(folder)
        } else if var tab = parseTabItem(from: dict, isPinned: isPinned, isFavorite: false, context: context) {
            tab.isHibernated = true
            return .tab(tab)
        }
        return nil
    }

    /// A tab item, or nil when the entry is not a tab, its address is unusable, or the import cap is reached.
    /// On success the tab has been counted in `context.tabCount`.
    private static func parseTabItem(
        from dict: [String: Any],
        isPinned: Bool,
        isFavorite: Bool,
        context: ImportContext
    ) -> TabItem? {
        guard let data = dict["data"] as? [String: Any],
              let tabDict = data["tab"] as? [String: Any],
              let rawURL = tabDict["savedURL"] as? String,
              !rawURL.isEmpty else {
            return nil
        }
        guard let urlString = cleanedURL(rawURL) else {
            context.skipped += 1
            return nil
        }
        guard context.admitTab() else { return nil }

        let itemTitle = cleanedTitle(dict["title"] as? String)
        let savedTitle = cleanedTitle(tabDict["savedTitle"] as? String)
        let finalTitle = savedTitle ?? itemTitle ?? urlString
        let customTitle = (itemTitle != nil && itemTitle != savedTitle) ? itemTitle : nil

        return TabItem(
            title: finalTitle,
            customTitle: customTitle,
            urlString: urlString,
            pinnedURLString: isPinned ? urlString : nil,
            isFavorite: isFavorite,
            isPinned: isPinned,
            isHibernated: true
        )
    }

    private static func extractEmoji(from customInfo: [String: Any]?) -> String? {
        guard let iconDict = customInfo?["iconType"] as? [String: Any] else { return nil }
        if let v2 = iconDict["emoji_v2"] as? String, !v2.isEmpty {
            return v2
        }
        if let scalarValue = iconDict["emoji"] as? Int, let scalar = UnicodeScalar(scalarValue) {
            return String(Character(scalar))
        }
        return nil
    }

    private static func extractTheme(from customInfo: [String: Any]?) -> SpaceTheme? {
        guard let windowTheme = customInfo?["windowTheme"] as? [String: Any] else { return nil }
        let palette = windowTheme["primaryColorPalette"] as? [String: Any]

        let shaded = extractColor(from: palette?["shaded"] as? [String: Any])
        let midTone = extractColor(from: palette?["midTone"] as? [String: Any])
        let tintedLight = extractColor(from: palette?["tintedLight"] as? [String: Any])
        let shadedDark = extractColor(from: palette?["shadedDark"] as? [String: Any])

        var singleColor: RGBAColor?
        var grain: Double = 0.65
        var intensity: Double = 0.35
        var vibrant: Bool = true
        var darkAppearance: Bool = false

        if let bg = windowTheme["background"] as? [String: Any],
           let single = bg["single"] as? [String: Any],
           let slot = single["_0"] as? [String: Any] {
            vibrant = (slot["isVibrant"] as? Bool) ?? true
            if let appearance = slot["contentOverBackgroundAppearance"] as? String {
                darkAppearance = (appearance.lowercased() == "dark")
            }
            if let style = slot["style"] as? [String: Any],
               let colorWrapper = style["color"] as? [String: Any],
               let c0 = colorWrapper["_0"] as? [String: Any],
               let blended = c0["blendedSingleColor"] as? [String: Any],
               let b0 = blended["_0"] as? [String: Any] {
                singleColor = extractColor(from: b0["color"] as? [String: Any])
                if let modifiers = b0["modifiers"] as? [String: Any] {
                    grain = (modifiers["noiseFactor"] as? Double) ?? 0.65
                    intensity = (modifiers["intensityFactor"] as? Double) ?? 0.35
                }
            }
        }

        guard let primary = singleColor ?? shaded ?? midTone else {
            return nil
        }

        let secondary = shadedDark ?? primary.darkened(by: 0.35)
        let accent = midTone ?? tintedLight ?? primary.lightened(by: 0.30)

        return SpaceTheme(
            primaryColor: primary,
            secondaryColor: secondary,
            accentColor: accent,
            colorStops: [primary],
            isVibrant: vibrant,
            grainIntensity: grain,
            intensityFactor: intensity,
            prefersLightForeground: darkAppearance
        )
    }

    private static func extractColor(from dict: [String: Any]?) -> RGBAColor? {
        guard let dict = dict,
              let r = dict["red"] as? Double,
              let g = dict["green"] as? Double,
              let b = dict["blue"] as? Double else {
            return nil
        }
        let a = (dict["alpha"] as? Double) ?? 1.0
        return RGBAColor(red: r, green: g, blue: b, alpha: a)
    }
}
