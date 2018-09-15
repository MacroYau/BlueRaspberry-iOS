//
//  BlueRaspberryService.swift
//  BlueRaspberry
//
//  Created by Macro Yau on 18/7/2018.
//  Copyright © 2018 Macro Yau. All rights reserved.
//

import Foundation

struct BlueRaspberryService {
    
    static let uuid = "D3BEC8C1-2B35-40E2-B92B-F9B429F4D3E5"
    
    struct ConnectivityService {
        
        static let uuid = "8F7E321D-DF0A-4096-BB5B-34C267671B06"
        
        enum Characteristics {
            
            case ipAddress
            case ssid
            
            var uuid: String {
                switch self {
                case .ipAddress:
                    return "132D7244-46C0-481B-B947-42F329F6BE55"
                case .ssid:
                    return "EF92DD60-B49C-4874-B93F-018E80FCF818"
                }
            }
            
        }
        
    }
    
    struct WiFiConfigService {
        
        static let uuid = "B2ADB965-76F6-4AFE-9450-2117326A6AFB"
        
        enum Characteristics {
            
            case availableNetworks
            case knownNetworks
            case connectNetwork
            case forgetNetwork
            case wifiSwitch
            
            var uuid: String {
                switch self {
                case .availableNetworks:
                    return "94F76327-6BC8-4B86-A3C5-F96F90574267"
                case .knownNetworks:
                    return "EF0CC4AE-40B0-493F-A5C3-E4BC83F0D8DD"
                case .connectNetwork:
                    return "E5508928-1536-4EF4-9BBD-B9A65C183D03"
                case .forgetNetwork:
                    return "A5DF4BFF-5FEE-43F8-8566-07D9A98EB734"
                case .wifiSwitch:
                    return "640BEF8F-0048-4A65-98BD-287731CF282C"
                }
            }
            
        }
        
    }
    
}
