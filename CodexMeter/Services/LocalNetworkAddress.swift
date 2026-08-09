import Darwin
import Foundation

enum LocalNetworkAddress {
    static func preferredIPv4Address() -> String? {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return nil }
        defer { freeifaddrs(firstAddress) }

        var candidates: [(priority: Int, address: String)] = []
        var current: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let interface = current?.pointee {
            defer { current = interface.ifa_next }
            guard let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0 else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else {
                continue
            }

            let interfaceName = String(cString: interface.ifa_name)
            let priority: Int
            switch interfaceName {
            case "en0":
                priority = 0
            case "en1":
                priority = 1
            default:
                priority = 2
            }
            candidates.append((priority, String(cString: host)))
        }

        return candidates.sorted { $0.priority < $1.priority }.first?.address
    }
}
