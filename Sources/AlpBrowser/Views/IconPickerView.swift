//
//  IconPickerView.swift
//  Alp Browser
//
//  "Change Icon…" picker for sidebar folders and pinned tabs: an Emoji page and a built-in Icons page,
//  with search, and a way back to the default glyph / favicon.
//

import SwiftUI

// MARK: - Catalog

enum AlpIconCatalog {
    struct Symbol: Identifiable {
        let symbol: String      // SF Symbol name (what gets persisted)
        let keywords: String
        var id: String { symbol }
    }

    struct EmojiGroup: Identifiable {
        let title: String
        let glyph: String       // shown on the category button
        let entries: [Emoji]
        var id: String { title }
    }

    struct Emoji: Identifiable {
        let char: String
        let keywords: String
        var id: String { char }
    }

    static let symbols: [Symbol] = [
        Symbol(symbol: "star.fill", keywords: "star favorite"),
        Symbol(symbol: "bookmark.fill", keywords: "bookmark save"),
        Symbol(symbol: "heart.fill", keywords: "heart love"),
        Symbol(symbol: "flag.fill", keywords: "flag"),
        Symbol(symbol: "bolt.fill", keywords: "flash bolt lightning fast"),
        Symbol(symbol: "triangle.fill", keywords: "triangle shape"),
        Symbol(symbol: "cross.case.fill", keywords: "medical health"),
        Symbol(symbol: "bell.fill", keywords: "notifications bell alert"),
        Symbol(symbol: "lightbulb.fill", keywords: "bulb idea light"),
        Symbol(symbol: "square.on.circle", keywords: "shapes"),
        Symbol(symbol: "square.grid.2x2.fill", keywords: "grid"),
        Symbol(symbol: "circle.grid.3x3.fill", keywords: "apps dots"),
        Symbol(symbol: "square.stack.3d.up.fill", keywords: "layers stack"),
        Symbol(symbol: "rectangle.stack.fill", keywords: "albums stack"),
        Symbol(symbol: "doc.on.doc.fill", keywords: "copy documents"),
        Symbol(symbol: "tray.full.fill", keywords: "file tray inbox"),
        Symbol(symbol: "calendar", keywords: "calendar date"),
        Symbol(symbol: "envelope.fill", keywords: "mail email"),
        Symbol(symbol: "checkmark.square.fill", keywords: "checkbox todo done"),
        Symbol(symbol: "book.fill", keywords: "book read"),
        Symbol(symbol: "person.2.fill", keywords: "people team friends"),
        Symbol(symbol: "terminal.fill", keywords: "terminal shell"),
        Symbol(symbol: "hammer.fill", keywords: "construction build tools"),
        Symbol(symbol: "square.fill", keywords: "square shape"),
        Symbol(symbol: "circle.fill", keywords: "ellipse circle shape"),
        Symbol(symbol: "moon.fill", keywords: "moon night"),
        Symbol(symbol: "sun.max.fill", keywords: "sunny sun day"),
        Symbol(symbol: "globe.americas.fill", keywords: "planet world earth"),
        Symbol(symbol: "leaf.fill", keywords: "leaf nature"),
        Symbol(symbol: "cloud.fill", keywords: "cloud"),
        Symbol(symbol: "cloud.rain.fill", keywords: "cloud rain weather"),
        Symbol(symbol: "gift.fill", keywords: "gift present"),
        Symbol(symbol: "fork.knife", keywords: "restaurant food eat"),
        Symbol(symbol: "dumbbell.fill", keywords: "barbell gym fitness"),
        Symbol(symbol: "airplane", keywords: "airplane travel flight"),
        Symbol(symbol: "music.note", keywords: "musical note music"),
        Symbol(symbol: "paintpalette.fill", keywords: "color palette paint art"),
        Symbol(symbol: "bandage.fill", keywords: "bandage"),
        Symbol(symbol: "chevron.left.forwardslash.chevron.right", keywords: "code developer"),
        Symbol(symbol: "baseball.fill", keywords: "baseball sport"),
        Symbol(symbol: "flame.fill", keywords: "bonfire fire flame"),
        Symbol(symbol: "cup.and.saucer.fill", keywords: "coffee cup drink"),
        Symbol(symbol: "doc.text.fill", keywords: "receipt document text"),
        Symbol(symbol: "tram.fill", keywords: "train transit"),
        Symbol(symbol: "magnifyingglass", keywords: "search find"),
        Symbol(symbol: "ellipsis.bubble.fill", keywords: "chat bubble message"),
    ]

    private static func group(_ title: String, _ glyph: String, _ raw: String) -> EmojiGroup {
        // "😀 grin smile" items separated by "|"
        let entries = raw.split(separator: "|").compactMap { item -> Emoji? in
            let parts = item.split(separator: " ", maxSplits: 1).map(String.init)
            guard let first = parts.first else { return nil }
            return Emoji(char: first, keywords: parts.count > 1 ? parts[1] : "")
        }
        return EmojiGroup(title: title, glyph: glyph, entries: entries)
    }

    static let emojiGroups: [EmojiGroup] = [
        group("Smileys & People", "😀", "😀 grin happy|😃 smile happy|😄 laugh|😁 beam|😆 laughing|😅 sweat|😂 joy tears|🙂 slight smile|😉 wink|😊 blush|😇 angel|😍 love eyes|🤩 star struck|😘 kiss|😋 yum|😎 cool sunglasses|🤓 nerd|🧐 monocle|🤔 thinking|😴 sleep|🤯 mind blown|🥳 party|😭 cry|😡 angry|🥶 cold|🥵 hot|😱 scream|🤖 robot|👻 ghost|💀 skull|👽 alien|🧌 troll|👹 ogre|👋 wave hello|👍 thumbs up|👏 clap|🙌 raised hands|🙏 pray thanks|💪 muscle strong|🧠 brain|👀 eyes|👤 person|👥 people|🧑‍💻 developer coder|🧑‍🎨 artist|🧑‍🚀 astronaut|🧙 wizard"),
        group("Animals & Nature", "🐶", "🐶 dog|🐱 cat|🐭 mouse|🐹 hamster|🐰 rabbit|🦊 fox|🐻 bear|🐼 panda|🐨 koala|🐯 tiger|🦁 lion|🐮 cow|🐷 pig|🐸 frog|🐵 monkey|🐔 chicken|🐧 penguin|🐦 bird|🦉 owl|🦄 unicorn|🐝 bee|🦋 butterfly|🐢 turtle|🐙 octopus|🐬 dolphin|🐳 whale|🦈 shark|🐘 elephant|🌵 cactus|🌲 tree pine|🌳 tree|🌴 palm|🍀 clover luck|🌱 seedling|🌿 herb|🍁 maple leaf|🌸 blossom flower|🌻 sunflower|🌹 rose|🌍 earth globe|🌙 moon|⭐ star|🌈 rainbow|🔥 fire|💧 water drop|❄️ snow|⚡ lightning"),
        group("Food & Drink", "🍔", "🍎 apple|🍊 orange|🍋 lemon|🍌 banana|🍉 watermelon|🍇 grapes|🍓 strawberry|🍒 cherries|🥑 avocado|🍅 tomato|🥕 carrot|🌽 corn|🥐 croissant|🍞 bread|🧀 cheese|🍳 egg cooking|🥞 pancakes|🍔 burger|🍟 fries|🍕 pizza|🌭 hot dog|🌮 taco|🍣 sushi|🍜 ramen noodles|🍩 donut|🍪 cookie|🎂 cake birthday|🍫 chocolate|🍿 popcorn|☕ coffee|🍵 tea|🍺 beer|🍷 wine|🥤 soda cup"),
        group("Activities", "⚽", "⚽ soccer football|🏀 basketball|🏈 american football|⚾ baseball|🎾 tennis|🏐 volleyball|🏓 ping pong|🥊 boxing|🎯 target dart|🎮 game controller|🕹️ joystick|🎲 dice|♟️ chess|🎨 art palette|🎬 movie clapper|🎤 microphone|🎧 headphones|🎼 music score|🎹 piano|🎸 guitar|🥁 drum|🏆 trophy|🥇 gold medal|🏋️ weights gym|🚴 cycling|🏊 swimming|🧘 yoga meditate|🎭 theater|🎪 circus"),
        group("Travel & Places", "✈️", "🚗 car|🚕 taxi|🚌 bus|🚆 train|🚀 rocket|✈️ airplane flight|🚁 helicopter|⛵ sailboat|🚲 bicycle|🏠 house home|🏢 office building|🏫 school|🏥 hospital|🏦 bank|🏰 castle|🗽 statue liberty|🗼 tower|⛰️ mountain|🏔️ snow mountain|🏖️ beach|🏝️ island|🌋 volcano|🗺️ map|🧭 compass|⛺ camping tent|🌆 city|🌃 night city"),
        group("Objects", "💡", "💡 idea bulb|🔦 flashlight|📱 phone|💻 laptop computer|🖥️ desktop|⌨️ keyboard|🖱️ mouse|💾 floppy save|📷 camera|📺 tv|📚 books|📖 book open|📝 memo note|📌 pin|📎 paperclip|✂️ scissors|🗂️ folder dividers|📁 folder|📂 open folder|📅 calendar|📈 chart up|📊 bar chart|💼 briefcase work|🛒 cart shopping|💰 money bag|💳 credit card|🔑 key|🔒 lock|🔧 wrench|🔨 hammer|⚙️ gear settings|🧪 test tube|🔬 microscope|🔭 telescope|💊 pill|🎁 gift|📦 package box|✉️ envelope mail|📬 mailbox"),
        group("Symbols", "❤️", "❤️ red heart|🧡 orange heart|💛 yellow heart|💚 green heart|💙 blue heart|💜 purple heart|🖤 black heart|🤍 white heart|💯 hundred|✅ check|❌ cross|❗ exclamation|❓ question|⭕ circle|🔴 red circle|🟠 orange circle|🟡 yellow circle|🟢 green circle|🔵 blue circle|🟣 purple circle|⚫ black circle|⚪ white circle|🟥 red square|🟧 orange square|🟨 yellow square|🟩 green square|🟦 blue square|🟪 purple square|🔶 diamond|✨ sparkles|💫 dizzy|♻️ recycle|➕ plus|➖ minus|🔔 bell|💬 speech bubble|🆕 new|🔝 top"),
        group("Flags", "🏁", "🏁 chequered flag race|🚩 red flag|🏳️ white flag|🏴 black flag|🏳️‍🌈 rainbow flag|🇺🇸 united states usa|🇬🇧 united kingdom uk|🇩🇪 germany|🇫🇷 france|🇪🇸 spain|🇮🇹 italy|🇹🇷 turkey|🇯🇵 japan|🇰🇷 south korea|🇨🇳 china|🇮🇳 india|🇧🇷 brazil|🇨🇦 canada|🇦🇺 australia|🇲🇽 mexico|🇳🇱 netherlands|🇸🇪 sweden|🇨🇭 switzerland"),
    ]
}

// MARK: - Rendering

/// Renders a custom icon at a given point size. Callers decide when to use it (only when the icon is set).
struct AlpCustomIconView: View {
    let icon: AlpCustomIcon
    let size: CGFloat
    let tint: Color

    var body: some View {
        switch icon {
        case .emoji(let char):
            Text(char).font(.system(size: size))
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.92))
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Picker

private enum IconPickerPage: String, CaseIterable, Identifiable {
    case emoji = "Emoji"
    case icons = "Icons"
    var id: String { rawValue }
}

struct IconPickerView: View {
    let current: AlpCustomIcon?
    let onPick: (AlpCustomIcon?) -> Void

    @State private var page: IconPickerPage
    @State private var query = ""
    @State private var groupTitle = AlpIconCatalog.emojiGroups[0].title

    init(current: AlpCustomIcon?, onPick: @escaping (AlpCustomIcon?) -> Void) {
        self.current = current
        self.onPick = onPick
        if case .symbol = current { _page = State(initialValue: .icons) } else { _page = State(initialValue: .emoji) }
    }

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 4), count: 8)

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private var emojiResults: [AlpIconCatalog.Emoji] {
        if trimmedQuery.isEmpty {
            return AlpIconCatalog.emojiGroups.first(where: { $0.title == groupTitle })?.entries ?? []
        }
        return AlpIconCatalog.emojiGroups.flatMap(\.entries).filter { $0.keywords.lowercased().contains(trimmedQuery) }
    }

    private var symbolResults: [AlpIconCatalog.Symbol] {
        trimmedQuery.isEmpty ? AlpIconCatalog.symbols : AlpIconCatalog.symbols.filter { $0.keywords.contains(trimmedQuery) }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $page) {
                ForEach(IconPickerPage.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)

            if page == .emoji && trimmedQuery.isEmpty {
                HStack(spacing: 2) {
                    ForEach(AlpIconCatalog.emojiGroups) { group in
                        Button { groupTitle = group.title } label: {
                            Text(group.glyph)
                                .font(.system(size: 14))
                                .frame(width: 28, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(groupTitle == group.title ? Color.primary.opacity(0.14) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(group.title)
                    }
                }
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    if page == .emoji {
                        ForEach(emojiResults) { item in
                            cell(selected: current == .emoji(item.char)) {
                                Text(item.char).font(.system(size: 21))
                            } action: {
                                onPick(.emoji(item.char))
                            }
                        }
                    } else {
                        ForEach(symbolResults) { item in
                            cell(selected: current == .symbol(item.symbol)) {
                                Image(systemName: item.symbol).font(.system(size: 16)).foregroundStyle(.primary)
                            } action: {
                                onPick(.symbol(item.symbol))
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 190)

            if current != nil {
                Button("Remove Icon") { onPick(nil) }
                    .buttonStyle(.link)
            }
        }
        .padding(12)
        .frame(width: 8 * 34 + 7 * 4 + 24 + 12)
    }

    private func cell<Label: View>(selected: Bool, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Attaches the icon picker as a popover anchored to this view.
    func alpIconPicker(isPresented: Binding<Bool>, current: AlpCustomIcon?, onPick: @escaping (AlpCustomIcon?) -> Void) -> some View {
        popover(isPresented: isPresented, arrowEdge: .trailing) {
            IconPickerView(current: current) { icon in
                onPick(icon)
                isPresented.wrappedValue = false
            }
        }
    }
}
