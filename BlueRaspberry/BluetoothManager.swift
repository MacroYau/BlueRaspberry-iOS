//
//  BLuetoothManager.swift
//  BlueRaspberry
//
//  Created by Macro Yau on 9/7/2018.
//  Copyright © 2018 Macro Yau. All rights reserved.
//

import Foundation
import CoreBluetooth
import NotificationCenter

extension Notification.Name {
    
    static let didUpdateBluetoothState = Notification.Name("didUpdateBluetoothState")
    static let didDiscoverBluetoothPeripheral = Notification.Name("didDiscoverBluetoothPeripheral")
    
    static let didConnectToBluetoothPeripheral = Notification.Name("didConnectToBluetoothPeripheral")
    static let didDisconnectFromBluetoothPeripheral = Notification.Name("didDisconnectFromBluetoothPeripheral")
    static let didReadBluetoothPeripheralRSSI = Notification.Name("didReadBluetoothPeripheralRSSI")
    
    static let didDiscoverGATTService = Notification.Name("didDiscoverGATTService")
    static let didUpdateValueForGATTCharacteristic = Notification.Name("didUpdateValueForGATTCharacteristic")
    static let didWriteValueForGATTCharacteristic = Notification.Name("didWriteValueForGATTCharacteristic")
    
}

class BluetoothManager: NSObject {
    
    static let shared = BluetoothManager()
    
    private var manager: CBCentralManager!
    
    private var discoveredPeripherals: [CBPeripheral] = []
    private var connectedPeripheral: CBPeripheral?
    
    private var availableServices: [CBService] = []
    private var availableCharacteristics: [CBCharacteristic] = []
    
    private var subscribedCharacteristics: [CBCharacteristic] = []
    
    var isConnected: Bool {
        return connectedPeripheral != nil
    }
    
    var peripheralName: String? {
        get {
            return connectedPeripheral?.name
        }
    }
    
    private override init() {
        super.init()
    }
    
    func prepare() {
        manager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning(services: [String]? = nil, continuous: Bool = false) {
        let servicesUUIDList: [CBUUID]?
        if let services = services {
            servicesUUIDList = services.map { CBUUID(string: $0) }
        } else {
            servicesUUIDList = nil
        }

        var options: [String : Any]? = nil
        if continuous {
            options = [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        }

        manager.scanForPeripherals(withServices: servicesUUIDList, options: options)
    }
    
    func stopScanning() {
        manager.stopScan()
    }
    
    func connect(peripheralUUID uuid: String) {
        if let peripheral = discoveredPeripherals.filter({ $0.identifier.uuidString == uuid }).first {
            self.connectedPeripheral = peripheral
            self.connectedPeripheral?.delegate = self
            manager.connect(peripheral)
        }
    }
    
    func disconnect() {
        if let peripheral = connectedPeripheral {
            manager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func readRSSI() {
        if let peripheral = connectedPeripheral {
            peripheral.readRSSI()
        }
    }
    
    private func characteristic(uuid: String, ofServiceUUID serviceUUID: String) -> CBCharacteristic? {
        if let service = availableServices.filter({ $0.uuid.uuidString == serviceUUID }).first,
            let availableCharacteristics = service.characteristics {
            return availableCharacteristics.filter({ $0.uuid.uuidString == uuid }).first
        } else {
            return nil
        }
    }
    
    func readCharacteristic(uuid: String, ofServiceUUID serviceUUID: String) {
        if let peripheral = connectedPeripheral,
            let characteristic = characteristic(uuid: uuid, ofServiceUUID: serviceUUID) {
            peripheral.readValue(for: characteristic)
        }
    }
    
    func writeCharacteristic(uuid: String, ofServiceUUID serviceUUID: String, value: Data, withResponse: Bool = true) {
        if let peripheral = connectedPeripheral,
            let characteristic = characteristic(uuid: uuid, ofServiceUUID: serviceUUID) {
            peripheral.writeValue(value, for: characteristic, type: withResponse ? .withResponse : .withoutResponse)
        }
    }
    
    func subscribeCharacteristic(uuid: String, ofServiceUUID serviceUUID: String, readImmediately: Bool = false) {
        guard let peripheral = connectedPeripheral else { return }
        
        if let characteristic = characteristic(uuid: uuid, ofServiceUUID: serviceUUID) {
            if readImmediately {
                peripheral.readValue(for: characteristic)
            }
            peripheral.setNotifyValue(true, for: characteristic)
            subscribedCharacteristics += [characteristic]
        }
    }
    
    func unsubscribeCharacteristic(uuid: String) {
        guard let peripheral = connectedPeripheral else { return }
        
        if let characteristic = subscribedCharacteristics.filter({ $0.uuid.uuidString == uuid }).first {
            peripheral.setNotifyValue(false, for: characteristic)
            subscribedCharacteristics = subscribedCharacteristics.filter { $0.uuid.uuidString != uuid }
        }
    }
    
}

extension BluetoothManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let userInfo: [String : Any]? = ["state": central.state]
        NotificationCenter.default.post(name: .didUpdateBluetoothState,
                                        object: self,
                                        userInfo: userInfo)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let uuid = peripheral.identifier
        let discovered = discoveredPeripherals.filter { $0.identifier == uuid }.count > 0
        if (!discovered) {
            discoveredPeripherals += [peripheral]
        }
        
        let userInfo: [String : Any]? = [
            "peripheralUUID": uuid.uuidString,
            "peripheralName": peripheral.name ?? "Unknown",
            "advertisementData": advertisementData,
            "rssi": RSSI.intValue
        ]
        NotificationCenter.default.post(name: .didDiscoverBluetoothPeripheral,
                                        object: self,
                                        userInfo: userInfo)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
        
        let userInfo: [String : Any]? = [
            "peripheralUUID": peripheral.identifier.uuidString,
            "peripheralName": peripheral.name ?? "Unknown"
        ]
        NotificationCenter.default.post(name: .didConnectToBluetoothPeripheral,
                                        object: self,
                                        userInfo: userInfo)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        availableServices = []
        availableCharacteristics = []
        subscribedCharacteristics = []
        connectedPeripheral = nil
        
        let userInfo: [String : Any]? = [
            "peripheralUUID": peripheral.identifier.uuidString,
            "peripheralName": peripheral.name ?? "Unknown"
        ]
        NotificationCenter.default.post(name: .didDisconnectFromBluetoothPeripheral,
                                        object: self,
                                        userInfo: userInfo)
    }
    
}

extension BluetoothManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if availableServices.filter({ $0.uuid == service.uuid }).count == 0 {
            availableServices += [service]
            
            let userInfo: [String : Any]? = [
                "serviceUUID": service.uuid.uuidString
            ]
            NotificationCenter.default.post(name: .didDiscoverGATTService,
                                            object: self,
                                            userInfo: userInfo)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let userInfo: [String : Any]? = [
            "serviceUUID": characteristic.service.uuid.uuidString,
            "characteristicUUID": characteristic.uuid.uuidString,
            "value": characteristic.value ?? Data()
        ]
        NotificationCenter.default.post(name: .didUpdateValueForGATTCharacteristic,
                                        object: self,
                                        userInfo: userInfo)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let userInfo: [String : Any]? = [
            "serviceUUID": characteristic.service.uuid.uuidString,
            "characteristicUUID": characteristic.uuid.uuidString,
            "value": characteristic.value ?? Data()
        ]
        NotificationCenter.default.post(name: .didWriteValueForGATTCharacteristic,
                                        object: self,
                                        userInfo: userInfo)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        let userInfo: [String : Any]? = [
            "peripheralUUID": peripheral.identifier.uuidString,
            "peripheralName": peripheral.name ?? "Unknown",
            "rssi": RSSI.intValue
        ]
        NotificationCenter.default.post(name: .didReadBluetoothPeripheralRSSI,
                                        object: self,
                                        userInfo: userInfo)
    }
    
}
