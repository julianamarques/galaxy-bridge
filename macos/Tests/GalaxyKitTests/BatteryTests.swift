import Testing
@testable import GalaxyKit

struct BatteryTests {
    @Test func parsesDumpsysOutput() {
        let output = """
        Current Battery Service state:
          AC powered: false
          USB powered: true
          Wireless powered: false
          status: 2
          health: 2
          present: true
          level: 78
          scale: 100
        """

        #expect(Battery(dumpsys: output) == Battery(level: 78, isCharging: true))
    }

    @Test func treatsFullAsCharging() {
        #expect(Battery(dumpsys: "  status: 5\n  level: 100")?.isCharging == true)
    }

    @Test func detectsDischarging() {
        #expect(Battery(dumpsys: "  status: 3\n  level: 15") == Battery(level: 15, isCharging: false))
    }

    @Test func rejectsOutputWithoutLevel() {
        #expect(Battery(dumpsys: "error: device offline") == nil)
    }
}

struct PhoneCountryTests {
    @Test func readsFirstCountryOfDualSIM() {
        #expect(ADB.firstCountry("br,\n") == "br")
        #expect(ADB.firstCountry(",us\n") == "us")
        #expect(ADB.firstCountry("\n") == nil)
    }
}
