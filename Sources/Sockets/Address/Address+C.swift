#if os(Linux)
    import Glibc
    typealias socket_addrinfo = Glibc.addrinfo
#else
    import Darwin
    typealias socket_addrinfo = Darwin.addrinfo
#endif

//Pretty types -> C types

protocol InternetAddressResolver {
    func resolve(_ internetAddress: InternetAddress, with config: inout Config) throws -> Zip2Sequence<[ResolvedInternetAddress],[Config]>
}

// Brief:   Given a hostname and a service this struct returns a list of
//          IP and Port adresses that where obtained during the name resolution
//          e.g. "localhost" and "echo" as arguments will result in a list of
//          IP addresses of the machine that runs the program and port set to 7
//
struct Resolver: InternetAddressResolver {
    
    // config       -   the provided Config object guides the name resolution
    //                  the socketType and protocolType fields control which kind
    //                  kind of socket you want to create.
    //                  E.g. set them to .STREAM .TCP to obtain address for a TCP Stream socket
    //              -   Set the addressFamily field to .UNSPECIFIED if you don't care if the
    //                  name resolution leads to IPv4 or IPv6 addresses.
    func resolve(_ internetAddress: InternetAddress, with config: inout Config) throws -> Zip2Sequence<[ResolvedInternetAddress],[Config]>
    {
        
        //
        // Narrowing down the results we will get from the getaddrinfo call
        //
        var addressCriteria = socket_addrinfo.init()
        // IPv4 or IPv6
        addressCriteria.ai_family = config.addressFamily.toCType()
        addressCriteria.ai_flags = AI_PASSIVE
        addressCriteria.ai_socktype = config.socketType.toCType()
        addressCriteria.ai_protocol = config.protocolType.toCType()
        
        // The list of addresses that correspond to the hostname/service pair.
        // servinfo is the first node in a linked list of addresses that is empty
        // at this line
        var servinfo: UnsafeMutablePointer<socket_addrinfo>? = nil
        // perform resolution
        let ret = getaddrinfo(internetAddress.hostname, internetAddress.port.toString(), &addressCriteria, &servinfo)
        guard ret == 0 else {
            let reason = String(validatingUTF8: gai_strerror(ret)) ?? "?"
            throw SocketsError(.ipAddressValidationFailed(reason))
        }
        
        guard let addrList = servinfo else { throw SocketsError(.ipAddressResolutionFailed) }
        defer {
            freeaddrinfo(addrList)
        }
        
        //this takes the first resolved address
        var currentAddrListItem: UnsafeMutablePointer<addrinfo> = addrList
        
        var addresses: [ResolvedInternetAddress] = []
        var configs: [Config] = []
        while true {
            guard let addrInfo = currentAddrListItem.pointee.ai_addr else {
                throw SocketsError(.ipAddressResolutionFailed)
            }
            let family = try AddressFamily(fromCType: Int32(addrInfo.pointee.sa_family))
            
            let ptr = UnsafeMutablePointer<sockaddr_storage>.allocate(capacity: 1)
            ptr.initialize(to: sockaddr_storage())
            
            switch family {
            case .inet:
                let addr = UnsafeMutablePointer<sockaddr_in>.init(OpaquePointer(addrInfo))!
                let specPtr = UnsafeMutablePointer<sockaddr_in>(OpaquePointer(ptr))
                specPtr.assign(from: addr, count: 1)
            case .inet6:
                let addr = UnsafeMutablePointer<sockaddr_in6>(OpaquePointer(addrInfo))!
                let specPtr = UnsafeMutablePointer<sockaddr_in6>(OpaquePointer(ptr))
                specPtr.assign(from: addr, count: 1)
            default:
                throw SocketsError(.concreteSocketAddressFamilyRequired)
            }
            
            let address = ResolvedInternetAddress(raw: ptr)
            addresses.append(address)
            
            let config = try! Config(addressFamily: address.addressFamily(), socketType: config.socketType, protocolType: config.protocolType)    //TODO: handle error
            configs.append(config)
            
            if let next = currentAddrListItem.pointee.ai_next {
                currentAddrListItem = next
            } else {
                // done checking
                break
            }
        }
        
        return zip(addresses,configs)
    }
}

