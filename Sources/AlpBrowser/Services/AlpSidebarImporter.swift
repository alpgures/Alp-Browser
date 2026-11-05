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
    public var totalImportedTabs: Int
    public var totalImportedFolders: Int

    public init(
        spaces: [AlpSpace],
        favorites: [TabItem],
        totalImportedTabs: Int,
        totalImportedFolders: Int
    ) {
        self.spaces = spaces
        self.favorites = favorites
        self.totalImportedTabs = totalImportedTabs
        self.totalImportedFolders = totalImportedFolders
    }
}

public enum AlpSidebarImporter {
    public static var defaultArcSidebarURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Arc/StorableSidebar.json")
    }

    public static var isArcInstalledDataAvailable: Bool {
        FileManager.default.fileExists(atPath: defaultArcSidebarURL.path)
    }

    public static func importFromArc(at fileURL: URL = defaultArcSidebarURL) throws -> ImportedData {
        let fileData = try Data(contentsOf: fileURL)
        guard let jsonObject = try JSONSerialization.jsonObject(with: fileData) as? [String: Any],
              let sidebarDict = jsonObject["sidebar"] as? [String: Any],
              let containerList = sidebarDict["containers"] as? [Any] else {
            throw NSError(
                domain: "AlpSidebarImporter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid sidebar JSON format"]
            )
        }

        // Locate main container housing spaces and items
        guard let primaryContainer = containerList
            .compactMap({ $0 as? [String: Any] })
            .first(where: { $0["spaces"] != nil && $0["items"] != nil }) else {
            throw NSError(
                domain: "AlpSidebarImporter",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No spaces container located in sidebar data"]
            )
        }

        // Build item lookup table
        let rawItems = (primaryContainer["items"] as? [Any]) ?? []
        var itemDictionary: [String: [String: Any]] = [:]
        for raw in rawItems {
            if let dict = raw as? [String: Any], let id = dict["id"] as? String {
                itemDictionary[id] = dict
            }
        }

        // Parse global favorites (top apps)
        var importedFavorites: [TabItem] = []
        if let topAppsList = primaryContainer["topAppsContainerIDs"] as? [Any] {
            for entry in topAppsList {
                if let containerID = entry as? String,
                   let containerDict = itemDictionary[containerID] {
                    let childIDs = extractChildIDs(for: containerDict, containerID: containerID, items: itemDictionary)
                    for childID in childIDs {
                        if let dict = itemDictionary[childID],
                           var tab = parseTabItem(from: dict, isPinned: true, isFavorite: true) {
                            tab.isHibernated = true
                            importedFavorites.append(tab)
                        }
                    }
                }
            }
        }

        var importedSpaces: [AlpSpace] = []
        var tabCount = importedFavorites.count
        var folderCount = 0

        let rawSpacesList = (primaryContainer["spaces"] as? [Any]) ?? []
        let fallbackThemes: [SpaceTheme] = [.userPersonalSky, .userLeisurePlum, .auroraMesh, .warmSunset]

        for (index, rawSpace) in rawSpacesList.enumerated() {
            guard let spaceDict = rawSpace as? [String: Any],
                  let spaceID = spaceDict["id"] as? String else {
                continue
            }

            let rawTitle = (spaceDict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let spaceTitle = (rawTitle?.isEmpty == false) ? rawTitle! : "Space \(index + 1)"

            let customInfo = spaceDict["customInfo"] as? [String: Any]
            let emoji = extractEmoji(from: customInfo) ?? (index == 0 ? "🧌" : "👹")
            let theme = extractTheme(from: customInfo) ?? fallbackThemes[index % fallbackThemes.count]

            let containerIDs = (spaceDict["containerIDs"] as? [Any])?.compactMap { $0 as? String } ?? []
            let pinnedID = nextContainerID(after: "pinned", in: containerIDs)
            let unpinnedID = nextContainerID(after: "unpinned", in: containerIDs)

            var pinnedNodes: [SidebarNode] = []
            if let pid = pinnedID, let pContainer = itemDictionary[pid] {
                let childIDs = extractChildIDs(for: pContainer, containerID: pid, items: itemDictionary)
                for cid in childIDs {
                    if let node = parseSidebarNode(
                        itemID: cid,
                        items: itemDictionary,
                        isPinned: true,
                        tabCounter: &tabCount,
                        folderCounter: &folderCount,
                        visited: Set()
                    ) {
                        pinnedNodes.append(node)
                    }
                }
            }

            var todayTabs: [TabItem] = []
            if let uid = unpinnedID, let uContainer = itemDictionary[uid] {
                let childIDs = extractChildIDs(for: uContainer, containerID: uid, items: itemDictionary)
                for cid in childIDs {
                    if let dict = itemDictionary[cid],
                       var tab = parseTabItem(from: dict, isPinned: false, isFavorite: false) {
                        tab.isHibernated = true
                        todayTabs.append(tab)
                        tabCount += 1
                    }
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

        return ImportedData(
            spaces: importedSpaces,
            favorites: importedFavorites,
            totalImportedTabs: tabCount,
            totalImportedFolders: folderCount
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
        items: [String: [String: Any]]
    ) -> [String] {
        if let children = dict["childrenIds"] as? [String], !children.isEmpty {
            return children
        }
        return items.values
            .filter { ($0["parentID"] as? String) == containerID }
            .compactMap { $0["id"] as? String }
    }

    private static func parseSidebarNode(
        itemID: String,
        items: [String: [String: Any]],
        isPinned: Bool,
        tabCounter: inout Int,
        folderCounter: inout Int,
        visited: Set<String>
    ) -> SidebarNode? {
        guard !visited.contains(itemID), let dict = items[itemID] else {
            return nil
        }
        var currentVisited = visited
        currentVisited.insert(itemID)

        let dataDict = dict["data"] as? [String: Any]
        if dataDict?["list"] != nil {
            let rawTitle = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let folderTitle = (rawTitle?.isEmpty == false) ? rawTitle! : "Folder"
            let childIDs = extractChildIDs(for: dict, containerID: itemID, items: items)
            var children: [SidebarNode] = []
            for cid in childIDs {
                if let child = parseSidebarNode(
                    itemID: cid,
                    items: items,
                    isPinned: isPinned,
                    tabCounter: &tabCounter,
                    folderCounter: &folderCounter,
                    visited: currentVisited
                ) {
                    children.append(child)
                }
            }
            folderCounter += 1
            let folder = FolderItem(
                title: folderTitle,
                isExpanded: false,
                children: children
            )
            return .folder(folder)
        } else if var tab = parseTabItem(from: dict, isPinned: isPinned, isFavorite: false) {
            tab.isHibernated = true
            tabCounter += 1
            return .tab(tab)
        }
        return nil
    }

    private static func parseTabItem(
        from dict: [String: Any],
        isPinned: Bool,
        isFavorite: Bool
    ) -> TabItem? {
        guard let data = dict["data"] as? [String: Any],
              let tabDict = data["tab"] as? [String: Any],
              let urlString = tabDict["savedURL"] as? String,
              !urlString.isEmpty else {
            return nil
        }

        let itemTitle = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedTitle = (tabDict["savedTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = (savedTitle?.isEmpty == false) ? savedTitle! : (itemTitle ?? urlString)
        let customTitle = (itemTitle?.isEmpty == false && itemTitle != savedTitle) ? itemTitle : nil

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
