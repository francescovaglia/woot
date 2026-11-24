import Foundation
import Testing
@testable import ChatwootPush

@Suite struct APSEnvironmentTests {
    /// A profile as Xcode embeds it: binary CMS bytes around the XML plist.
    func profile(aps: String) -> Data {
        var data = Data([0x30, 0x82, 0x4e, 0x00, 0x06, 0x09])
        data.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Entitlements</key><dict><key>aps-environment</key><string>\(aps)</string></dict></dict></plist>
        """.utf8))
        data.append(Data([0xa0, 0x82, 0x0d, 0x00]))
        return data
    }

    @Test func developmentProfileMeansSandbox() {
        #expect(APSEnvironment.of(provisioningProfile: profile(aps: "development")) == "development")
    }

    @Test func distributionProfileMeansProduction() {
        #expect(APSEnvironment.of(provisioningProfile: profile(aps: "production")) == "production")
    }

    @Test func noProfileMeansStoreBuild() {
        #expect(APSEnvironment.of(provisioningProfile: nil) == "production")
        #expect(APSEnvironment.of(provisioningProfile: Data([0x30, 0x82])) == "production")
    }
}
