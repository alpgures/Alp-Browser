import Foundation

public struct ImportedArcData {
    public var spaces: [ArcSpace]
    public var favorites: [TabItem]
    public var totalImportedTabs: Int
    public var totalImportedFolders: Int
}

public enum ArcSidebarImporter {
    public static var defaultArcSidebarURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Arc/StorableSidebar.json")
    }

    public static var isArcInstalledDataAvailable: Bool {
        FileManager.default.fileExists(atPath: defaultArcSidebarURL.path)
    }

    public static func importFromArc(at fileURL: URL = defaultArcSidebarURL) throws -> ImportedArcData {
        let data = try Data(contentsOf: fileURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sidebar = root["sidebar"] as? [String: Any],
              let containers = sidebar["containers"] as? [Any] else {
            throw NSError(domain: "ArcSidebarImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid StorableSidebar.json structure"])
        }

        guard let mainContainer = containers.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] != nil && $0["items"] != nil }) else {
            throw NSError(domain: "ArcSidebarImporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "No spaces container found in StorableSidebar.json"])
        }

        let rawItems = (mainContainer["items"] as? [Any]) ?? []
        var itemsByID: [String: [String: Any]] = [:]
        for element in rawItems {
            if let dict = element as? [String: Any], let id = dict["id"] as? String {
                itemsByID[id] = dict
            }
        }

        var favorites: [TabItem] = []
        if let topAppEntries = mainContainer["topAppsContainerIDs"] as? [Any] {
            for entry in topAppEntries {
                if let containerID = entry as? String,
                   let containerDict = itemsByID[containerID] {
                    let childIDs = orderedChildIDs(for: containerDict, containerID: containerID, itemsByID: itemsByID)
                    for childID in childIDs {
                        if let itemDict = itemsByID[childID],
                           var tab = parseTabItem(from: itemDict, isPinned: true, isFavorite: true) {
                            tab.isHibernated = true
                            favorites.append(tab)
                        }
                    }
                }
            }
        }

        var importedSpaces: [ArcSpace] = []
        var totalTabsCount = favorites.count
        var totalFoldersCount = 0

        let rawSpaces = (mainContainer["spaces"] as? [Any]) ?? []
        let fallbackThemes: [SpaceTheme] = [.userPersonalSky, .userLeisurePlum, .arcAurora, .arcSunset]

        for (index, element) in rawSpaces.enumerated() {
            guard let spaceDict = element as? [String: Any],
                  let spaceID = spaceDict["id"] as? String else {
                continue
            }

            let title = (spaceDict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = (title?.isEmpty == false) ? title! : "Space \(index + 1)"

            let customInfo = spaceDict["customInfo"] as? [String: Any]
            let emoji = parseEmoji(from: customInfo) ?? (index == 0 ? "🧌" : "👹")
            let theme = parseTheme(from: customInfo) ?? fallbackThemes[index % fallbackThemes.count]

            let containerIDs = (spaceDict["containerIDs"] as? [Any])?.compactMap { $0 as? String } ?? []
            let pinnedContainerID = containerIDAfterTag("pinned", in: containerIDs)
            let unpinnedContainerID = containerIDAfterTag("unpinned", in: containerIDs)

            var pinnedNodes: [SidebarNode] = []
            if let pid = pinnedContainerID, let pContainer = itemsByID[pid] {
                let childIDs = orderedChildIDs(for: pContainer, containerID: pid, itemsByID: itemsByID)
                for cid in childIDs {
                    if let node = parseSidebarNode(
                        itemID: cid,
                        itemsByID: itemsByID,
                        isPinned: true,
                        tabsCounter: &totalTabsCount,
                        foldersCounter: &totalFoldersCount,
                        visited: Set()
                    ) {
                        pinnedNodes.append(node)
                    }
                }
            }

            var todayTabs: [TabItem] = []
            if let uid = unpinnedContainerID, let uContainer = itemsByID[uid] {
                let childIDs = orderedChildIDs(for: uContainer, containerID: uid, itemsByID: itemsByID)
                for cid in childIDs {
                    if let itemDict = itemsByID[cid],
                       var tab = parseTabItem(from: itemDict, isPinned: false, isFavorite: false) {
                        tab.isHibernated = true
                        todayTabs.append(tab)
                        totalTabsCount += 1
                    }
                }
            }

            let initialActiveTab = todayTabs.first?.id
                ?? pinnedNodes.flatMap({ $0.allTabs }).first?.id
                ?? favorites.first?.id

            let space = ArcSpace(
                arcOriginalID: spaceID,
                title: resolvedTitle,
                iconEmoji: emoji,
                profileName: "Default",
                theme: theme,
                pinnedNodes: pinnedNodes,
                todayTabs: todayTabs,
                activeTabID: initialActiveTab
            )
            importedSpaces.append(space)
        }

        return ImportedArcData(
            spaces: importedSpaces,
            favorites: favorites,
            totalImportedTabs: totalTabsCount,
            totalImportedFolders: totalFoldersCount
        )
    }

    // MARK: - Private Helpers

    private static func containerIDAfterTag(_ tag: String, in array: [String]) -> String? {
        guard let idx = array.firstIndex(of: tag), idx + 1 < array.count else {
            return nil
        }
        return array[idx + 1]
    }

    private static func orderedChildIDs(
        for containerDict: [String: Any],
        containerID: String,
        itemsByID: [String: [String: Any]]
    ) -> [String] {
        if let childrenIds = containerDict["childrenIds"] as? [String], !childrenIds.isEmpty {
            return childrenIds
        }
        return itemsByID.values
            .filter { ($0["parentID"] as? String) == containerID }
            .compactMap { $0["id"] as? String }
    }

    private static func parseSidebarNode(
        itemID: String,
        itemsByID: [String: [String: Any]],
        isPinned: Bool,
        tabsCounter: inout Int,
        foldersCounter: inout Int,
        visited: Set<String>
    ) -> SidebarNode? {
        guard !visited.contains(itemID), let itemDict = itemsByID[itemID] else {
            return nil
        }
        var nextVisited = visited
        nextVisited.insert(itemID)

        let dataDict = itemDict["data"] as? [String: Any]
        if dataDict?["list"] != nil {
            let rawTitle = (itemDict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let folderTitle = (rawTitle?.isEmpty == false) ? rawTitle! : "Folder"
            let childIDs = orderedChildIDs(for: itemDict, containerID: itemID, itemsByID: itemsByID)
            var children: [SidebarNode] = []
            for cid in childIDs {
                if let childNode = parseSidebarNode(
                    itemID: cid,
                    itemsByID: itemsByID,
                    isPinned: isPinned,
                    tabsCounter: &tabsCounter,
                    foldersCounter: &foldersCounter,
                    visited: nextVisited
                ) {
                    children.append(childNode)
                }
            }
            foldersCounter += 1
            let folder = FolderItem(
                title: folderTitle,
                isExpanded: children.count <= 8,
                children: children
            )
            return .folder(folder)
        } else if var tab = parseTabItem(from: itemDict, isPinned: isPinned, isFavorite: false) {
            tab.isHibernated = true
            tabsCounter += 1
            return .tab(tab)
        }

        return nil
    }

    private static func parseTabItem(
        from itemDict: [String: Any],
        isPinned: Bool,
        isFavorite: Bool
    ) -> TabItem? {
        guard let dataDict = itemDict["data"] as? [String: Any],
              let tabDict = dataDict["tab"] as? [String: Any],
              let savedURL = tabDict["savedURL"] as? String,
              !savedURL.isEmpty else {
            return nil
        }

        let itemLevelTitle = (itemDict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedTitle = (tabDict["savedTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (savedTitle?.isEmpty == false ? savedTitle! : (itemLevelTitle ?? savedURL))
        let customTitle = (itemLevelTitle?.isEmpty == false && itemLevelTitle != savedTitle) ? itemLevelTitle : nil

        return TabItem(
            title: resolvedTitle,
            customTitle: customTitle,
            urlString: savedURL,
            pinnedURLString: isPinned ? savedURL : nil,
            isFavorite: isFavorite,
            isPinned: isPinned,
            isHibernated: true
        )
    }

    private static func parseEmoji(from customInfo: [String: Any]?) -> String? {
        guard let iconType = customInfo?["iconType"] as? [String: Any] else { return nil }
        if let emojiV2 = iconType["emoji_v2"] as? String, !emojiV2.isEmpty {
            return emojiV2
        }
        if let scalarInt = iconType["emoji"] as? Int, let scalar = UnicodeScalar(scalarInt) {
            return String(Character(scalar))
        }
        return nil
    }

    public static func parseTheme(from customInfo: [String: Any]?) -> SpaceTheme? {
        guard let windowTheme = customInfo?["windowTheme"] as? [String: Any] else { return nil }
        let palette = windowTheme["primaryColorPalette"] as? [String: Any]

        let shaded = parseRGBAColor(from: palette?["shaded"] as? [String: Any])
        let midTone = parseRGBAColor(from: palette?["midTone"] as? [String: Any])
        let tintedLight = parseRGBAColor(from: palette?["tintedLight"] as? [String: Any])
        let shadedDark = parseRGBAColor(from: palette?["shadedDark"] as? [String: Any])

        var singleColor: RGBAColor?
        var grainFactor: Double = 0.65
        var intensityFactor: Double = 0.35
        var isVibrant: Bool = true
        var isDarkAppearance: Bool = false

        if let bg = windowTheme["background"] as? [String: Any],
           let single = bg["single"] as? [String: Any],
           let s0 = single["_0"] as? [String: Any] {
            isVibrant = (s0["isVibrant"] as? Bool) ?? true
            if let appearance = s0["contentOverBackgroundAppearance"] as? String {
                // In Arc: "light" means light frosted theme (dark foreground text); "dark" means dark theme (light foreground text)
                isDarkAppearance = (appearance.lowercased() == "dark")
            }
            if let style = s0["style"] as? [String: Any],
               let colorObj = style["color"] as? [String: Any],
               let c0 = colorObj["_0"] as? [String: Any],
               let blended = c0["blendedSingleColor"] as? [String: Any],
               let b0 = blended["_0"] as? [String: Any] {
                singleColor = parseRGBAColor(from: b0["color"] as? [String: Any])
                if let modifiers = b0["modifiers"] as? [String: Any] {
                    grainFactor = (modifiers["noiseFactor"] as? Double) ?? 0.65
                    intensityFactor = (modifiers["intensityFactor"] as? Double) ?? 0.35
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
            isVibrant: isVibrant,
            grainIntensity: grainFactor,
            intensityFactor: intensityFactor,
            prefersLightForeground: isDarkAppearance
        )
    }

    private static func parseRGBAColor(from dict: [String: Any]?) -> RGBAColor? {
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
