import Testing
@testable import GalaxyKit

struct LocalNetworkTests {
    private let wifi = LocalNetwork.Interface(name: "en0", address: "10.0.0.5", netmask: "255.255.255.0")

    @Test func detectsHostInSameSubnet() {
        #expect(LocalNetwork.isInSubnet("10.0.0.195", of: wifi))
    }

    @Test func detectsHostInOtherSubnet() {
        #expect(!LocalNetwork.isInSubnet("192.168.1.48", of: wifi))
    }

    @Test func rejectsInvalidAddresses() {
        #expect(LocalNetwork.ipv4("galaxy.local") == nil)
        #expect(!LocalNetwork.isInSubnet("galaxy.local", of: wifi))
    }

    @Test func parsesDefaultGateway() {
        let output = """
           route to: default
        destination: default
               mask: default
            gateway: 10.0.0.195
          interface: en0
        """

        #expect(LocalNetwork.gateway(fromRouteOutput: output) == "10.0.0.195")
        #expect(LocalNetwork.gateway(fromRouteOutput: "route: writing to routing socket: not in table") == nil)
    }
}
