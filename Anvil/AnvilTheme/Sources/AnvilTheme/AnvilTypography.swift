import SwiftUI

public struct AnvilTypography: Sendable {
    public var pageTitle: Font
    public var sectionTitle: Font
    public var rowTitle: Font
    public var body: Font
    public var caption: Font
    public var smallCaption: Font
    public var status: Font
    public var code: Font

    public init(
        pageTitle: Font,
        sectionTitle: Font,
        rowTitle: Font,
        body: Font,
        caption: Font,
        smallCaption: Font,
        status: Font,
        code: Font
    ) {
        self.pageTitle = pageTitle
        self.sectionTitle = sectionTitle
        self.rowTitle = rowTitle
        self.body = body
        self.caption = caption
        self.smallCaption = smallCaption
        self.status = status
        self.code = code
    }

    public static let fallback = AnvilTypography(
        pageTitle: .title2.weight(.semibold),
        sectionTitle: .title2.weight(.medium),
        rowTitle: .headline,
        body: .callout,
        caption: .caption,
        smallCaption: .caption2,
        status: .callout,
        code: .system(.caption, design: .monospaced)
    )
}
