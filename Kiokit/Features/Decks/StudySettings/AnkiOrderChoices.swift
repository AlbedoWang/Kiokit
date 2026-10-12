// Values copied from proto/anki/deck_config.proto in ankitects/anki 26.09.3.
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later.
import Foundation

struct AnkiOrderChoice: Identifiable {
    let value: String
    let label: String
    var id: String { value }
}

enum AnkiOrderChoices {
    static let insertion = [
        AnkiOrderChoice(value: "NEW_CARD_INSERT_ORDER_DUE", label: "顺序添加"),
        AnkiOrderChoice(value: "NEW_CARD_INSERT_ORDER_RANDOM", label: "随机"),
    ]
    static let gather = [
        AnkiOrderChoice(value: "NEW_CARD_GATHER_PRIORITY_DECK", label: "牌组"),
        AnkiOrderChoice(value: "NEW_CARD_GATHER_PRIORITY_DECK_THEN_RANDOM_NOTES", label: "牌组，然后随机笔记"),
        AnkiOrderChoice(value: "NEW_CARD_GATHER_PRIORITY_LOWEST_POSITION", label: "位置升序"),
        AnkiOrderChoice(value: "NEW_CARD_GATHER_PRIORITY_HIGHEST_POSITION", label: "位置降序"),
        AnkiOrderChoice(value: "NEW_CARD_GATHER_PRIORITY_RANDOM_NOTES", label: "随机笔记"),
        AnkiOrderChoice(value: "NEW_CARD_GATHER_PRIORITY_RANDOM_CARDS", label: "随机卡片"),
    ]
    static let newSort = [
        AnkiOrderChoice(value: "NEW_CARD_SORT_ORDER_TEMPLATE", label: "卡片类型"),
        AnkiOrderChoice(value: "NEW_CARD_SORT_ORDER_NO_SORT", label: "收集顺序"),
        AnkiOrderChoice(value: "NEW_CARD_SORT_ORDER_TEMPLATE_THEN_RANDOM", label: "卡片类型，然后随机"),
        AnkiOrderChoice(value: "NEW_CARD_SORT_ORDER_RANDOM_NOTE_THEN_TEMPLATE", label: "随机笔记，然后卡片类型"),
        AnkiOrderChoice(value: "NEW_CARD_SORT_ORDER_RANDOM_CARD", label: "随机"),
    ]
    static let review = [
        AnkiOrderChoice(value: "REVIEW_CARD_ORDER_DAY", label: "到期日，然后随机"),
        AnkiOrderChoice(value: "REVIEW_CARD_ORDER_DAY_THEN_DECK", label: "到期日，然后牌组"),
        AnkiOrderChoice(value: "REVIEW_CARD_ORDER_DECK_THEN_DAY", label: "牌组，然后到期日"),
        AnkiOrderChoice(value: "REVIEW_CARD_ORDER_INTERVALS_ASCENDING", label: "间隔升序"),
        AnkiOrderChoice(value: "REVIEW_CARD_ORDER_INTERVALS_DESCENDING", label: "间隔降序"),
        AnkiOrderChoice(value: "REVIEW_CARD_ORDER_EASE_ASCENDING", label: "易度升序"),
        AnkiOrderChoice(value: "REVIEW_CARD_ORDER_EASE_DESCENDING", label: "易度降序"),
        AnkiOrderChoice(value: "REVIEW_CARD_ORDER_RETRIEVABILITY_ASCENDING", label: "可提取性升序"),
        AnkiOrderChoice(value: "REVIEW_CARD_ORDER_RETRIEVABILITY_DESCENDING", label: "可提取性降序"),
        AnkiOrderChoice(value: "REVIEW_CARD_ORDER_RELATIVE_OVERDUENESS", label: "相对逾期程度"),
        AnkiOrderChoice(value: "REVIEW_CARD_ORDER_RANDOM", label: "随机"),
        AnkiOrderChoice(value: "REVIEW_CARD_ORDER_ADDED", label: "添加顺序"),
        AnkiOrderChoice(value: "REVIEW_CARD_ORDER_REVERSE_ADDED", label: "添加顺序倒序"),
    ]
}
