import Foundation
import Testing
@testable import KhaiCleanMac

@Suite struct ExtensionTests {
    @Test func parsesPluginkitBlocks() {
        let output = """
        +    com.google.GeminiMacOS.FinderSync(1.131.04.0)
        \t            Path = /Applications/Gemini.app/Contents/PlugIns/FinderSync.appex
        \t             SDK = com.apple.FinderSync
        \t    Display Name = Gemini Finder

        -    com.jgraph.drawio.desktop.PreviewExtension(31.0.2)
        \t            Path = /Applications/draw.io.app/Contents/PlugIns/Preview.appex
        \t             SDK = com.apple.quicklook.preview
        \t    Display Name = draw.io Preview

             com.apple.SoftwareUpdateSettingsExtensionIntents((null))
        \t            Path = /System/Library/ExtensionKit/Extensions/SoftwareUpdate.appex
        \t             SDK = com.apple.appintents-extension
        """
        let parsed = ExtensionScanner.parse(output)
        #expect(parsed.count == 3)
        #expect(parsed[0].id == "com.google.GeminiMacOS.FinderSync")
        #expect(parsed[0].election == .enabled)
        #expect(parsed[0].kind == .finderSync)
        #expect(parsed[0].appURL?.path == "/Applications/Gemini.app")
        #expect(parsed[1].election == .disabled)
        #expect(parsed[1].kind == .quickLook)
        #expect(parsed[1].version == "31.0.2")
        #expect(parsed[2].version == nil)
        #expect(parsed[2].election == .automatic)
    }

    @Test func findsLegacyPluginsByFolderAndExtension() throws {
        let temp = try TempFolder()
        try temp.folder("Library/QuickLook/Markdown.qlgenerator")
        try temp.folder("Library/Services/Resize Images.workflow")
        try temp.folder("Library/Spotlight/ExtensionsCache")

        let plugins = ExtensionScanner.legacyPlugins(home: temp.url).filter { !$0.isSystem }
        #expect(Set(plugins.map(\.name)) == ["Markdown", "Resize Images"], "Caches and unknown folders are ignored")
    }
}
